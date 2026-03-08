import SwiftUI

@main
struct MacRecordApp: App {
    @StateObject private var recordingManager = RecordingManager()
    @StateObject private var recordingsStore = RecordingsStore()
    @StateObject private var transcriptionManager = TranscriptionManager()
    @StateObject private var speakerProfileStore = SpeakerProfileStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(recordingManager)
                .environmentObject(recordingsStore)
                .environmentObject(transcriptionManager)
                .environmentObject(speakerProfileStore)
                .frame(minWidth: 700, minHeight: 500)
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
        .windowStyle(.titleBar)
        .defaultSize(width: 900, height: 650)
    }
}
