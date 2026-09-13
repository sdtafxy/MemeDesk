import AppKit
import SwiftUI

// MARK: - 面板尺寸常量
//
// 面板高度是纯算术：padding + header + divider + 列表 + divider + footer + padding。
// SwiftUI 不参与高度协商，素材增删只影响列表那一截 —— 顶部永远不会被顶下去。
enum PanelMetrics {
    static let width: CGFloat = 336
    static let padding: CGFloat = 12
    static let headerHeight: CGFloat = 44
    static let dividerHeight: CGFloat = 1
    static let emptyHeight: CGFloat = 148
    static let rowHeight: CGFloat = 44
    static let rowSpacing: CGFloat = 4
    static let maxListHeight: CGFloat = 300
    static let footerHeight: CGFloat = 100

    static func listHeight(summaryCount: Int) -> CGFloat {
        guard summaryCount > 0 else { return emptyHeight }
        let n = CGFloat(summaryCount)
        return min(n * rowHeight + (n - 1) * rowSpacing, maxListHeight)
    }

    static func panelHeight(summaryCount: Int) -> CGFloat {
        padding + headerHeight + dividerHeight
            + listHeight(summaryCount: summaryCount)
            + dividerHeight + footerHeight + padding
    }

    static func contentSize(summaryCount: Int) -> NSSize {
        NSSize(width: width, height: panelHeight(summaryCount: summaryCount))
    }
}

// MARK: - 面板

struct MenuBarRootView: View {
    @ObservedObject private var stage = Stage.shared
    @ObservedObject private var loc = Localization.shared
    @ObservedObject private var update = UpdateService.shared

    var body: some View {
        VStack(spacing: 0) {
            header
                .frame(height: PanelMetrics.headerHeight)
            divider
            list
                .frame(height: PanelMetrics.listHeight(summaryCount: stage.summaries.count))
            divider
            footer
                .frame(height: PanelMetrics.footerHeight)
        }
        .padding(PanelMetrics.padding)
        .frame(width: PanelMetrics.width,
               height: PanelMetrics.panelHeight(summaryCount: stage.summaries.count))
        .background(MD.canvas)
    }

    private var divider: some View {
        Rectangle()
            .fill(MD.hairline)
            .frame(height: PanelMetrics.dividerHeight)
    }

