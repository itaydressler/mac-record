import SwiftUI

final class AppSettings: ObservableObject {
    @AppStorage("transcriptionEngine")
    var transcriptionEngineRaw: String = TranscriptionEngineOption.fluidAudio.rawValue {
        willSet { objectWillChange.send() }
    }

    var transcriptionEngine: TranscriptionEngineOption {
        get { TranscriptionEngineOption(rawValue: transcriptionEngineRaw) ?? .fluidAudio }
        set { transcriptionEngineRaw = newValue.rawValue }
    }
}
