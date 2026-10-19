import SwiftUI

/// 设置类列表行的图标：系统“设置”同款圆角色块上的白色 SF Symbol，颜色用于区分分组入口。
struct SettingsIcon: View {
    let systemImage: String
    let color: Color
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 29
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.5, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color, in: RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .opacity(isEnabled ? 1 : 0.4)
            .accessibilityHidden(true)
    }
}

/// 带彩色图标的设置行标签；辅助字号下省去装饰图标，保留完整文案。
struct SettingsLabel: View {
    let title: String
    let systemImage: String
    let color: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ title: String, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Text(title)
        } else {
            Label { Text(title) } icon: { SettingsIcon(systemImage: systemImage, color: color) }
        }
    }
}
