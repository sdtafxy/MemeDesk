import AppKit

/// 菜单栏图标的分组。设置页按组成列，方便以后继续加。
enum MenuBarIconGroup: String, CaseIterable, Identifiable, Sendable {
    case faces
    case jimi

    var id: String { rawValue }

    var icons: [MenuBarIcon] {
        MenuBarIcon.allCases.filter { $0.group == self }
    }
}

/// 菜单栏按钮的图标。
///
/// 设计要点：
///
/// 1. **实心剪影 + 镂空五官。** 图案是一块实心色块，眼睛和嘴是**挖空**出来的。
///    没有外描边 —— 描边版在 16pt 上会显得毛糙，实心块边缘更干净，
///    观感也更接近系统自带图标。
/// 2. **模板图（`isTemplate = true`）。** 绘制时只填黑色，实际颜色交给系统：
///    浅色菜单栏渲染成黑、深色渲染成白，按下时自动反色。所谓"白色 + 透明"，
///    关键在 alpha，不在颜色。
/// 3. **画满画布。** 圆形脸的直径约占画布 86%，与 SF Symbols 在菜单栏里的视觉大小对齐。
/// 4. **矢量绘制。** 在 24×24 的逻辑网格里画，再统一缩放到目标点数；
///    因为缩放发生在 CTM 上，**线宽也一起缩放**，所以只用一套数字就够。
///
/// 这个文件**只依赖 AppKit**（不引用 `LKey`／SwiftUI），
/// 所以能单独 `swiftc` 编译出来把每个图标 dump 成 PNG 做目视校对 ——
/// 菜单栏截不了图，那是唯一能验证形状的手段。改图形时请保持这个性质。
enum MenuBarIcon: String, CaseIterable, Identifiable, Codable, Sendable {

    // 笑脸
    case smile
    case grin
    case wink
    case surprised
    case cool
    case love
    case sad
    case angry

    // 基米（用户提供的猫头像重绘）
    case jimiSmile
    case jimiFacepalm

    var id: String { rawValue }

    var group: MenuBarIconGroup {
        switch self {
        case .smile, .grin, .wink, .surprised, .cool, .love, .sad, .angry:
            return .faces
        case .jimiSmile, .jimiFacepalm:
            return .jimi
        }
    }

    /// 找不到／解析失败时用的那个。与 App 图标同款。
    static let fallback: MenuBarIcon = .smile

    /// 从持久化的字符串还原，未知值一律回落到默认，绝不返回 nil。
    static func stored(_ raw: String) -> MenuBarIcon {
        MenuBarIcon(rawValue: raw) ?? fallback
    }

    /// 渲染成模板图。`pointSize` 是画布边长（点）。
    ///
    /// 「基米」那两个是**从照片量化出来的四级灰度图**（暗处实心、亮处透明），
    /// 其余走矢量。两者都是模板图，颜色交给系统。
    func image(pointSize: CGFloat = 18) -> NSImage {
        if let bitmap = Self.decodedBitmap(self) {
            bitmap.size = NSSize(width: pointSize, height: pointSize)
            return bitmap
        }
        let size = NSSize(width: pointSize, height: pointSize)
        // flipped: true → 坐标系原点在左上、y 向下，和写 SVG 时一致，省得每处都要翻符号。
        let image = NSImage(size: size, flipped: true) { _ in
            Self.draw(self, in: pointSize)
            return true
        }
        image.isTemplate = true
        return image
    }

    /// 内嵌的 4 级 alpha 数据 → 模板图。返回 nil 表示这个图案走矢量。
    ///
    /// 数据由 `Scripts/make_menubar_icons.py` 从照片生成，2bit/像素打包后 base64。
    /// 打包而不是带 PNG 资源，是为了让 App 里不多一份资源、这个文件也仍然只依赖 AppKit ——
    /// 那样才能单独 `swiftc` 出来 dump 成 PNG 做目视校对。
    private static func decodedBitmap(_ icon: MenuBarIcon) -> NSImage? {
        guard let encoded = bitmapData(for: icon) else { return nil }
        let side = MenuBarIconBitmaps.side
        guard let data = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              data.count >= side * side / 4,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                         pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                         isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0),
              let pixels = rep.bitmapData
        else { return nil }

