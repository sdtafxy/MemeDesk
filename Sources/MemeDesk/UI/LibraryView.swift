import AppKit
import SwiftUI

/// 素材库：内置示例 + 桌面现有 + 拖进来的一切。
struct LibraryView: View {
    @ObservedObject private var stage = Stage.shared
    @ObservedObject private var loc = Localization.shared
    @State private var samples: [MediaItem] = []
    @State private var isDropTarget = false

    private let columns = [GridItem(.adaptive(minimum: 86, maximum: 120), spacing: 12)]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandMark(size: 26)
                Text(loc[.library])
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MD.ink)
                Spacer()
                Button(loc[.addFiles]) { Task { await addFiles() } }
                    .buttonStyle(MDButtonStyle())
                Button(loc[.addAll]) { Task { await addFiles(samples.map { $0.url }) } }
                    .buttonStyle(MDPrimaryButtonStyle())
                    .disabled(samples.isEmpty)
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Rectangle().fill(MD.hairline).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if !samples.isEmpty {
                        section(loc[.bundledSamples]) {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(samples) { item in
                                    MediaCard(item: item) { Task { await stage.add(urls: [item.url]) } }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(String(format: loc[.onDeskCount], stage.summaries.count))
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(MD.ink)
                            Spacer()
                            if !stage.summaries.isEmpty {
                                Button(loc[.hideAll]) { stage.hideAllTemporary() }
                                    .buttonStyle(MDButtonStyle(compact: true))
                            }
                        }
                        if stage.summaries.isEmpty {
                            dropHint
                        } else {
                            LazyVGrid(columns: columns, spacing: 12) {
                                ForEach(stage.summaries) { summary in
                                    ActiveCard(summary: summary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
        }
        .background(MD.canvas)
        .tint(MD.accent)
        .onAppear { samples = Self.bundledSamples() }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers, _ in
            Self.acceptDrop(providers)
            return true
        }
        .overlay(alignment: .center) {
            if isDropTarget {
                RoundedRectangle(cornerRadius: MD.cornerL)
                    .strokeBorder(MD.accent, lineWidth: 2)
                    .background(MD.accent.opacity(0.08))
                    .overlay(Text(loc[.dropToAdd]).font(.system(size: 14, weight: .semibold)))
                    .padding(20)
            }
        }
    }

    private var dropHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.doc")
                .font(.system(size: 26))
                .foregroundStyle(MD.accent)
            Text(loc[.dropHintTitle])
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(MD.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(loc[.dropHintBody])
                .font(MD.fontCaption)
                .foregroundStyle(MD.inkSub)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 12)
        }
        .frame(maxWidth: .infinity, minHeight: 150)
        .background(
            RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous)
                .fill(MD.surface.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous)
                .strokeBorder(MD.hairline, style: StrokeStyle(dash: [6, 4]))
        )
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MDSectionHeader(title: title)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func addFiles(_ urls: [URL]? = nil) async {
        let target: [URL]
        if let urls {
            target = urls
        } else {
            target = await FilePicker.chooseMedia()
        }
        guard !target.isEmpty else { return }
        await stage.add(urls: target)
    }

    private static func acceptDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { object, _ in
                guard let url = object else { return }
                Task { @MainActor in await Stage.shared.add(urls: [url]) }
            }
        }
    }

    private static func bundledSamples() -> [MediaItem] {
        Bundle.main.urls(forResourcesWithExtension: nil, subdirectory: "Samples")?
            .filter { MediaProbe.allowedExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { MediaItem(url: $0) } ?? []
    }
}

// MARK: - 卡片

private struct MediaCard: View {
    let item: MediaItem
    let action: () -> Void
    @State private var thumb: NSImage?
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                thumbnail.frame(width: 72, height: 64)
                Text(item.name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MD.ink)
                    .lineLimit(1)
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous)
                    .fill(hovering ? MD.surfaceActive : MD.surface)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .task { thumb = await ThumbnailCache.shared.image(for: item.url, kind: item.kind) }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumb {
            Image(nsImage: thumb).resizable().scaledToFit()
        } else {
            ProgressView().controlSize(.small)
        }
    }
}

private struct ActiveCard: View {
    let summary: StickerSummary
    @ObservedObject private var stage = Stage.shared
    @State private var thumb: NSImage?
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Group {
                if let thumb {
                    Image(nsImage: thumb).resizable().scaledToFit()
                } else {
                    MD.surfaceActive
                }
            }
            .frame(width: 72, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            Text(summary.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MD.ink)
                .lineLimit(1)
            HStack(spacing: 6) {
                Button {
                    stage.setHidden(summary.id, !summary.isHidden)
                } label: {
                    Image(systemName: summary.isHidden ? "eye.slash" : "eye")
                }
                Button(role: .destructive) {
                    stage.remove(summary.id)
                } label: {
                    Image(systemName: "trash")
                }
            }
            .controlSize(.small)
        }
        .padding(6)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: MD.cornerM, style: .continuous)
                .fill(hovering ? MD.surfaceActive : MD.surface)
        )
        .opacity(summary.isHidden ? 0.5 : 1)
        .onHover { hovering = $0 }
        .task {
            guard let bookmark = stage.config(for: summary.id)?.bookmark,
                  let url = Bookmark.url(from: bookmark) else { return }
            thumb = await ThumbnailCache.shared.image(for: url, kind: MediaProbe.kind(of: url))
        }
    }
}
