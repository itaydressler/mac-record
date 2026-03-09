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
            // Step 1: Extract audio tracks
            states[id] = .extractingAudio
            let systemAudioURL = recording.folderURL.appendingPathComponent("audio-system.m4a")
            let micAudioURL = recording.folderURL.appendingPathComponent("audio-mic.m4a")

            // Check how many audio tracks exist
            let asset = AVAsset(url: recording.videoURL)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let hasMicTrack = audioTracks.count >= 2

            for (i, track) in audioTracks.enumerated() {
                let desc = try await track.load(.formatDescriptions)
                let channels = desc.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 0
                DebugLog.shared.send("[Transcription] Audio track \(i): trackID=\(track.trackID), channels=\(channels)")
            }
            DebugLog.shared.send("[Transcription] Found \(audioTracks.count) audio track(s), hasMicTrack=\(hasMicTrack)")

            // Extract system audio (track 0)
            if !FileManager.default.fileExists(atPath: systemAudioURL.path) {
                try await extractAudioTrack(from: recording.videoURL, trackIndex: 0, to: systemAudioURL)
            }

            // Extract mic audio (track 1) if available
            if hasMicTrack && !FileManager.default.fileExists(atPath: micAudioURL.path) {
                try await extractAudioTrack(from: recording.videoURL, trackIndex: 1, to: micAudioURL)
            }

            // Step 2: Load models
            try await ensureModelsLoaded(stateId: id)

            guard let asr = asrManager, let diarizer = diarizerManager else {
                throw TranscriptionError.modelNotLoaded
            }

            // Step 3: Transcribe system audio (remote speakers)
            states[id] = .transcribing(progress: 0.2)
            let systemAsrResult = try await asr.transcribe(systemAudioURL)
            states[id] = .transcribing(progress: 0.4)

            // Step 4: Diarize system audio
            states[id] = .diarizing
            let diarizationResult = try await diarizer.process(systemAudioURL)

            // Step 5: Transcribe mic audio (local speaker) if available
            var micAsrResult: ASRResult?
            if hasMicTrack {
                states[id] = .transcribing(progress: 0.7)
                // Verify mic file was extracted and has content
                let micAttrs = try? FileManager.default.attributesOfItem(atPath: micAudioURL.path)
                let micSize = (micAttrs?[.size] as? Int) ?? 0
                DebugLog.shared.send("[Transcription] Mic audio file size: \(micSize) bytes")

                micAsrResult = try await asr.transcribe(micAudioURL)
                let micText = micAsrResult?.text ?? ""
                let micTokenCount = micAsrResult?.tokenTimings?.count ?? 0
                DebugLog.shared.send("[Transcription] Mic ASR text (\(micText.count) chars, \(micTokenCount) tokens): \(micText.prefix(200))")
            }

            // Step 6: Build structured transcript
            states[id] = .transcribing(progress: 0.9)

            // Match remote speakers against known profiles
            let speakerMatches = matchSpeakers(diarization: diarizationResult)

            let transcript = Self.buildTwoTrackTranscript(
                systemAsr: systemAsrResult,
                micAsr: micAsrResult,
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

            // Keep temp audio files for debugging (audio-system.m4a, audio-mic.m4a)

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

    /// Extract a specific audio track by index from the video file.
    /// trackIndex 0 = system audio, trackIndex 1 = mic audio.
    private func extractAudioTrack(from videoURL: URL, trackIndex: Int, to outputURL: URL) async throws {
        let asset = AVAsset(url: videoURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard trackIndex < audioTracks.count else {
            throw TranscriptionError.audioTrackNotFound(trackIndex)
        }

        let sourceTrack = audioTracks[trackIndex]
        let composition = AVMutableComposition()

        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }

        let duration = try await asset.load(.duration)
        try compositionTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: sourceTrack,
            at: .zero
        )

        guard let exportSession = AVAssetExportSession(
            asset: composition,
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

    /// Legacy: extract first audio track (system audio)
    private func extractAudio(from videoURL: URL, to outputURL: URL) async throws {
        try await extractAudioTrack(from: videoURL, trackIndex: 0, to: outputURL)
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

    // MARK: - Two-Track Transcript Building

    private static let localSpeakerId = "__local_mic__"

    static func buildTwoTrackTranscript(
        systemAsr: ASRResult,
        micAsr: ASRResult?,
        diarization: DiarizationResult,
        speakerMatches: [String: SpeakerMatch],
        recordingId: String
    ) -> Transcript {
        // Build remote speaker segments from system audio + diarization
        let remoteTranscript = buildTranscript(
            asr: systemAsr,
            diarization: diarization,
            speakerMatches: speakerMatches,
            recordingId: recordingId
        )

        DebugLog.shared.send("[Transcription] Remote segments: \(remoteTranscript.segments.count), speakers: \(remoteTranscript.speakers.map { $0.name })")

        // If no mic track, just return remote-only transcript
        guard let micAsr = micAsr else {
            DebugLog.shared.send("[Transcription] No mic ASR, returning remote-only transcript")
            return remoteTranscript
        }

        DebugLog.shared.send("[Transcription] Mic ASR text: '\(micAsr.text.prefix(100))', tokens: \(micAsr.tokenTimings?.count ?? 0)")

        // Build local (mic) segments — all attributed to local speaker
        var micSegments: [TranscriptSegment] = []
        if let tokenTimings = micAsr.tokenTimings, !tokenTimings.isEmpty {
            // Group tokens into sentence-like segments (flush every ~10s or on long pause)
            var currentText = ""
            var segStart: TimeInterval = 0
            var segEnd: TimeInterval = 0
            var lastEnd: TimeInterval = 0

            for token in tokenTimings {
                let gap = token.startTime - lastEnd
                // Start new segment on large gap (>1s) or if segment is long (>10s)
                if !currentText.isEmpty && (gap > 1.0 || (token.startTime - segStart) > 10.0) {
                    let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty {
                        micSegments.append(TranscriptSegment(
                            speakerId: localSpeakerId,
                            startTime: segStart,
                            endTime: segEnd,
                            text: TextNormalizer.shared.normalizeSentence(trimmed)
                        ))
                    }
                    currentText = ""
                    segStart = token.startTime
                }
                if currentText.isEmpty {
                    segStart = token.startTime
                }
                currentText += token.token
                segEnd = token.endTime
                lastEnd = token.endTime
            }
            // Flush last
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                micSegments.append(TranscriptSegment(
                    speakerId: localSpeakerId,
                    startTime: segStart,
                    endTime: segEnd,
                    text: TextNormalizer.shared.normalizeSentence(trimmed)
                ))
            }
        } else if !micAsr.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // No token timings — single segment for all mic text
            micSegments.append(TranscriptSegment(
                speakerId: localSpeakerId,
                startTime: 0,
                endTime: 0,
                text: TextNormalizer.shared.normalizeSentence(micAsr.text)
            ))
        }

        DebugLog.shared.send("[Transcription] Built \(micSegments.count) mic segments")
        for (i, seg) in micSegments.enumerated() {
            DebugLog.shared.send("[Transcription]   mic[\(i)]: \(String(format: "%.1f", seg.startTime))-\(String(format: "%.1f", seg.endTime))s '\(seg.text.prefix(60))'")
        }

        // Merge and sort all segments chronologically
        var allSegments = remoteTranscript.segments + micSegments
        allSegments.sort { $0.startTime < $1.startTime }

        // Build speaker list: keep remote speakers + add "Me"
        var speakers = remoteTranscript.speakers
        if !micSegments.isEmpty {
            speakers.append(TranscriptSpeaker(
                id: localSpeakerId,
                name: "Me",
                color: speakers.count % TranscriptSpeaker.colors.count
            ))
        }

        return Transcript(
            version: Transcript.currentVersion,
            recordingId: recordingId,
            createdAt: Date(),
            speakers: speakers,
            segments: allSegments
        )
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
    case audioTrackNotFound(Int)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "AI models failed to load."
        case .audioExtractionFailed: return "Could not extract audio from video."
        case .audioTrackNotFound(let index): return "Audio track \(index) not found in video."
        }
    }
}
