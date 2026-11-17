import CoreImage.CIFilterBuiltins
import SwiftUI

enum ApplicationShareAppearance: String, CaseIterable, Identifiable {
    case light, dark
    var id: Self { self }
    var title: String { self == .light ? "浅色" : "深色" }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

enum ApplicationShareCardError: LocalizedError {
    case missingWebsite, renderingFailed
    var errorDescription: String? {
        switch self {
        case .missingWebsite: return "这个应用暂未提供可分享的网站地址。仍可分享云乐坊链接。"
        case .renderingFailed: return "暂时无法生成分享卡片，请重试。"
        }
    }
}

enum ApplicationShareQRCode {
    /// Keep the original websiteUrl bytes, including query and fragment. A
    /// canonical launchURL or a market link is a different sharing contract.
    static func payload(for application: CloudApplication) throws -> String {
        guard let raw = application.shareWebsitePayload else { throw ApplicationShareCardError.missingWebsite }
        return raw
    }

    static func image(for application: CloudApplication) throws -> UIImage {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(try payload(for: application).utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let code = CIContext().createCGImage(output, from: output.extent, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()),
              let data = code.dataProvider?.data else {
            throw ApplicationShareCardError.renderingFailed
        }
        let bytes = [UInt8](data as Data)
        guard code.bitsPerPixel == 32, bytes.count >= code.bytesPerRow * code.height else { throw ApplicationShareCardError.renderingFailed }
        func original(_ x: Int, _ y: Int) -> Bool {
            let offset = y * code.bytesPerRow + x * 4
            return min(bytes[offset], bytes[offset + 1], bytes[offset + 2]) < 128
        }
        // Read the genuine encoded matrix. Trim only Core Image's existing
        // border, then add exactly four white modules around the styled code.
        var minX = code.width, minY = code.height, maxX = 0, maxY = 0
        for y in 0..<code.height { for x in 0..<code.width where original(x, y) {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        } }
        let count = maxX - minX + 1
        guard count >= 21, count == maxY - minY + 1, (count - 21) % 4 == 0 else { throw ApplicationShareCardError.renderingFailed }
        func black(_ x: Int, _ y: Int) -> Bool {
            x >= 0 && y >= 0 && x < count && y < count && original(x + minX, y + minY)
        }
        func finder(_ x: Int, _ y: Int) -> Bool {
            (x < 7 && y < 7) || (x >= count - 7 && y < 7) || (x < 7 && y >= count - 7)
        }
        // Adjacent modules share one path, so there are no antialias seams.
        // Only exposed corners soften; timing modules retain their square mass.
        let path = UIBezierPath()
        for y in 0..<count { for x in 0..<count where black(x, y) && !finder(x, y) {
            let px = CGFloat(x), py = CGFloat(y), radius: CGFloat = x == 6 || y == 6 ? 0.08 : 0.45
            let a: CGFloat = !black(x - 1, y) && !black(x, y - 1) ? radius : 0
            let b: CGFloat = !black(x + 1, y) && !black(x, y - 1) ? radius : 0
            let c: CGFloat = !black(x + 1, y) && !black(x, y + 1) ? radius : 0
            let d: CGFloat = !black(x - 1, y) && !black(x, y + 1) ? radius : 0
            path.move(to: CGPoint(x: px + a, y: py))
            path.addLine(to: CGPoint(x: px + 1 - b, y: py))
            path.addQuadCurve(to: CGPoint(x: px + 1, y: py + b), controlPoint: CGPoint(x: px + 1, y: py))
            path.addLine(to: CGPoint(x: px + 1, y: py + 1 - c))
            path.addQuadCurve(to: CGPoint(x: px + 1 - c, y: py + 1), controlPoint: CGPoint(x: px + 1, y: py + 1))
            path.addLine(to: CGPoint(x: px + d, y: py + 1))
            path.addQuadCurve(to: CGPoint(x: px, y: py + 1 - d), controlPoint: CGPoint(x: px, y: py + 1))
            path.addLine(to: CGPoint(x: px, y: py + a))
            path.addQuadCurve(to: CGPoint(x: px + a, y: py), controlPoint: CGPoint(x: px, y: py))
            path.close()
        } }
        // Render above export resolution so rounded contours downsample cleanly.
        let module: CGFloat = 16, quiet: CGFloat = 4
        let side = (CGFloat(count) + quiet * 2) * module
        let format = UIGraphicsImageRendererFormat(); format.scale = 1; format.opaque = true
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: side, height: side))
            context.cgContext.translateBy(x: quiet * module, y: quiet * module)
            context.cgContext.scaleBy(x: module, y: module)
            UIColor.black.setFill(); path.fill()
            for (x, y) in [(0, 0), (count - 7, 0), (0, count - 7)] {
                let px = CGFloat(x), py = CGFloat(y)
                let origin = CGPoint(x: px, y: py)
                UIColor.black.setFill()
                UIBezierPath(roundedRect: CGRect(origin: origin, size: CGSize(width: 7, height: 7)), cornerRadius: 1.65).fill()
                UIColor.white.setFill()
                UIBezierPath(roundedRect: CGRect(x: px + 1, y: py + 1, width: 5, height: 5), cornerRadius: 1).fill()
                UIColor.black.setFill()
                UIBezierPath(roundedRect: CGRect(x: px + 2, y: py + 2, width: 3, height: 3), cornerRadius: 0.7).fill()
            }
        }
    }
}

