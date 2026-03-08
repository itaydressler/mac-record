import SwiftUI

@main
struct MacRecordApp: App {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var recordingsStore = RecordingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
                .environmentObject(recordingsStore)
                .frame(minWidth: 700, minHeight: 500)
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
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
    }
}
