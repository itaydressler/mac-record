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
                    customizeMainWindow()
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

    private func customizeMainWindow() {
        DispatchQueue.main.async {
            guard let window = NSApp.windows.first(where: { $0.isVisible && !($0 is FloatingPanel) }) else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.cornerRadius = 18
                contentView.layer?.masksToBounds = true
            }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.isMovableByWindowBackground = true
            // Hide native traffic light buttons
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
        }
    }
}

// MARK: - App Delegate (for window customization)

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for window in NSApp.windows where !(window is FloatingPanel) {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.hasShadow = true
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.isMovableByWindowBackground = true
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                if let contentView = window.contentView {
                    contentView.wantsLayer = true
                    contentView.layer?.cornerRadius = 18
                    contentView.layer?.masksToBounds = true
                }
            }
        }
    }
}