/// The exported material is baked into one deterministic composition: the
/// system's live backdrop glass is reserved for controls, not offscreen PNGs.
struct ApplicationShareCard: View {
    static let size = CGSize(width: 360, height: 540)
    static let qrSide: CGFloat = 160
    let application: CloudApplication
    let appearance: ApplicationShareAppearance
    let qrImage: UIImage
    let icon: UIImage?
    private var dark: Bool { appearance == .dark }
    private var ink: Color { dark ? Color(white: 0.97) : Color(white: 0.10) }
    private var secondary: Color { dark ? Color(white: 0.67) : Color(white: 0.43) }
    private var accent: Color { ApplicationShareTheme(hex: application.themeColor).color }
    private var websiteHost: String {
        application.shareWebsitePayload.flatMap { URL(string: $0)?.host } ?? ""
    }

    var body: some View {
        ZStack {
            backdrop
            glassPanel
            VStack(spacing: 0) {
                iconView
                    .frame(width: 84, height: 84)
                    .clipShape(RoundedRectangle(cornerRadius: 21, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 21, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .white.opacity(0.04), .white.opacity(0.13)],
                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7)
                    }
                    .shadow(color: .black.opacity(dark ? 0.35 : 0.13), radius: 13, y: 9)
                Text(application.name)
                    .font(.system(size: 30, weight: .semibold, design: .rounded))
                    .tracking(-0.6).foregroundStyle(ink).multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.7)
                    .frame(height: 43).padding(.top, 17)
                Text(application.summary)
                    .font(.system(size: 12.5)).foregroundStyle(secondary)
                    .multilineTextAlignment(.center).lineSpacing(4).lineLimit(2)
                    .truncationMode(.tail).frame(height: 42, alignment: .top)
                    .padding(.top, 8).padding(.horizontal, 14)
                qrPlate.padding(.top, 21)
                Text("扫码打开 · \(websiteHost)")
                    .font(.system(size: 10, weight: .regular)).foregroundStyle(secondary)
                    .lineLimit(1).minimumScaleFactor(0.7).padding(.top, 16)
                Text("云乐坊 YunLeFun")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .tracking(0.3).foregroundStyle(secondary).padding(.top, 9)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 43).padding(.top, 57).padding(.bottom, 39)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipped()
        .environment(\.colorScheme, appearance.colorScheme)
        .environment(\.dynamicTypeSize, .large)
    }

    private var backdrop: some View {
        ZStack {
            LinearGradient(colors: dark ? [Color(white: 0.115), Color(white: 0.035), Color(white: 0.065)]
                                       : [Color(white: 0.94), Color(white: 0.88), Color(white: 0.96)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            // A neutral light source gives the glass depth without painting it
            // with the app's accent. Theme color remains a small, diffused halo.
            Ellipse().fill(.white.opacity(dark ? 0.13 : 0.55))
                .frame(width: 230, height: 90).blur(radius: 40).rotationEffect(.degrees(-36))
                .offset(x: -112, y: -176)
            Circle().fill(accent.opacity(dark ? 0.17 : 0.14))
                .frame(width: 130, height: 130).blur(radius: 48).offset(x: 137, y: -175)
            Circle().fill(accent.opacity(dark ? 0.065 : 0.06))
                .frame(width: 120, height: 120).blur(radius: 48).offset(x: -140, y: 203)
            refraction.stroke(.white.opacity(dark ? 0.06 : 0.45), lineWidth: 24)
                .blur(radius: 12)
        }
    }

    private var refraction: Path {
        Path { path in
            path.move(to: CGPoint(x: -100, y: 280))
            path.addCurve(to: CGPoint(x: 258, y: -70),
                          control1: CGPoint(x: 80, y: 254), control2: CGPoint(x: 73, y: 34))
        }
    }

    private var glassPanel: some View {
        let shape = RoundedRectangle(cornerRadius: 38, style: .continuous)
        return shape
            .fill(LinearGradient(stops: [
                .init(color: .white.opacity(dark ? 0.085 : 0.56), location: 0),
                .init(color: .white.opacity(dark ? 0.028 : 0.24), location: 0.48),
                .init(color: .white.opacity(dark ? 0.045 : 0.38), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .background {
                shape.fill(.black.opacity(dark ? 0.09 : 0.015))
                    .shadow(color: .black.opacity(dark ? 0.42 : 0.15), radius: 22, x: 0, y: 18)
            }
            .overlay {
                shape.strokeBorder(LinearGradient(stops: [
                    .init(color: .white.opacity(dark ? 0.60 : 0.95), location: 0),
                    .init(color: .white.opacity(dark ? 0.09 : 0.35), location: 0.23),
                    .init(color: .white.opacity(0.025), location: 0.55),
                    .init(color: .white.opacity(dark ? 0.20 : 0.70), location: 1)
                ], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.8)
            }
            .overlay {
                shape.inset(by: 2).strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.10 : 0.36),
                    .clear, .black.opacity(dark ? 0.24 : 0.05)], startPoint: .top, endPoint: .bottom), lineWidth: 0.6)
            }
            .overlay(alignment: .top) {
                Capsule().fill(LinearGradient(colors: [.clear, .white.opacity(dark ? 0.48 : 0.9), .clear],
                    startPoint: .leading, endPoint: .trailing))
                    .frame(width: 125, height: 0.75).padding(.top, 0.5).offset(x: -40)
            }
            .padding(.horizontal, 22).padding(.vertical, 24)
    }

    private var qrPlate: some View {
        Image(uiImage: qrImage).interpolation(.high).resizable().scaledToFit()
            .frame(width: Self.qrSide, height: Self.qrSide)
            .background(.white)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .padding(7)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.90), .white.opacity(dark ? 0.055 : 0.24)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.035), .white.opacity(0.2)],
                                startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65)
                    }
            }
            .shadow(color: .black.opacity(dark ? 0.28 : 0.11), radius: 13, y: 9)
            .accessibilityLabel("\(application.name)的网站二维码")
    }

    @ViewBuilder private var iconView: some View {
        if let icon {
            Image(uiImage: icon).resizable().scaledToFit().background(dark ? Color(white: 0.17) : .white)
        } else {
            ZStack {
                dark ? Color(white: 0.19) : .white
                if let emoji = application.emoji?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty {
                    Text(emoji).font(.system(size: 40))
                } else {
                    Image(systemName: "app").font(.system(size: 34, weight: .light)).foregroundStyle(secondary)
                }
            }
        }
    }
}

struct ApplicationShareTheme: Equatable {
    static let defaultHex = "#7898B6"
    let hex: String

    init(hex: String?) {
        let value = hex?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil {
            self.hex = value.uppercased()
        } else if value.range(of: "^#[0-9a-fA-F]{3}$", options: .regularExpression) != nil {
            self.hex = "#" + value.dropFirst().map { "\($0)\($0)" }.joined().uppercased()
        } else { self.hex = Self.defaultHex }
    }

    var color: Color {
        let value = UInt32(hex.dropFirst(), radix: 16)!
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

@MainActor
enum ApplicationShareCardRenderer {
    static func image(application: CloudApplication, appearance: ApplicationShareAppearance, icon: UIImage?) throws -> UIImage {
        let qr = try ApplicationShareQRCode.image(for: application)
        let renderer = ImageRenderer(content: ApplicationShareCard(application: application, appearance: appearance, qrImage: qr, icon: icon))
        renderer.scale = 3
        renderer.isOpaque = true
        guard let image = renderer.uiImage else { throw ApplicationShareCardError.renderingFailed }
        return image
    }
}
