import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
enum FilePicker {
    /// 用于文件面板的类型白名单。
    private static let types: [UTType] = [
        .gif, .png, .jpeg, .webP, .heic, .bmp, .tiff,
        .mpeg4Movie, .quickTimeMovie, .movie, .video,
    ]

    /// 弹出选择面板；返回用户选中的媒体文件（允许选文件夹，会自动向下挖一层）。
    @discardableResult
    static func chooseMedia() async -> [URL] {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.message = L(.pickerMessage)
        panel.prompt = L(.pickerPrompt)
        panel.allowedContentTypes = types
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }
        guard panel.runModal() == .OK else { return [] }
        var files: [URL] = []
        for url in panel.urls {
            if Self.isDirectory(url) {
                files.append(contentsOf: Self.scan(url))
            } else {
                files.append(url)
            }
        }
        return files
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// 文件夹里最多找两层，避免把整个磁盘扫一遍。
    private static func scan(_ directory: URL, depth: Int = 0) -> [URL] {
        guard depth < 2 else { return [] }
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(at: directory,
                                                             includingPropertiesForKeys: [.isDirectoryKey],
                                                             options: [.skipsHiddenFiles])
        else { return [] }
        var result: [URL] = []
        for entry in entries {
            if isDirectory(entry) {
                result.append(contentsOf: scan(entry, depth: depth + 1))
            } else if MediaProbe.allowedExtensions.contains(entry.pathExtension.lowercased()) {
                result.append(entry)
            }
        }
        return result
    }
}
