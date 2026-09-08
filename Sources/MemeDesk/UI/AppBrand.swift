import AppKit
import SwiftUI

// MARK: - 品牌资源

/// App 图标在程序内的统一入口：Finder 里的图标、菜单栏按钮、
/// 欢迎页、菜单栏面板、设置页全都读这里，保证永远同步。
enum AppBrand {

    /// 从 bundle 里读 AppIcon.png（Scripts/make_icon.py 生成，build.sh 负责复制）。
    static func image() -> NSImage? {
        if let bundled = Bundle.main.image(forResource: "AppIcon") {
            return bundled
        }
        // 从 SwiftPM 直接 swift run 时没有打包资源；再兜一层运行中的 App 图标。
        if let appIcon = NSApp.applicationIconImage, appIcon.size.width > 1 {
            return appIcon
        }
        return nil
    }

    /// 菜单栏按钮用的图标：渲染成固定点数的正方形，非模板（保留彩色笑脸）。
    static func menuBarImage(pointSize: CGFloat = 17) -> NSImage? {
        guard let base = image() else { return nil }
        let target = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: target, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
            return true
        }
        image.isTemplate = false
        return image
    }
}

/// 程序内显示品牌图标的地方（欢迎页 / 面板头 / 设置页）都用这个视图。
struct BrandMark: View {
    var size: CGFloat = 44

    var body: some View {
        if let ns = AppBrand.image() {
            Image(nsImage: ns)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: size, height: size)
        } else {
            // 最终兜底：没有图标资源也不能开天窗
            RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                .fill(LinearGradient(colors: [MD.sunshine, MD.accent],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "face.smiling")
                        .font(.system(size: size * 0.5))
                        .foregroundStyle(.white)
                )
        }
    }
}
