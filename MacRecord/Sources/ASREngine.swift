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

