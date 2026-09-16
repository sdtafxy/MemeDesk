import AppKit
import SwiftUI

/// 设置页的「菜单栏图标」分区：从一组矢量图案里挑一个当菜单栏按钮。
///
/// 预览用的就是菜单栏那份绘制代码（`MenuBarIcon.image`），按模板图渲染成当前文字色，
/// 所以**所见即所得** —— 不会出现"设置里好看、菜单栏里变形"这种事。
struct MenuBarIconSection: View {
    @ObservedObject private var stage = Stage.shared
    @ObservedObject private var loc = Localization.shared

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        Section(loc[.menuBarIcon]) {
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(MenuBarIcon.allCases) { icon in
                    cell(for: icon)
                }
            }
            .padding(.vertical, 2)

            Text(loc[.menuBarIconHint])
                .font(MD.fontCaption)
                .foregroundStyle(MD.inkSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func cell(for icon: MenuBarIcon) -> some View {
        let selected = stage.preferences.menuBarIcon == icon
        return Button {
            stage.preferences.menuBarIcon = icon
        } label: {
            VStack(spacing: 7) {
                Image(nsImage: icon.image(pointSize: 26))
                    .renderingMode(.template)
                    .foregroundStyle(selected ? MD.accent : MD.ink)
                Text(loc[Self.labelKey(icon)])
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(selected ? MD.accent : MD.inkSub)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .background(
                RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous)
                    .fill(selected ? MD.accent.opacity(0.12) : MD.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous)
                    .strokeBorder(selected ? MD.accent : .clear, lineWidth: 1.5)
            )
            .contentShape(RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(loc[Self.labelKey(icon)])
        .accessibilityLabel(loc[Self.labelKey(icon)])
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    /// 图案 → 文案键。刻意放在视图层，让 `MenuBarIcon.swift` 保持零 SwiftUI 依赖
    /// （那样它才能被单独编译出来做目视校对）。
    private static func labelKey(_ icon: MenuBarIcon) -> LKey {
        switch icon {
        case .smile: return .iconSmile
        case .grin: return .iconGrin
        case .wink: return .iconWink
        case .surprised: return .iconSurprised
        case .cool: return .iconCool
        case .love: return .iconLove
        case .sad: return .iconSad
        case .angry: return .iconAngry
        }
    }
}
