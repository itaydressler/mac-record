import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SpokeTheme.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SpokeTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Rectangle().fill(SpokeTheme.divider).frame(height: 1)

            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 32))
                    .foregroundStyle(SpokeTheme.textTertiary.opacity(0.4))
                Text("No settings available")
                    .font(.system(size: 14))
                    .foregroundStyle(SpokeTheme.textTertiary)
                Spacer()
            }
        }
        .background(SpokeTheme.contentBg)
        .frame(width: 360, height: 220)
    }
}
