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
    var speakerProfileStore: SpeakerProfileStore?

    func ensureModelsLoaded(stateId: String) async throws {
        if asrManager != nil && diarizerManager != nil { return }

        states[stateId] = .downloadingModels

        if asrModels == nil {
            asrModels = try await AsrModels.downloadAndLoad(version: .v3)
        }
        if asrManager == nil {
            asrManager = AsrManager(config: .default)
            try await asrManager!.initialize(models: asrModels!)
        }

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
            // Step 1: Extract audio
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

            // Step 5: Build structured transcript
            states[id] = .transcribing(progress: 0.9)

            // Match speakers against known profiles
            let speakerMatches = matchSpeakers(diarization: diarizationResult)

            let transcript = Self.buildTranscript(
                asr: asrResult,
                diarization: diarizationResult,
                speakerMatches: speakerMatches,
                recordingId: id
            )

            // Save as JSON
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(transcript)
            try data.write(to: recording.transcriptURL, options: .atomic)

            // Clean up temp audio
            try? FileManager.default.removeItem(at: audioURL)

            states[id] = .done
        } catch {
            states[id] = .error(error.localizedDescription)
        }
    }

    // MARK: - Speaker Matching

    private func matchSpeakers(diarization: DiarizationResult) -> [String: SpeakerMatch] {
        var matches: [String: SpeakerMatch] = [:]
        guard let profiles = speakerProfileStore?.profiles, !profiles.isEmpty else {
            return matches
        }

        // Get unique speaker IDs and their embeddings from diarization
        let speakerEmbeddings = diarization.speakerDatabase ?? [:]

        for (speakerId, embedding) in speakerEmbeddings {
            var bestMatch: SpeakerProfile?
            var bestDistance: Float = Float.greatestFiniteMagnitude

            for profile in profiles {
                guard !profile.embedding.isEmpty else { continue }
                let distance = cosineDistance(embedding, profile.embedding)
                if distance < bestDistance {
                    bestDistance = distance
                    bestMatch = profile
                }
            }

            // Threshold for matching (lower = stricter)
            if bestDistance < 0.5, let match = bestMatch {
                matches[speakerId] = SpeakerMatch(
                    profileId: match.id.uuidString,
                    name: match.name,
                    photoFileName: match.photoFileName
                )
            }
        }

        return matches
    }

    private func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 1.0 }
        var dot: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 0 else { return 1.0 }
        return 1.0 - (dot / denom)
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

    // MARK: - Build Structured Transcript

    static func buildTranscript(
        asr: ASRResult,
        diarization: DiarizationResult,
        speakerMatches: [String: SpeakerMatch],
        recordingId: String
    ) -> Transcript {
        // Build speaker list
        let uniqueSpeakerIds = Array(Set(diarization.segments.map { $0.speakerId })).sorted()
        var speakers: [TranscriptSpeaker] = []
        for (index, speakerId) in uniqueSpeakerIds.enumerated() {
            if let match = speakerMatches[speakerId] {
                speakers.append(TranscriptSpeaker(
                    id: speakerId,
                    name: match.name,
                    profileId: match.profileId,
                    color: index % TranscriptSpeaker.colors.count
                ))
            } else {
                let name = Self.defaultSpeakerName(index: index)
                speakers.append(TranscriptSpeaker(
                    id: speakerId,
                    name: name,
                    color: index % TranscriptSpeaker.colors.count
                ))
            }
        }

        // Build segments by aligning tokens with speaker segments
        var segments: [TranscriptSegment] = []

        if let tokenTimings = asr.tokenTimings, !tokenTimings.isEmpty {
            segments = alignTokensWithSpeakers(
                tokens: tokenTimings,
                speakers: diarization.segments
            )
        } else {
            // Fallback: one segment per diarization segment with full text
            for segment in diarization.segments {
                segments.append(TranscriptSegment(
                    speakerId: segment.speakerId,
                    startTime: Double(segment.startTimeSeconds),
                    endTime: Double(segment.endTimeSeconds),
                    text: ""
                ))
            }
            // Put full text in first segment if no alignment possible
            if !segments.isEmpty {
                segments[0] = TranscriptSegment(
                    speakerId: segments[0].speakerId,
                    startTime: segments[0].startTime,
                    endTime: segments[0].endTime,
                    text: asr.text
                )
            }
        }

        // Apply ITN (Inverse Text Normalization) to each segment
        for i in 0..<segments.count {
            let normalized = TextNormalizer.shared.normalizeSentence(segments[i].text)
            segments[i] = TranscriptSegment(
                speakerId: segments[i].speakerId,
                startTime: segments[i].startTime,
                endTime: segments[i].endTime,
                text: normalized,
                confidence: segments[i].confidence
            )
        }

        return Transcript(
            version: Transcript.currentVersion,
            recordingId: recordingId,
            createdAt: Date(),
            speakers: speakers,
            segments: segments
        )
    }

    static func alignTokensWithSpeakers(
        tokens: [TokenTiming],
        speakers: [TimedSpeakerSegment]
    ) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var currentSpeaker: String?
        var currentText = ""
        var segmentStart: TimeInterval = 0
        var segmentEnd: TimeInterval = 0

        for token in tokens {
            let midpoint = (token.startTime + token.endTime) / 2.0
            let speaker = findSpeaker(at: Float(midpoint), in: speakers)

            if speaker != currentSpeaker {
                // Flush previous segment
                if let prev = currentSpeaker, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(TranscriptSegment(
                        speakerId: prev,
                        startTime: segmentStart,
                        endTime: segmentEnd,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                        confidence: token.confidence
                    ))
                }
                currentSpeaker = speaker
                currentText = ""
                segmentStart = token.startTime
            }
            currentText += token.token
            segmentEnd = token.endTime
        }

        // Flush last segment
        if let prev = currentSpeaker, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            segments.append(TranscriptSegment(
                speakerId: prev,
                startTime: segmentStart,
                endTime: segmentEnd,
                text: currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
        }

        return segments
    }

    static func findSpeaker(at time: Float, in segments: [TimedSpeakerSegment]) -> String? {
        for segment in segments {
            if time >= segment.startTimeSeconds && time <= segment.endTimeSeconds {
                return segment.speakerId
            }
        }
        return nil
    }

    static func defaultSpeakerName(index: Int) -> String {
        let names = ["Speaker A", "Speaker B", "Speaker C", "Speaker D",
                     "Speaker E", "Speaker F", "Speaker G", "Speaker H"]
        return index < names.count ? names[index] : "Speaker \(index + 1)"
    }
}

struct SpeakerMatch {
    let profileId: String
    let name: String
    let photoFileName: String?
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
