import SwiftUI

// MARK: - 设计基元
//
// 全应用只有这一套颜色 / 圆角 / 字号 / 按钮样式：
// 菜单栏面板、欢迎页、设置、素材库共用，保证观感统一。
// 设计语言：纯白（深色下近黑）底 + 灰色块按钮，品牌橙只用在主操作和点睛处。
enum MD {

    // MARK: 颜色（明暗两套，跟随系统）

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255.0,
                           green: CGFloat((hex >> 8) & 0xFF) / 255.0,
                           blue: CGFloat(hex & 0xFF) / 255.0,
                           alpha: 1)
        })
    }

    /// 窗口底色：浅色纯白，深色近黑。
    static let canvas = dynamic(0xFFFFFF, 0x17171A)
    /// 卡片 / 按钮的灰色块。
    static let surface = dynamic(0xF2F2F5, 0x26262B)
    /// 按钮按下 / 悬停时的灰色块。
    static let surfaceActive = dynamic(0xE6E6EB, 0x323238)
    /// 描边、分隔线。
    static let hairline = dynamic(0xE4E4E9, 0x333339)
    /// 主文字。
    static let ink = dynamic(0x1C1C21, 0xF4F4F6)
    /// 次要文字。
    static let inkSub = dynamic(0x85858F, 0x9C9CA6)

    /// 品牌橙（和 App 图标同族），只给主按钮和高亮元素。
    static let accent = dynamic(0xFF7A2E, 0xFF8A46)
    /// 品牌橙的按下态。
    static let accentActive = dynamic(0xF06A1E, 0xE0722F)
    /// 品牌黄（点缀用）。
    static let sunshine = dynamic(0xFFC53D, 0xFFC53D)

    // MARK: 形状

    static let cornerS: CGFloat = 8
    static let cornerM: CGFloat = 11
    static let cornerL: CGFloat = 16

    // MARK: 字号

    static let fontTitle = Font.system(size: 16, weight: .bold)
    static let fontBody = Font.system(size: 12.5)
    static let fontBodyMedium = Font.system(size: 12.5, weight: .medium)
    static let fontCaption = Font.system(size: 11)
    static let fontButton = Font.system(size: 11.5, weight: .medium)
}

// MARK: - 按钮

/// 灰色块按钮：应用的默认按钮，次要操作全部用它。
struct MDButtonStyle: ButtonStyle {
    var compact = false
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MD.fontButton)
            .foregroundStyle(configuration.isPressed ? MD.inkSub : MD.ink)
            .lineLimit(1)
            .padding(.horizontal, compact ? 9 : 13)
            .frame(height: compact ? 24 : 28)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: MD.cornerS, style: .continuous)
                    .fill(configuration.isPressed ? MD.surfaceActive : MD.surface)
            )
            .contentShape(RoundedRectangle(cornerRadius: MD.cornerS, style: .continuous))
    }
}

/// 品牌橙按钮：每个界面最多一个，留给最重要的操作。
struct MDPrimaryButtonStyle: ButtonStyle {
    var fullWidth = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MD.fontButton)
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: MD.cornerS, style: .continuous)
                    .fill(configuration.isPressed ? MD.accentActive : MD.accent)
            )
            .contentShape(RoundedRectangle(cornerRadius: MD.cornerS, style: .continuous))
    }
}

/// 图标方按钮：菜单栏面板底部的六宫格、行内的小图标按钮。
struct MDIconButtonStyle: ButtonStyle {
    var role: ButtonRole? = nil

    private var fg: Color {
        role == .destructive ? Color(nsColor: .systemRed) : MD.ink
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(configuration.isPressed ? MD.inkSub : fg)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous)
                    .fill(configuration.isPressed ? MD.surfaceActive : MD.surface)
            )
            .contentShape(RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous))
    }
}

// MARK: - 通用小组件

/// 带图标的一行说明文字。欢迎页、空状态共用，行高固定，间距永远一致。
struct MDTipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(MD.accent)
                .frame(width: 20)
            Text(text)
                .font(MD.fontBody)
                .foregroundStyle(MD.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 26)
    }
}

/// 分区标题（设置页、素材库）。
struct MDSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(MD.inkSub)
            .textCase(nil)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
