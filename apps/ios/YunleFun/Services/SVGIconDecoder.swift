import CoreGraphics
import Foundation
import SwiftDraw

enum ApplicationImageError: Error { case invalid, oversized, unavailable }

enum SVGIconDecoder {
    static func decode(_ data: Data, maximumPixelSize: Int) throws -> CGImage {
        try Task.checkCancellation()
        guard !data.isEmpty, data.count <= 2 * 1024 * 1024 else { throw ApplicationImageError.oversized }
        let policy = SVGResourcePolicy()
        guard policy.accepts(data), let svg = SVG(data: data),
              svg.size.width.isFinite, svg.size.height.isFinite,
              svg.size.width > 0, svg.size.height > 0,
              max(svg.size.width, svg.size.height) <= 100_000
        else { throw ApplicationImageError.invalid }
        let edge = CGFloat(min(2048, max(1, maximumPixelSize)))
        let scale = edge / max(svg.size.width, svg.size.height)
        let width = max(1, Int((svg.size.width * scale).rounded()))
        let height = max(1, Int((svg.size.height * scale).rounded()))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw ApplicationImageError.invalid }
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: 1, y: -1)
        context.draw(svg, in: CGRect(x: 0, y: 0, width: width, height: height))
        try Task.checkCancellation()
        guard let result = context.makeImage() else { throw ApplicationImageError.invalid }
        return result
    }
}

// Parse once before the rendering library: no script, external resources, DTD or recursive reference expansion.
private final class SVGResourcePolicy: NSObject, XMLParserDelegate {
    private var stack: [Int] = []
    private var children: [[Int]] = []
    private var ids: [String: Int] = [:]
    private var references: [(Int, String)] = []
    private var styleContent: [Int: String] = [:]
    private var accepted = true
    private var foundRoot = false

    func accepts(_ data: Data) -> Bool {
        guard let xml = String(data: data, encoding: .utf8),
              xml.range(of: "<!DOCTYPE", options: .caseInsensitive) == nil,
              xml.range(of: "<!ENTITY", options: .caseInsensitive) == nil else { return false }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false; parser.shouldProcessNamespaces = true; parser.delegate = self
        guard parser.parse(), accepted, foundRoot, stack.isEmpty else { return false }
        for (from, id) in references {
            guard let target = ids[id] else { return false }
            children[from].append(target)
        }
        var costs: [Int: Int] = [:], visiting = Set<Int>()
        func cost(_ node: Int) -> Int? {
            if let value = costs[node] { return value }
            guard visiting.count < 64, visiting.insert(node).inserted else { return nil }
            var value = 1
            for child in children[node] {
                guard let next = cost(child), value + next <= 50_000 else { return nil }
                value += next
            }
            visiting.remove(node); costs[node] = value
            return value
        }
        return cost(0) != nil
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard accepted else { return }
        let name = elementName.lowercased()
        guard (namespaceURI == nil || namespaceURI == "" || namespaceURI == "http://www.w3.org/2000/svg"),
              !["script", "foreignobject", "animate", "animatetransform", "animatemotion", "set", "image"].contains(name),
              stack.count < 32, children.count < 5_000,
              !stack.isEmpty || name == "svg" else { reject(parser); return }
        let index = children.count
        children.append([])
        if let parent = stack.last { children[parent].append(index) }
        stack.append(index); foundRoot = true
        if name == "style" { styleContent[index] = "" }
        for (key, raw) in attributeDict {
            let key = key.lowercased()
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.hasPrefix("on"), value.count <= 300_000 else { reject(parser); return }
            if key == "id" {
                guard ids[value] == nil else { reject(parser); return }
                ids[value] = index
            }
            if key == "href" || key == "xlink:href" {
                guard value.hasPrefix("#"), value.count > 1 else { reject(parser); return }
                references.append((index, String(value.dropFirst())))
            }
            scanURLs(value, node: index, parser: parser)
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if let node = stack.last, let text = styleContent[node],
           text.range(of: #"url\s*\(|@import"#, options: [.regularExpression, .caseInsensitive]) != nil {
            // CSS resource references can create inheritance cycles outside the explicit element graph.
            reject(parser); return
        }
        if !stack.isEmpty { stack.removeLast() }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if let node = stack.last {
            if styleContent[node] != nil { styleContent[node, default: ""] += string }
            scanURLs(string, node: node, parser: parser)
        }
    }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let text = String(data: CDATABlock, encoding: .utf8), let node = stack.last else { reject(parser); return }
        if styleContent[node] != nil { styleContent[node, default: ""] += text }
        scanURLs(text, node: node, parser: parser)
    }
    private func scanURLs(_ text: String, node: Int, parser: XMLParser) {
        if text.range(of: "@import", options: .caseInsensitive) != nil { reject(parser); return }
        let pattern = #"url\s*\(\s*['"]?([^)'"\s]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { reject(parser); return }
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { reject(parser); return }
            let value = String(text[range])
            guard value.hasPrefix("#"), value.count > 1 else { reject(parser); return }
            references.append((node, String(value.dropFirst())))
        }
    }
    private func reject(_ parser: XMLParser) { accepted = false; parser.abortParsing() }
}
