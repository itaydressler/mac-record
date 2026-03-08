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
        hostingView.frame = NSRect(x: 0, y: 0, width: 280, height: 56)

        // Find the screen being recorded
        let targetScreen = Self.screenForRecording(recordingManager) ?? NSScreen.main ?? NSScreen.screens.first
        let screenFrame = targetScreen?.visibleFrame ?? .zero
        let x = screenFrame.midX - 140
        let y = screenFrame.maxY - 70

        let panel = FloatingPanel(contentRect: NSRect(x: x, y: y, width: 280, height: 56))
        panel.contentView = hostingView

        panel.orderFrontRegardless()
        self.panel = panel
    }

    /// Find the NSScreen matching the recording source
    private static func screenForRecording(_ manager: RecordingManager) -> NSScreen? {
        if manager.recordingMode == .display, let display = manager.selectedDisplay {
            // Match SCDisplay to NSScreen by CGDirectDisplayID
            return NSScreen.screens.first { screen in
                guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                    return false
                }
                return screenNumber == display.displayID
            }
        } else if manager.recordingMode == .window, let window = manager.selectedWindow {
            // Find which screen contains the window's center
            let windowFrame = window.frame
            let center = CGPoint(x: windowFrame.midX, y: windowFrame.midY)
            return NSScreen.screens.first { screen in
                screen.frame.contains(center)
            }
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
        HStack(spacing: 14) {
            // Recording indicator + time
            HStack(spacing: 8) {
                Circle()
                    .fill(.red)
                    .frame(width: 10, height: 10)
                    .shadow(color: .red.opacity(0.6), radius: 4)

                Text(formatTime(recordingManager.elapsedTime))
                    .font(.system(.body, design: .monospaced, weight: .semibold))
                    .foregroundStyle(.primary)
                    .monospacedDigit()
            }

            Spacer()

            // Pause / Resume
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
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)

            // Stop button
            Button {
                Task {
                    await recordingManager.stopRecording()
                    recordingsStore.refresh()
                }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(.red, in: RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}
