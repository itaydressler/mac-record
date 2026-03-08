import Foundation
import AVFoundation
import WhisperKit

enum TranscriptionState: Equatable {
    case idle
    case extractingAudio
    case downloadingModel
    case loadingModel
    case transcribing(progress: Double)
    case done
    case error(String)

    static func == (lhs: TranscriptionState, rhs: TranscriptionState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.extractingAudio, .extractingAudio),
             (.downloadingModel, .downloadingModel),
             (.loadingModel, .loadingModel), (.done, .done):
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
    @Published var modelLoaded = false

    private var whisperKit: WhisperKit?

    static let modelName = "openai_whisper-large-v3_turbo"

    static var modelsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MacRecord/Models")
    }

    func ensureModelLoaded(stateId: String) async throws {
        guard whisperKit == nil else { return }

        let modelsDir = Self.modelsDirectory
        let localModelFolder = modelsDir.appendingPathComponent(Self.modelName)

        if FileManager.default.fileExists(atPath: localModelFolder.path) {
            // Load from local folder
            states[stateId] = .loadingModel
            let config = WhisperKitConfig(
                modelFolder: localModelFolder.path,
                verbose: true,
                prewarm: true,
                load: true
            )
            whisperKit = try await WhisperKit(config)
        } else {
            // Download to our models directory
            states[stateId] = .downloadingModel
            try FileManager.default.createDirectory(at: modelsDir, withIntermediateDirectories: true)
            let config = WhisperKitConfig(
                model: Self.modelName,
                downloadBase: modelsDir,
                verbose: true,
                prewarm: true,
                load: true
            )
            whisperKit = try await WhisperKit(config)
        }

        states[stateId] = .loadingModel
        modelLoaded = true
    }

    func transcribe(recording: Recording) async {
        let id = recording.id
        guard states[id] == nil || states[id] == .idle || states[id] == .done || states[id]?.isError == true else { return }

        do {
            // Step 1: Extract audio
            states[id] = .extractingAudio
            let audioURL = recording.folderURL.appendingPathComponent("audio.m4a")

            if !FileManager.default.fileExists(atPath: audioURL.path) {
                try await extractAudio(from: recording.videoURL, to: audioURL)
            }

            // Step 2: Download & load model
            try await ensureModelLoaded(stateId: id)

            guard let pipe = whisperKit else {
                throw TranscriptionError.modelNotLoaded
            }

            // Step 3: Transcribe
            states[id] = .transcribing(progress: 0)

            let options = DecodingOptions(
                temperature: 0.0,
                temperatureFallbackCount: 3,
                sampleLength: 224,
                wordTimestamps: true
            )

            let results: [TranscriptionResult] = try await pipe.transcribe(
                audioPath: audioURL.path,
                decodeOptions: options
            ) { progress in
                Task { @MainActor in
                    self.states[id] = .transcribing(progress: min(Double(progress.windowId + 1) * 0.1, 0.99))
                }
                return true
            }

            // Step 4: Save as markdown
            let markdown = Self.buildMarkdown(from: results, filename: recording.filename)
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

    // MARK: - Markdown Generation

    static func buildMarkdown(from results: [TranscriptionResult], filename: String) -> String {
        var md = "# Transcription: \(filename)\n\n"
        md += "---\n\n"

        for result in results {
            for segment in result.segments {
                let start = formatTimestamp(segment.start)
                let end = formatTimestamp(segment.end)
                let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    md += "**[\(start) → \(end)]**\n\n"
                    md += "\(text)\n\n"
                }
            }
        }

        return md
    }

    static func formatTimestamp(_ seconds: Float) -> String {
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
        case .modelNotLoaded: return "Whisper model failed to load."
        case .audioExtractionFailed: return "Could not extract audio from video."
        }
    }
}