    // MARK: 头部：图标 + 标题 + 投放按钮

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 34)

            VStack(alignment: .leading, spacing: 1) {
                Text("MemeDesk")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MD.ink)
                Text(stage.globallyPaused
                     ? loc[.paused]
                     : String(format: loc[.onDesktopCount], stage.count))
                    .font(.system(size: 10.5))
                    .foregroundStyle(MD.inkSub)
            }

            Spacer(minLength: 8)

            Button {
                Task { await addFiles() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MD.ink)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: MD.cornerS, style: .continuous)
                        .fill(MD.surface))
            }
            .buttonStyle(.plain)
            .help(loc[.addStickerTip])
        }
    }

    // MARK: 列表 / 空状态

    @ViewBuilder
    private var list: some View {
        if stage.summaries.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: PanelMetrics.rowSpacing) {
                    ForEach(stage.summaries) { summary in
                        StickerRow(summary: summary)
                            .frame(height: PanelMetrics.rowHeight)
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .scrollContentBackground(.hidden)
            .clipShape(RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 26))
                .foregroundStyle(MD.accent)
            Text(loc[.emptyTitle])
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MD.ink)
            Text(loc[.emptyBody])
                .font(.system(size: 11))
                .foregroundStyle(MD.inkSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
            Button(loc[.addFirst]) { Task { await addFiles() } }
                .buttonStyle(MDPrimaryButtonStyle())
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: 底部：六个操作，两行三列

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                footerButton(stage.globallyPaused ? loc[.resume] : loc[.pauseAll],
                             icon: stage.globallyPaused ? "play.fill" : "pause.fill") {
                    stage.toggleGlobalPause()
                }
                footerButton(loc[.library], icon: "square.grid.2x2") {
                    Task { @MainActor in LibraryWindow.show() }
                }
                footerButton(loc[.settings], icon: "gearshape",
                             badge: update.updateAvailable) {
                    Task { @MainActor in SettingsWindow.show() }
                }
            }
            HStack(spacing: 6) {
                let allHidden = stage.summaries.allSatisfy { $0.isHidden }
                footerButton(allHidden ? loc[.showAll] : loc[.hideAll],
                             icon: allHidden ? "eye" : "eye.slash") {
                    if allHidden { stage.showAll() } else { stage.hideAllTemporary() }
                }
                footerButton(loc[.clearDesk], icon: "trash", role: .destructive) {
                    stage.removeAll()
                }
                footerButton(loc[.quit], icon: "power") {
                    Stage.shared.saveNow()
                    NSApp.terminate(nil)
                }
            }
        }
    }

    /// `badge` 只在设置的图标上点一个小圆点表示"有新版"。
    /// 用 overlay 而不是加一行 —— 面板高度是算术常量（`PanelMetrics`），不能被动到。
    private func footerButton(_ title: String, icon: String,
                              role: ButtonRole? = nil,
                              badge: Bool = false,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .overlay(alignment: .topTrailing) {
                        if badge {
                            Circle()
                                .fill(MD.accent)
                                .frame(width: 6, height: 6)
                                .offset(x: 6, y: -2)
                        }
                    }
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
        }
        .buttonStyle(MDIconButtonStyle(role: role))
        .help(badge ? loc[.updateBadgeTip] : title)
    }

    private func addFiles() async {
        let urls = await FilePicker.chooseMedia()
        guard !urls.isEmpty else { return }
        await stage.add(urls: urls)
    }
}

// MARK: - 素材行

private struct StickerRow: View {
    let summary: StickerSummary
    @ObservedObject private var stage = Stage.shared
    @State private var thumb: NSImage?

    var body: some View {
        HStack(spacing: 9) {
            thumbnail
                .frame(width: 30, height: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(summary.name)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(MD.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(rowSubtitle)
                    .font(.system(size: 9.5))
                    .foregroundStyle(MD.inkSub)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            Button {
                stage.setHidden(summary.id, !summary.isHidden)
            } label: {
                Image(systemName: summary.isHidden ? "eye.slash" : "eye")
                    .font(.system(size: 11))
                    .foregroundStyle(MD.inkSub)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(MD.surface))
            }
            .buttonStyle(.plain)

            Button {
                showStickerMenu()
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MD.inkSub)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(MD.surface))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 7)
        .background(
            RoundedRectangle(cornerRadius: MD.cornerS, style: .continuous)
                .fill(MD.surface.opacity(summary.isHidden ? 0.45 : 1))
        )
        .task { await loadThumb() }
    }

    private var rowSubtitle: String {
        var parts = [summary.layerMode.label]
        if summary.motion != .still {
            parts.append(summary.motion.label)
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb {
            Image(nsImage: thumb)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(MD.surfaceActive)
                .overlay(Image(systemName: "photo").font(.system(size: 10)).foregroundStyle(MD.inkSub))
        }
    }

    /// 弹出该素材自己的 NSMenu。弹菜单期间通知状态栏控制器别把手势当成“点外面”。
    @MainActor
    private func showStickerMenu() {
        guard let menu = stage.menu(for: summary.id) else { return }
        StatusBarController.shared.beginMenuSuppression()
        defer { StatusBarController.shared.endMenuSuppression() }
        _ = menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private func loadThumb() async {
        guard let bookmark = stage.config(for: summary.id)?.bookmark,
              let url = Bookmark.url(from: bookmark)
        else { return }
        let image = await ThumbnailCache.shared.image(for: url, kind: MediaProbe.kind(of: url))
        await MainActor.run { thumb = image }
    }
}