        let rowBytes = rep.bytesPerRow
        for y in 0..<side {
            for x in 0..<side {
                let index = y * side + x
                let byte = data[index >> 2]
                let level = (byte >> UInt8((3 - (index & 3)) * 2)) & 0b11
                let offset = y * rowBytes + x * 4
                pixels[offset] = 0
                pixels[offset + 1] = 0
                pixels[offset + 2] = 0
                pixels[offset + 3] = level * 85        // 0 / 85 / 170 / 255
            }
        }

        rep.size = NSSize(width: 18, height: 18)
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    /// 哪些图案有照片量化数据。
    private static func bitmapData(for icon: MenuBarIcon) -> String? {
        switch icon {
        case .jimiSmile: return MenuBarIconBitmaps.jimiSmile
        case .jimiFacepalm: return MenuBarIconBitmaps.jimiFacepalm
        default: return nil
        }
    }

    // MARK: - 绘制
    //
    // 全部图形都画在 24×24 的逻辑网格里，最后统一按 pointSize 缩放。

    private static let grid: CGFloat = 24

    /// 圆形脸：圆心、半径。
    private static let faceCenter: CGFloat = 12
    private static let faceRadius: CGFloat = 10.3
    /// 五官线宽（弧线类：嘴、眼、眉毛）。
    private static let featureStroke: CGFloat = 2.2
    /// 眼睛位置。
    private static let eyeY: CGFloat = 9.6
    private static let eyeDX: CGFloat = 3.6
    private static let dotEyeRadius: CGFloat = 1.75

    private static func draw(_ icon: MenuBarIcon, in size: CGFloat) {
        let transform = NSAffineTransform()
        transform.scale(by: size / grid)
        transform.concat()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // ① 实心剪影。可以是好几块互相重叠的图形 —— 反正都在同一种颜色里，重叠没有副作用。
        NSColor.black.setFill()
        for shape in silhouette(for: icon) { shape.fill() }

        // ② 切到擦除模式，把五官"挖"出来。
        //
        // 为什么用混合模式而不是把描边转成路径去凑 even-odd：后者要 `NSBezierPath.cgPath`，
        // 那是 macOS 14 才有的 API，而本项目的部署目标是 macOS 13（实测会直接编译失败）。
        // 擦除模式还有个额外好处 —— **挖两次和挖一次等价**，所以五官之间哪怕重叠也不会出脏点。
        //
        // 这个混合只作用在 NSImage 自己的后备位图上（懒绘制的图会先渲进一块带 alpha 的
        // 位图），不受最终贴到哪里影响 —— 模板图需要的正是那份 alpha。
        ctx.setBlendMode(.clear)
        paint(erase(for: icon))
    }

    private static func paint(_ features: [Feature]) {
        NSColor.black.setFill()
        NSColor.black.setStroke()
        for feature in features {
            if let width = feature.width {
                feature.path.lineWidth = width
                feature.path.lineCapStyle = .round
                feature.path.lineJoinStyle = .round
                feature.path.stroke()
            } else {
                feature.path.fill()
            }
        }
    }

    /// 一段图形。`width` 为 nil 表示整块填充，否则是描边宽度。
    private struct Feature {
        let path: NSBezierPath
        var width: CGFloat?
    }

    private static func filled(_ path: NSBezierPath) -> Feature {
        Feature(path: path, width: nil)
    }

    private static func stroked(_ path: NSBezierPath, width: CGFloat = featureStroke) -> Feature {
        Feature(path: path, width: width)
    }

    // MARK: - 剪影

    /// 这个图案的实心部分。只有圆形脸这一种 ——
    /// 「基米」走的是照片量化那条路（见 `decodedBitmap`），根本不经过这里。
    private static func silhouette(for icon: MenuBarIcon) -> [NSBezierPath] {
        [oval(centerX: faceCenter, centerY: faceCenter, radius: faceRadius)]
    }

