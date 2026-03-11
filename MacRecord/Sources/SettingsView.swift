import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appSettings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
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

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    transcriptionSection
                }
                .padding(24)
            }
        }
        .background(SpokeTheme.contentBg)
        .frame(width: 480, height: 320)
    }

    // MARK: - Transcription Engine Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Transcription Engine")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(SpokeTheme.textPrimary)

            VStack(spacing: 8) {
                ForEach(TranscriptionEngineOption.allCases) { option in
                    engineRow(option)
                }
            }
        }
    }

    private func engineRow(_ option: TranscriptionEngineOption) -> some View {
        let isSelected = appSettings.transcriptionEngine == option
        let isAvailable = option.isAvailable

        return Button {
            if isAvailable {
                appSettings.transcriptionEngine = option
            }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? SpokeTheme.accent : SpokeTheme.border, lineWidth: isSelected ? 2 : 1.5)
                        .frame(width: 18, height: 18)
                    if isSelected {
                        Circle()
                            .fill(SpokeTheme.accent)
                            .frame(width: 10, height: 10)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(option.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(isAvailable ? SpokeTheme.textPrimary : SpokeTheme.textTertiary)

                        if !isAvailable {
                            Text("macOS 26+")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(SpokeTheme.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(SpokeTheme.cardBg))
                        }
                    }

                    Text(option.description)
                        .font(.system(size: 12))
                        .foregroundStyle(SpokeTheme.textTertiary)
                }

                Spacer()
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? SpokeTheme.accentLight : SpokeTheme.cardBg)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(isSelected ? SpokeTheme.accent.opacity(0.3) : SpokeTheme.cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!isAvailable)
        .opacity(isAvailable ? 1 : 0.6)
    }
}
