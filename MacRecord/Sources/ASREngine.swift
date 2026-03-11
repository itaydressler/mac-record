import Foundation

// MARK: - Transcription state (shared across engines and UI)

enum TranscriptionState: Equatable {
    case idle
    case extractingAudio
    case downloadingModels
    case transcribing(progress: Double)
    case diarizing
    case done
    case error(String)

    static func == (lhs: TranscriptionState, rhs: TranscriptionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.extractingAudio, .extractingAudio),
             (.downloadingModels, .downloadingModels),
             (.diarizing, .diarizing), (.done, .done):
            return true
        case (.transcribing(let a), .transcribing(let b)):
            return a == b
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

// MARK: - Shared ASR types (decoupled from FluidAudio)

struct WordTiming {
    let word: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
}

struct ASROutput {
    let text: String
    let wordTimings: [WordTiming]?
}

// MARK: - Engine protocol

protocol ASREngine: AnyObject {
    /// Ensure underlying models are downloaded and ready.
    /// Calls `onState` with `.downloadingModels` while preparing.
    func ensureReady(onState: @escaping @MainActor (TranscriptionState) -> Void) async throws

    /// Transcribe an audio file at the given URL.
    func transcribe(audioURL: URL) async throws -> ASROutput
}

// MARK: - Engine option

enum TranscriptionEngineOption: String, CaseIterable, Identifiable {
    case fluidAudio = "fluidAudio"
    case appleSpeech = "appleSpeech"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fluidAudio: return "FluidAudio (Parakeet)"
        case .appleSpeech: return "Apple SpeechAnalyzer"
        }
    }

    var description: String {
        switch self {
        case .fluidAudio: return "Open-source Parakeet model. Works on macOS 15+."
        case .appleSpeech: return "Apple's on-device model. Requires macOS 26+."
        }
    }

    var isAvailable: Bool {
        switch self {
        case .fluidAudio: return true
        case .appleSpeech:
            if #available(macOS 26, *) { return true }
            return false
        }
    }
}