    /// 该图案要挖空的五官。
    private static func erase(for icon: MenuBarIcon) -> [Feature] {
        switch icon {
        case .smile:            return [filled(eyeDot(left: true)), filled(eyeDot(left: false)), stroked(smileArc())]

        case .grin:
            return [stroked(closedEyeArc(left: true)),
                    stroked(closedEyeArc(left: false)),
                    filled(openMouth())]

        case .wink:
            return [filled(eyeDot(left: true)),
                    stroked(closedEyeArc(left: false)),
                    stroked(smileArc())]

        case .surprised:
            // 嘴比眼睛大一圈、位置更低，于是读作"张开的 o 形嘴"。
            return [filled(eyeDot(left: true, radius: 1.7)),
                    filled(eyeDot(left: false, radius: 1.7)),
                    filled(oval(centerX: 12, centerY: 16.5, radius: 2.25))]

        case .cool:
            // 镜片留白读作"墨镜"：脸是实心的，镜片是透明的。
            return [filled(goggles()),
                    stroked(smileArc(openAt: 8.7, closeAt: 15.3, baseline: 15.1, dip: 2.9))]

        case .love:
            return [filled(heart(centerX: faceCenter - eyeDX, centerY: eyeY + 0.3,
                                 width: 4.9, height: 4.5)),
                    filled(heart(centerX: faceCenter + eyeDX, centerY: eyeY + 0.3,
                                 width: 4.9, height: 4.5)),
                    stroked(smileArc())]

        case .sad:
            return [filled(eyeDot(left: true)), filled(eyeDot(left: false)), stroked(frownArc())]

        case .angry:
            var out: [Feature] = [filled(eyeDot(left: true, radius: 1.6, y: 10.9)),
                                  filled(eyeDot(left: false, radius: 1.6, y: 10.9))]
            for sign in [CGFloat(-1), 1] {   // 八字眉
                let brow = NSBezierPath()
                brow.move(to: NSPoint(x: faceCenter + sign * 5.3, y: 6.7))
                brow.line(to: NSPoint(x: faceCenter + sign * 1.7, y: 8.6))
                out.append(stroked(brow, width: 2.0))
            }
            out.append(stroked(frownArc(openAt: 8.6, closeAt: 15.4, baseline: 16.6, rise: 3.3)))
            return out

        case .jimiSmile, .jimiFacepalm:
            // 这两个是照片量化出来的位图，根本不走矢量这条路（见 `decodedBitmap`）。
            return []
        }
    }

    // MARK: - 基础图形

