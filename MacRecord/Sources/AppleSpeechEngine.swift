// AppleSpeechEngine.swift
//
// Uses Apple's SpeechAnalyzer framework (macOS 26+).
// Requires the macOS 26 SDK to compile the real implementation.
//
// To enable: uncomment OTHER_SWIFT_FLAGS in project.yml:
//   OTHER_SWIFT_FLAGS: $(inherited) -DSPEECH_ANALYZER_AVAILABLE

#if SPEECH_ANALYZER_AVAILABLE

import Foundation
import AVFoundation
import Speech

/// ASR engine backed by Apple's SpeechAnalyzer + DictationTranscriber.
/// On-device, punctuation-aware long-form transcription (macOS 26+).
/// Diarization is still handled by FluidAudio in TranscriptionManager.
@available(macOS 26, *)
@MainActor
final class AppleSpeechEngine: ASREngine {

    private let locale = Locale(identifier: "en-US")

    // MARK: - Model Readiness

    func ensureReady(onState: @escaping @MainActor (TranscriptionState) -> Void) async throws {
        let transcriber = makeDictationTranscriber()
        let status = await AssetInventory.status(forModules: [transcriber])
        guard status != .installed else { return }

        onState(.downloadingModels)
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
    }

    // MARK: - Transcription

    func transcribe(audioURL: URL) async throws -> ASROutput {
        let transcriber = makeDictationTranscriber()
        let audioFile = try AVAudioFile(forReading: audioURL)
        let analyzer = try await SpeechAnalyzer(
            inputAudioFile: audioFile,
            modules: [transcriber],
            finishAfterFile: true
        )

        var fullText = ""
        var wordTimings: [WordTiming] = []

        // DictationTranscriber.results emits committed (final) chunks only
        // since we did not set progressiveLongDictation reporting option.
        for try await result in transcriber.results {
            let attrStr = result.text
            fullText += String(attrStr.characters)

            // Each AttributedString run may carry an audioTimeRange attribute
            // (CMTimeRange) when attributeOptions: [.audioTimeRange] is set.
            for run in attrStr.runs {
                let word = String(attrStr[run.range].characters)
                guard !word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }

                // Dynamic member lookup: run.audioTimeRange -> CMTimeRange?
                if let cmRange = run.audioTimeRange {
                    wordTimings.append(WordTiming(
                        word: word,
                        startTime: cmRange.start.seconds,
                        endTime: (cmRange.start + cmRange.duration).seconds,
                        confidence: 1.0
                    ))
                }
            }
        }

        return ASROutput(
            text: fullText,
            wordTimings: wordTimings.isEmpty ? nil : wordTimings
        )
    }

    // MARK: - Private

    private func makeDictationTranscriber() -> DictationTranscriber {
        // .timeIndexedLongDictation preset = long-form + audioTimeRange attributes
        DictationTranscriber(locale: locale, preset: .timeIndexedLongDictation)
    }
}

#else // SPEECH_ANALYZER_AVAILABLE

import Foundation

/// Stub: compiles when macOS 26 SDK is not available.
/// Enable SPEECH_ANALYZER_AVAILABLE in project.yml to activate.
@MainActor
final class AppleSpeechEngine: ASREngine {
    func ensureReady(onState: @escaping @MainActor (TranscriptionState) -> Void) async throws {
        throw TranscriptionError.engineNotAvailable
    }

    func transcribe(audioURL: URL) async throws -> ASROutput {
        throw TranscriptionError.engineNotAvailable
    }
}

#endif // SPEECH_ANALYZER_AVAILABLE
