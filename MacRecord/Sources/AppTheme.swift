import SwiftUI

// MARK: - Spoke Color Palette (Superlist-inspired light theme)

enum SpokeTheme {
    // Backgrounds
    static let windowBg = Color(red: 0.976, green: 0.976, blue: 0.980)       // #F9F9FA
    static let sidebarBg = Color(red: 0.965, green: 0.965, blue: 0.973)      // #F7F7F8
    static let contentBg = Color.white
    static let cardBg = Color(red: 0.957, green: 0.953, blue: 0.969)         // #F4F3F7 (light lavender)
    static let inputBg = Color(red: 0.957, green: 0.953, blue: 0.969)        // #F4F3F7
    static let mediaPanelBg = Color(red: 0.137, green: 0.122, blue: 0.200)   // #231F33 (dark for media)

    // Text
    static let textPrimary = Color(red: 0.118, green: 0.110, blue: 0.165)    // #1E1C2A
    static let textSecondary = Color(red: 0.455, green: 0.439, blue: 0.518)  // #747084
    static let textTertiary = Color(red: 0.631, green: 0.620, blue: 0.690)   // #A19EB0

    // Accent (Superlist purple)
    static let accent = Color(red: 0.435, green: 0.325, blue: 0.996)         // #6F53FE
    static let accentLight = Color(red: 0.435, green: 0.325, blue: 0.996).opacity(0.08)
    static let accentMid = Color(red: 0.435, green: 0.325, blue: 0.996).opacity(0.15)

    // Borders & Dividers
    static let divider = Color.black.opacity(0.06)
    static let border = Color.black.opacity(0.08)
    static let cardBorder = Color.black.opacity(0.06)

    // Status
    static let recording = Color(red: 0.937, green: 0.267, blue: 0.267)      // #EF4444
    static let success = Color(red: 0.204, green: 0.733, blue: 0.408)        // #34BB68
    static let warning = Color(red: 0.957, green: 0.718, blue: 0.086)        // #F4B716

    // Sidebar
    static let sidebarSelected = Color(red: 0.435, green: 0.325, blue: 0.996).opacity(0.10)
    static let sidebarSelectedBar = Color(red: 0.435, green: 0.325, blue: 0.996)  // left bar
    static let sidebarHover = Color.black.opacity(0.03)

    // Speaker colors
    static let speakerColors: [Color] = [
        Color(red: 0.435, green: 0.325, blue: 0.996),  // purple
        Color(red: 0.937, green: 0.267, blue: 0.267),  // red
        Color(red: 0.204, green: 0.733, blue: 0.408),  // green
        Color(red: 0.957, green: 0.588, blue: 0.086),  // orange
        Color(red: 0.608, green: 0.325, blue: 0.996),  // violet
        Color(red: 0.086, green: 0.706, blue: 0.706),  // teal
        Color(red: 0.937, green: 0.267, blue: 0.600),  // pink
        Color(red: 0.400, green: 0.733, blue: 0.204),  // lime
    ]
}

// MARK: - Custom Button Styles

struct SpokeAccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(SpokeTheme.accent)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
    }
}

struct SpokeRecordButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(SpokeTheme.recording)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
    }
}

struct SpokeGhostButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SpokeTheme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(SpokeTheme.border, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(configuration.isPressed ? Color.black.opacity(0.03) : Color.clear)
                    )
            )
    }
}

struct SpokePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(SpokeTheme.textSecondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .strokeBorder(SpokeTheme.border, lineWidth: 1)
                    .background(
                        Capsule()
                            .fill(configuration.isPressed ? Color.black.opacity(0.03) : Color.clear)
                    )
            )
    }
}