    private static func oval(centerX: CGFloat, centerY: CGFloat, radius: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: centerX - radius, y: centerY - radius,
                                    width: radius * 2, height: radius * 2))
    }

    // MARK: - 五官

    /// 一只圆点眼。
    private static func eyeDot(left: Bool, radius: CGFloat = dotEyeRadius, y: CGFloat = eyeY) -> NSBezierPath {
        let cx = faceCenter + (left ? -eyeDX : eyeDX)
        return oval(centerX: cx, centerY: y, radius: radius)
    }

    /// 闭着（笑弯）的眼睛弧线，`^ ^` 那种。
    private static func closedEyeArc(left: Bool) -> NSBezierPath {
        let cx = faceCenter + (left ? -eyeDX : eyeDX)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx - 1.8, y: eyeY + 0.7))
        path.curve(to: NSPoint(x: cx + 1.8, y: eyeY + 0.7),
                   controlPoint1: NSPoint(x: cx - 0.7, y: eyeY - 2.5),
                   controlPoint2: NSPoint(x: cx + 0.7, y: eyeY - 2.5))
        return path
    }

    /// 向上拱起的嘴（微笑）。`dip` 越大笑得越开。
    private static func smileArc(openAt: CGFloat = 7.7, closeAt: CGFloat = 16.3,
                                 baseline: CGFloat = 14.3, dip: CGFloat = 4.1) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: openAt, y: baseline))
        path.curve(to: NSPoint(x: closeAt, y: baseline),
                   controlPoint1: NSPoint(x: openAt + 1.8, y: baseline + dip),
                   controlPoint2: NSPoint(x: closeAt - 1.8, y: baseline + dip))
        return path
    }

    /// 向下弯的嘴（难过 / 生气）。
    private static func frownArc(openAt: CGFloat = 8.3, closeAt: CGFloat = 15.7,
                                 baseline: CGFloat = 16.6, rise: CGFloat = 3.8) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: openAt, y: baseline))
        path.curve(to: NSPoint(x: closeAt, y: baseline),
                   controlPoint1: NSPoint(x: openAt + 1.6, y: baseline - rise),
                   controlPoint2: NSPoint(x: closeAt - 1.6, y: baseline - rise))
        return path
    }

    /// 张开的嘴（大笑）：上缘平直，下缘一个大弧。
    private static func openMouth() -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 8.0, y: 13.1))
        path.line(to: NSPoint(x: 16.0, y: 13.1))
        path.curve(to: NSPoint(x: 8.0, y: 13.1),
                   controlPoint1: NSPoint(x: 16.0, y: 19.7),
                   controlPoint2: NSPoint(x: 8.0, y: 19.7))
        path.close()
        return path
    }

    /// 墨镜：**一整条闭合轮廓**（镜片 + 中间的鼻梁缺口），而不是"两片镜片 + 一根横梁"。
    ///
    /// 分开画会踩坑：横梁两端的圆头会扎进镜片里 —— 早先用 even-odd 填充时，
    /// 交叠处环绕数变偶数于是翻回实心，镜片上留下两个黑色缺口（实测过）。
    private static func goggles() -> NSBezierPath {
        let top: CGFloat = 8.9
        let bottom: CGFloat = 12.4
        let left: CGFloat = 5.2
        let right: CGFloat = 18.8
        let radius = (bottom - top) / 2
        let cy = (top + bottom) / 2
        let leftCX = left + radius
        let rightCX = right - radius

        let path = NSBezierPath()
        path.move(to: NSPoint(x: left, y: cy))
        path.appendArc(withCenter: NSPoint(x: leftCX, y: cy), radius: radius,
                       startAngle: 180, endAngle: 270)
        path.line(to: NSPoint(x: rightCX, y: top))
        path.appendArc(withCenter: NSPoint(x: rightCX, y: cy), radius: radius,
                       startAngle: 270, endAngle: 450)
        path.line(to: NSPoint(x: 13.2, y: bottom))
        path.line(to: NSPoint(x: 12.3, y: 11.0))
        path.line(to: NSPoint(x: 11.7, y: 11.0))
        path.line(to: NSPoint(x: 10.8, y: bottom))
        path.line(to: NSPoint(x: leftCX, y: bottom))
        path.appendArc(withCenter: NSPoint(x: leftCX, y: cy), radius: radius,
                       startAngle: 90, endAngle: 180)
        path.close()
        return path
    }

    /// 爱心（眼睛用）。画在 y 向下的坐标系里。
    private static func heart(centerX cx: CGFloat, centerY cy: CGFloat,
                              width w: CGFloat, height h: CGFloat) -> NSBezierPath {
        let top = cy - h / 2
        let bottom = cy + h / 2
        let half = w / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx, y: bottom))
        path.curve(to: NSPoint(x: cx - half, y: top + h * 0.28),
                   controlPoint1: NSPoint(x: cx - half * 0.62, y: bottom - h * 0.22),
                   controlPoint2: NSPoint(x: cx - half, y: top + h * 0.70))
        path.curve(to: NSPoint(x: cx, y: top + h * 0.30),
                   controlPoint1: NSPoint(x: cx - half, y: top),
                   controlPoint2: NSPoint(x: cx - half * 0.36, y: top))
        path.curve(to: NSPoint(x: cx + half, y: top + h * 0.28),
                   controlPoint1: NSPoint(x: cx + half * 0.36, y: top),
                   controlPoint2: NSPoint(x: cx + half, y: top))
        path.curve(to: NSPoint(x: cx, y: bottom),
                   controlPoint1: NSPoint(x: cx + half, y: top + h * 0.70),
                   controlPoint2: NSPoint(x: cx + half * 0.62, y: bottom - h * 0.22))
        path.close()
        return path
    }
}
