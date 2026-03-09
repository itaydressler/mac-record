import SwiftUI
import AppKit
import ScreenCaptureKit

// MARK: - Floating Panel (NSPanel subclass)

final class FloatingPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .statusBar
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        hidesOnDeactivate = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isReleasedWhenClosed = false
    }
}

// MARK: - Floating Toolbar Controller

@MainActor
final class FloatingToolbarController: ObservableObject {
    private var panel: FloatingPanel?

    func show(recordingManager: RecordingManager, recordingsStore: RecordingsStore) {
        guard panel == nil else { return }

        let toolbarView = FloatingToolbarView()
            .environmentObject(recordingManager)
            .environmentObject(recordingsStore)

        let hostingView = NSHostingView(rootView: toolbarView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 260, height: 48)

        let targetScreen = Self.screenForRecording(recordingManager) ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = targetScreen?.visibleFrame ?? .zero
        let x = screenFrame.midX - 130
        let y = screenFrame.maxY - 64

        let panel = FloatingPanel(contentRect: NSRect(x: x, y: y, width: 260, height: 48))
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        self.panel = panel
    }

    private static func screenForRecording(_ manager: RecordingManager) -> NSScreen? {
        if manager.recordingMode == .display, let display = manager.selectedDisplay {
            return NSScreen.screens.first { screen in
                guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return false }
                return screenNumber == display.displayID
            }
        } else if manager.recordingMode == .window, let window = manager.selectedWindow {
            let windowFrame = window.frame
            let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
            return NSScreen.screens.first { screen in screen.frame.contains(center) }
        }
        return nil
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

// MARK: - Floating Toolbar View

struct FloatingToolbarView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var recordingsStore: RecordingsStore

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0.937, green: 0.267, blue: 0.267))
                .frame(width: 8, height: 8)
                .shadow(color: Color(red: 0.937, green: 0.267, blue: 0.267).opacity(0.5), radius: 3)

            Text(formatTime(recordingManager.elapsedTime))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.primary)
                .monospacedDigit()

            Spacer()

            Button {
                Task {
                    if recordingManager.isPaused {
                        await recordingManager.resumeRecording()
                    } else {
                        await recordingManager.pauseRecording()
                    }
                }
            } label: {
                Image(systemName: recordingManager.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                Task {
                    await recordingManager.stopRecording()
                    recordingsStore.refresh()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(Color(red: 0.937, green: 0.267, blue: 0.267))
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, y: 3)
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
