import SwiftUI

@main
struct MacRecordApp: App {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var recordingsStore = RecordingsStore()
    @StateObject private var transcriptionManager = TranscriptionManager()
    @StateObject private var speakerProfileStore = SpeakerProfileStore()
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
                .environmentObject(recordingsStore)
                .environmentObject(transcriptionManager)
                .environmentObject(speakerProfileStore)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear {
                    transcriptionManager.speakerProfileStore = speakerProfileStore
                }
                .onReceive(recordingManager.$state) { newState in
                    if newState == .recording {
                        recordingManager.floatingToolbar.show(
                            recordingManager: recordingManager,
                            recordingsStore: recordingsStore
                        )
                    } else if newState == .idle || newState == .stopping {
                        recordingManager.floatingToolbar.dismiss()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1080, height: 700)
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.configureWindows()
        }
        // Also observe new windows
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidBecomeKey(_:)),
            name: NSWindow.didBecomeKeyNotification,
            object: nil
        )
    }

    @objc private func windowDidBecomeKey(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              !(window is FloatingPanel),
              !window.styleMask.contains(.borderless) else { return }
        configureWindow(window)
    }

    private func configureWindows() {
        for window in NSApp.windows where !(window is FloatingPanel) {
            configureWindow(window)
        }
    }

    private func configureWindow(_ window: NSWindow) {
        // Go fully borderless but keep resizable
        window.styleMask = [.borderless, .resizable, .miniaturizable]
        window.isMovableByWindowBackground = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true

        // Hide any native buttons (they shouldn't exist on borderless, but be safe)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        // Round the content view
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 18
            contentView.layer?.masksToBounds = true
        }
    }
}
