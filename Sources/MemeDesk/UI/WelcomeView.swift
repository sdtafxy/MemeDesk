import SwiftUI

struct WelcomeView: View {
    @ObservedObject private var loc = Localization.shared

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 6)

            VStack(spacing: 10) {
                BrandMark(size: 76)
                    .shadow(color: MD.accent.opacity(0.30), radius: 14, y: 6)
                VStack(spacing: 4) {
                    Text("MemeDesk")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(MD.ink)
                    Text(loc[.tagline])
                        .font(.system(size: 12))
                        .foregroundStyle(MD.inkSub)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            // 四行说明：每行都是固定高度盒子，间距永远一致
            VStack(alignment: .leading, spacing: 2) {
                MDTipRow(icon: "cursorarrow.motionlines", text: loc[.tip1])
                MDTipRow(icon: "contextualmenu.and.cursorarrow", text: loc[.tip2])
                MDTipRow(icon: "moon.zzz", text: loc[.tip3])
                MDTipRow(icon: "menubar.rectangle", text: loc[.tip4])
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: MD.cornerL, style: .continuous)
                    .fill(MD.surface.opacity(0.6))
            )
            .padding(.horizontal, 4)

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                Button(loc[.chooseStickers]) {
                    Task {
                        let urls = await FilePicker.chooseMedia()
                        await Stage.shared.add(urls: urls)
                    }
                }
                .buttonStyle(MDPrimaryButtonStyle())
                Button(loc[.openLibrary]) {
                    Task { @MainActor in LibraryWindow.show() }
                }
                .buttonStyle(MDButtonStyle())
                Button(loc[.openSettings]) {
                    SettingsWindow.show()
                }
                .buttonStyle(MDButtonStyle())
            }
            .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 460, height: 400)
        .background(MD.canvas)
    }
}
