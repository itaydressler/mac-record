import Foundation
import FluidAudio

/// ASR engine backed by FluidAudio's on-device Parakeet model.
/// Works on macOS 15+.
@MainActor
final class FluidAudioEngine: ASREngine {
    private var asrManager: AsrManager?
    private var asrModels: AsrModels?

    func ensureReady(onState: @escaping @MainActor (TranscriptionState) -> Void) async throws {
        guard asrManager == nil else { return }

        onState(.downloadingModels)

        if asrModels == nil {
            asrModels = try await AsrModels.downloadAndLoad(version: .v3)
        }
        let manager = AsrManager(config: .default)
        try await manager.initialize(models: asrModels!)
        asrManager = manager
    }

    func transcribe(audioURL: URL) async throws -> ASROutput {
        guard let asr = asrManager else {
            throw TranscriptionError.modelNotLoaded
        }
        let result = try await asr.transcribe(audioURL)
        let wordTimings = result.tokenTimings?.map { t in
            WordTiming(
                word: t.token,
                startTime: t.startTime,
                endTime: t.endTime,
                confidence: t.confidence ?? 1.0
            )
        }
        return ASROutput(text: result.text, wordTimings: wordTimings)
    }
}
