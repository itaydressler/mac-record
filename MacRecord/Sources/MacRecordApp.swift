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
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
    }
}
