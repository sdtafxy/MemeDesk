import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject private var stage = Stage.shared
    @ObservedObject private var loc = Localization.shared
    /// 只用来让「状态」一行重新求值：切语言或点刷新都会让它自增。
    @State private var statusTick = 0

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.1"
    }

    private var loginStatus: String {
        _ = statusTick
        return LoginItem.statusDescription()
    }

    var body: some View {
        Form {
            Section(loc[.language]) {
                Picker(loc[.language], selection: languageBinding) {
                    ForEach(AppLanguage.allCases) { option in
                        Text(option.name).tag(option)
                    }
                }
                .labelsHidden()
            }

            Section(loc[.placement]) {
                HStack {
                    Text(loc[.defaultSize])
                    Slider(value: $stage.preferences.defaultSize, in: 80...600)
                    Text("\(Int(stage.preferences.defaultSize)) pt").monospacedDigit().frame(width: 60)
                }
                Toggle(loc[.snapToEdges], isOn: $stage.preferences.snapToEdges)
                Toggle(loc[.muteByDefault], isOn: $stage.preferences.videosMutedByDefault)
                Toggle(loc[.restoreSession], isOn: $stage.preferences.restoreSession)
            }

            Section(loc[.performance]) {
                HStack {
                    Text(loc[.decodePixelLimit])
                    Slider(value: Binding(get: { Double(stage.preferences.decodePixelLimit) },
                                          set: { stage.preferences.decodePixelLimit = Int($0) }),
                           in: 96...1024)
                    Text("\(stage.preferences.decodePixelLimit) px").monospacedDigit().frame(width: 70)
                }
                Text(loc[.decodeHint])
                    .font(MD.fontCaption)
                    .foregroundStyle(MD.inkSub)
                Toggle(loc[.pauseWhenOccluded], isOn: $stage.preferences.pauseWhenOccluded)
                Toggle(loc[.hideOnFullscreen], isOn: $stage.preferences.hideOnFullscreen)
                Toggle(loc[.pauseOnBattery], isOn: $stage.preferences.pauseOnBattery)
                HStack {
                    Text(loc[.motionSpeed])
                    Slider(value: $stage.preferences.motionSpeed, in: 0...2)
                    Text(String(format: "%.1f×", stage.preferences.motionSpeed))
                        .monospacedDigit()
                        .frame(width: 44)
                }
            }

            Section(loc[.startup]) {
                Toggle(loc[.launchAtLogin], isOn: Binding(
                    get: { LoginItem.isEnabled },
                    set: { enabled in
                        LoginItem.setEnabled(enabled)
                        stage.preferences.launchAtLogin = enabled
                    }))
                HStack {
                    Text(String(format: loc[.statusLabel], loginStatus))
                        .font(MD.fontCaption)
                        .foregroundStyle(MD.inkSub)
                    Spacer()
                    Button(loc[.refresh]) { statusTick += 1 }
                        .buttonStyle(MDButtonStyle(compact: true))
                }
            }

            Section(loc[.about]) {
                HStack(spacing: 12) {
                    BrandMark(size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("MemeDesk")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MD.ink)
                        Text(String(format: loc[.aboutVersion], version))
                            .font(MD.fontCaption)
                            .foregroundStyle(MD.inkSub)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
                Text(loc[.aboutNote])
                    .font(MD.fontCaption)
                    .foregroundStyle(MD.inkSub)
                Text(loc[.aboutCLI])
                    .font(MD.fontCaption)
                    .foregroundStyle(MD.inkSub)
                    .textSelection(.enabled)
                HStack {
                    Text(String(format: loc[.instanceCount], stage.count))
                        .font(MD.fontCaption)
                        .foregroundStyle(MD.inkSub)
                    Spacer()
                    Button(loc[.clearDesk], role: .destructive) { stage.removeAll() }
                        .buttonStyle(MDButtonStyle(compact: true))
                    Button(loc[.openSamples]) { Task { @MainActor in LibraryWindow.show() } }
                        .buttonStyle(MDButtonStyle(compact: true))
                }
            }
        }
        .formStyle(.grouped)
        .tint(MD.accent)
        .scrollContentBackground(.hidden)
        .background(MD.canvas)
        .frame(minWidth: 480, minHeight: 560)
        .navigationTitle(loc[.settingsTitle])
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { loc.language }, set: { loc.setLanguage($0) })
    }
}
