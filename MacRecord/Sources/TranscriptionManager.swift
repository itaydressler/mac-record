import Foundation
import AVFoundation
import FluidAudio

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

@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var states: [String: TranscriptionState] = [:]
    @Published var modelsReady = false

    private var asrManager: AsrManager?
    private var asrModels: AsrModels?
    private var diarizerManager: OfflineDiarizerManager?

    func ensureModelsLoaded(stateId: String) async throws {
        if asrManager != nil && diarizerManager != nil { return }

        states[stateId] = .downloadingModels

        // Load ASR models
        if asrModels == nil {
            asrModels = try await AsrModels.downloadAndLoad(version: .v3)
        }
        if asrManager == nil {
            asrManager = AsrManager(config: .default)
            try await asrManager!.initialize(models: asrModels!)
        }

        // Load diarization models
        if diarizerManager == nil {
            let config = OfflineDiarizerConfig()
            diarizerManager = OfflineDiarizerManager(config: config)
            try await diarizerManager!.prepareModels()
        }

        modelsReady = true
    }

    func transcribe(recording: Recording) async {
        let id = recording.id
        guard states[id] == nil || states[id] == .idle || states[id] == .done || states[id]?.isError == true else { return }

        do {
            // Step 1: Extract audio to WAV (FluidAudio handles conversion internally from URL)
            states[id] = .extractingAudio
            let audioURL = recording.folderURL.appendingPathComponent("audio.m4a")

            if !FileManager.default.fileExists(atPath: audioURL.path) {
                try await extractAudio(from: recording.videoURL, to: audioURL)
            }

            // Step 2: Load models
            try await ensureModelsLoaded(stateId: id)

            guard let asr = asrManager, let diarizer = diarizerManager else {
                throw TranscriptionError.modelNotLoaded
            }

            // Step 3: Transcribe
            states[id] = .transcribing(progress: 0.3)
            let asrResult = try await asr.transcribe(audioURL)
            states[id] = .transcribing(progress: 0.6)

            // Step 4: Diarize
            states[id] = .diarizing
            let diarizationResult = try await diarizer.process(audioURL)

            // Step 5: Merge and save as markdown
            states[id] = .transcribing(progress: 0.9)
            let markdown = Self.buildMarkdown(
                asr: asrResult,
                diarization: diarizationResult,
                filename: recording.filename
            )
            let mdURL = recording.folderURL.appendingPathComponent("transcription.md")
            try markdown.write(toFile: mdURL.path, atomically: true, encoding: .utf8)

            // Clean up temp audio
            try? FileManager.default.removeItem(at: audioURL)

            states[id] = .done
        } catch {
            states[id] = .error(error.localizedDescription)
        }
    }

    // MARK: - Audio Extraction

    private func extractAudio(from videoURL: URL, to outputURL: URL) async throws {
        let asset = AVAsset(url: videoURL)

        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }

        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputFileType = .m4a
        exportSession.outputURL = outputURL

        await exportSession.export()

        guard exportSession.status == .completed else {
            throw exportSession.error ?? TranscriptionError.audioExtractionFailed
        }
    }

    // MARK: - Markdown Generation with Speaker Labels

    static func buildMarkdown(
        asr: ASRResult,
        diarization: DiarizationResult,
        filename: String
    ) -> String {
        var md = "# Transcription: \(filename)\n\n"

        let speakerCount = Set(diarization.segments.map { $0.speakerId }).count
        md += "_\(speakerCount) speaker\(speakerCount == 1 ? "" : "s") detected_\n\n"
        md += "---\n\n"

        // If we have word-level timings, align them with speaker segments
        if let tokenTimings = asr.tokenTimings, !tokenTimings.isEmpty {
            md += Self.buildAlignedTranscript(tokens: tokenTimings, speakers: diarization.segments)
        } else {
            // Fallback: just output the full text with speaker segments
            for segment in diarization.segments {
                let start = formatTimestamp(Double(segment.startTimeSeconds))
                let end = formatTimestamp(Double(segment.endTimeSeconds))
                let speaker = Self.speakerName(segment.speakerId)
                md += "**[\(start) → \(end)] \(speaker)**\n\n"
            }
            md += "\n" + asr.text + "\n"
        }

        return md
    }

    /// Align word-level ASR tokens with speaker diarization segments
    static func buildAlignedTranscript(
        tokens: [TokenTiming],
        speakers: [TimedSpeakerSegment]
    ) -> String {
        var md = ""
        var currentSpeaker: String?
        var currentText = ""
        var segmentStart: Double?

        for token in tokens {
            let midpoint = (token.startTime + token.endTime) / 2.0
            let speaker = Self.findSpeaker(at: Float(midpoint), in: speakers)

            if speaker != currentSpeaker {
                // Flush previous speaker's text
                if let prev = currentSpeaker, !currentText.isEmpty {
                    let start = formatTimestamp(segmentStart ?? 0)
                    let name = speakerName(prev)
                    md += "**[\(start)] \(name):**\n\(currentText.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
                }
                currentSpeaker = speaker
                currentText = ""
                segmentStart = token.startTime
            }
            currentText += token.token
        }

        // Flush last segment
        if let prev = currentSpeaker, !currentText.isEmpty {
            let start = formatTimestamp(segmentStart ?? 0)
            let name = speakerName(prev)
            md += "**[\(start)] \(name):**\n\(currentText.trimmingCharacters(in: .whitespacesAndNewlines))\n\n"
        }

        return md
    }

    static func findSpeaker(at time: Float, in segments: [TimedSpeakerSegment]) -> String? {
        for segment in segments {
            if time >= segment.startTimeSeconds && time <= segment.endTimeSeconds {
                return segment.speakerId
            }
        }
        return nil
    }

    static func speakerName(_ id: String) -> String {
        // Convert IDs like "speaker_0" to friendly names
        if let num = id.split(separator: "_").last.flatMap({ Int($0) }) {
            let names = ["Speaker A", "Speaker B", "Speaker C", "Speaker D",
                         "Speaker E", "Speaker F", "Speaker G", "Speaker H"]
            return num < names.count ? names[num] : "Speaker \(num + 1)"
        }
        return id
    }

    static func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case audioExtractionFailed

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "AI models failed to load."
        case .audioExtractionFailed: return "Could not extract audio from video."
        }
    }
}
