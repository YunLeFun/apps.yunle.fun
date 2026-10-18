import SwiftUI

struct AssistantMarkdown: View {
    let text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(Self.blocks(text).enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let value): Text(Self.inline(value)).textSelection(.enabled)
                case .heading(let value): Text(Self.inline(value)).font(.headline).accessibilityAddTraits(.isHeader)
                case .bullet(let prefix, let value):
                    HStack(alignment: .top, spacing: 8) { Text(verbatim: prefix); Text(Self.inline(value)).textSelection(.enabled) }
                case .quote(let value): Text(Self.inline(value)).foregroundStyle(.secondary).textSelection(.enabled)
                case .code(let value):
                    ScrollView(.horizontal) {
                        Text(verbatim: value).font(.system(.body, design: .monospaced)).textSelection(.enabled).padding(10)
                    }.background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }
    enum Block: Equatable { case paragraph(String), heading(String), bullet(String, String), quote(String), code(String) }
    static func blocks(_ text: String) -> [Block] {
        var result: [Block] = [], paragraph: [String] = [], code: [String] = []
        var inCode = false
        func flush() { if !paragraph.isEmpty { result.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] } }
        for line in text.components(separatedBy: .newlines) {
            if line.hasPrefix("\u{0060}\u{0060}\u{0060}") {
                flush()
                if inCode { result.append(.code(code.joined(separator: "\n"))); code = [] }
                inCode.toggle(); continue
            }
            if inCode { code.append(line); continue }
            if line.isEmpty { flush(); continue }
            if line.hasPrefix("#"), let space = line.firstIndex(of: " "), line[..<space].allSatisfy({ $0 == "#" }) {
                flush(); result.append(.heading(String(line[line.index(after: space)...]))); continue
            }
            if line.hasPrefix("- ") || line.hasPrefix("* ") {
                flush(); result.append(.bullet("•", String(line.dropFirst(2)))); continue
            }
            if let end = line.range(of: #"^[0-9]{1,3}\. "#, options: .regularExpression) {
                flush(); result.append(.bullet(String(line[end].dropLast()), String(line[end.upperBound...]))); continue
            }
            if line.hasPrefix("> ") { flush(); result.append(.quote(String(line.dropFirst(2)))); continue }
            paragraph.append(line)
        }
        flush()
        if inCode { result.append(.code(code.joined(separator: "\n"))) }
        return result
    }
    static func inline(_ text: String) -> AttributedString {
        var value = (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
        for run in value.runs {
            if let link = run.link, !safeLink(link) { value[run.range].link = nil }
        }
        return value
    }
    static func safeLink(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }
}
