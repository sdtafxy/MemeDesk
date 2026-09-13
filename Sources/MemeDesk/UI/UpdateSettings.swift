import AppKit
import SwiftUI

/// 设置页的「更新」分区。
///
/// 三种用法都在这一块里：**自动检查**（开关）、**自动下载安装**（开关）、
/// **手动检查**（按钮）。安装会原地替换 App 本体，用户数据在 App 之外，不受影响。
struct UpdateSettingsSection: View {
    @ObservedObject private var stage = Stage.shared
    @ObservedObject private var loc = Localization.shared
    @ObservedObject private var update = UpdateService.shared

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        Section(loc[.updateSection]) {
            statusRow
            actions

            Toggle(loc[.updateAutoCheck], isOn: $stage.preferences.autoCheckForUpdates)
            Toggle(loc[.updateAutoInstall], isOn: $stage.preferences.autoInstallUpdates)

            Text(loc[.updateManualHint])
                .font(MD.fontCaption)
                .foregroundStyle(MD.inkSub)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 状态

    private var statusRow: some View {
        HStack(spacing: 9) {
            Image(systemName: statusIcon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(statusTint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(statusText)
                    .font(MD.fontBodyMedium)
                    .foregroundStyle(MD.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lastCheckedText)
                    .font(MD.fontCaption)
                    .foregroundStyle(MD.inkSub)
            }
            Spacer(minLength: 6)
            if case .checking = update.status {
                ProgressView().controlSize(.small)
            }
            if case .installing = update.status {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 1)
    }

    private var statusIcon: String {
        switch update.status {
        case .idle: return "arrow.triangle.2.circlepath"
        case .checking: return "arrow.triangle.2.circlepath"
        case .upToDate: return "checkmark.circle.fill"
        case .available: return "arrow.down.circle.fill"
        case .downloading: return "arrow.down.circle"
        case .ready: return "shippingbox.fill"
        case .installing: return "arrow.triangle.2.circlepath"
        case .blocked: return "exclamationmark.triangle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        }
    }

    private var statusTint: Color {
        switch update.status {
        case .idle, .checking: return MD.inkSub
        case .upToDate: return MD.accent
        case .available, .downloading, .ready, .installing: return MD.accent
        case .blocked: return Color(nsColor: .systemOrange)
        case .failed: return Color(nsColor: .systemRed)
        }
    }

    private var statusText: String {
        switch update.status {
        case .idle:
            return String(format: loc[.updateCurrentVersion], update.currentVersionString)
        case .checking:
            return loc[.updateChecking]
        case .upToDate:
            return loc[.updateUpToDate]
        case .available(let release):
            return String(format: loc[.updateAvailable], release.versionString)
        case .blocked:
            return loc[.updateNotWritable]
        case .downloading(let fraction):
            return String(format: loc[.updateDownloading], Int(fraction * 100))
        case .ready:
            return loc[.updateReady]
        case .installing:
            return loc[.updateInstalling]
        case .failed(let reason):
            return "\(loc[.updateErrorTitle])：\(reason)"
        }
    }

    private var lastCheckedText: String {
        guard let at = update.lastChecked else { return loc[.updateNeverChecked] }
        return String(format: loc[.updateLastChecked], Self.stamp.string(from: at))
    }

    // MARK: 操作

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            Button(loc[.updateCheckNow]) {
                Task { await update.checkForUpdates(userInitiated: true) }
            }
            .buttonStyle(MDButtonStyle(compact: true))
            .disabled(isBusy)

            Spacer(minLength: 0)

            switch update.status {
            case .available(let release):
                Button(loc[.updateSkip]) { update.skip(release) }
                    .buttonStyle(MDButtonStyle(compact: true))
                Button(loc[.updateDownloadNow]) {
                    Task { await update.download(release, thenInstall: false) }
                }
                .buttonStyle(MDPrimaryButtonStyle())

            case .ready(let release):
                Button(loc[.updateRevealDownload]) { update.revealDownload(in: release) }
                    .buttonStyle(MDButtonStyle(compact: true))
                Button(loc[.updateInstallNow]) { update.install(release: release) }
                    .buttonStyle(MDPrimaryButtonStyle())

            case .blocked(let release):
                Button(loc[.updateRevealDownload]) { update.revealDownload(in: release) }
                    .buttonStyle(MDButtonStyle(compact: true))
                Button(loc[.updateOpenRelease]) { update.openReleasePage(release) }
                    .buttonStyle(MDButtonStyle(compact: true))

            case .failed:
                Button(loc[.updateOpenRelease]) { update.openLatestReleasePage() }
                    .buttonStyle(MDButtonStyle(compact: true))

            default:
                EmptyView()
            }
        }

        // 更新说明：只在下到包或发现有新版时展开，平时不占版面
        if let notes = currentNotes, !notes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(loc[.updateNotes])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(MD.inkSub)
                ScrollView {
                    Text(notes)
                        .font(MD.fontCaption)
                        .foregroundStyle(MD.ink)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 110)
            }
            .padding(.top, 2)
        }

        if case .failed = update.status {
            Button(loc[.updateShowLog]) { update.revealInstallLog() }
                .buttonStyle(MDButtonStyle(compact: true))
        }
    }

    private var currentNotes: String? {
        switch update.status {
        case .available(let r), .ready(let r), .blocked(let r): return r.notes
        default: return nil
        }
    }

    private var isBusy: Bool {
        switch update.status {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }
}
