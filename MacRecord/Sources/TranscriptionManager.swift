import Foundation
import AVFoundation
import FluidAudio

@MainActor
final class TranscriptionManager: ObservableObject {
    @Published var states: [String: TranscriptionState] = [:]
    @Published var modelsReady = false

    var speakerProfileStore: SpeakerProfileStore?
    var appSettings: AppSettings?

    // Active engine + the option it was built for (nil = not loaded yet)
    private var loadedEngine: (option: TranscriptionEngineOption, engine: ASREngine)?
    private var diarizerManager: OfflineDiarizerManager?

    // MARK: - Engine management

    private func engine(for option: TranscriptionEngineOption) -> ASREngine {
        if let loaded = loadedEngine, loaded.option == option {
            return loaded.engine
        }
        // Build fresh engine for the new option
        let engine: ASREngine
        switch option {
        case .fluidAudio:
            engine = FluidAudioEngine()
        case .appleSpeech:
            if #available(macOS 26, *) {
                engine = AppleSpeechEngine()
            } else {
                engine = FluidAudioEngine() // fallback
            }
        }
        loadedEngine = (option, engine)
        modelsReady = false
        return engine
    }

    // MARK: - Model loading

    func ensureModelsLoaded(stateId: String, option: TranscriptionEngineOption) async throws {
        let eng = engine(for: option)

        // Load ASR engine if needed
        if loadedEngine?.option != option || !modelsReady {
            try await eng.ensureReady { [weak self] state in
                self?.states[stateId] = state
            }
        }

        // Load diarizer (shared across both engines)
        if diarizerManager == nil {
            states[stateId] = .downloadingModels
            let config = OfflineDiarizerConfig()
            let dm = OfflineDiarizerManager(config: config)
            try await dm.prepareModels()
            diarizerManager = dm
        }

        modelsReady = true
    }

    // MARK: - Transcribe

    func transcribe(recording: Recording) async {
        let id = recording.id
        guard states[id] == nil || states[id] == .idle || states[id] == .done || states[id]?.isError == true else { return }

        let option = appSettings?.transcriptionEngine ?? .fluidAudio

        do {
            // Step 1: Extract audio tracks
            states[id] = .extractingAudio
            let systemAudioURL = recording.folderURL.appendingPathComponent("audio-system.m4a")
            let micAudioURL = recording.folderURL.appendingPathComponent("audio-mic.m4a")

            let asset = AVAsset(url: recording.videoURL)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            let hasMicTrack = audioTracks.count >= 2

            for (i, track) in audioTracks.enumerated() {
                let desc = try await track.load(.formatDescriptions)
                let channels = desc.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mChannelsPerFrame } ?? 0
                DebugLog.shared.send("[Transcription] Audio track \(i): trackID=\(track.trackID), channels=\(channels)")
            }
            DebugLog.shared.send("[Transcription] Found \(audioTracks.count) audio track(s), hasMicTrack=\(hasMicTrack), engine=\(option.displayName)")

            if !FileManager.default.fileExists(atPath: systemAudioURL.path) {
                try await extractAudioTrack(from: recording.videoURL, trackIndex: 0, to: systemAudioURL)
            }
            if hasMicTrack && !FileManager.default.fileExists(atPath: micAudioURL.path) {
                try await extractAudioTrack(from: recording.videoURL, trackIndex: 1, to: micAudioURL)
            }

            // Step 2: Load models
            try await ensureModelsLoaded(stateId: id, option: option)

            guard let diarizer = diarizerManager else {
                throw TranscriptionError.modelNotLoaded
            }

            let eng = engine(for: option)

            // Step 3: Transcribe system audio
            states[id] = .transcribing(progress: 0.2)
            let systemAsr = try await eng.transcribe(audioURL: systemAudioURL)
            states[id] = .transcribing(progress: 0.4)

            // Step 4: Diarize system audio (always via FluidAudio)
            states[id] = .diarizing
            let diarizationResult = try await diarizer.process(systemAudioURL)

            // Step 5: Transcribe mic audio
            var micAsr: ASROutput?
            if hasMicTrack {
                states[id] = .transcribing(progress: 0.7)
                let micAttrs = try? FileManager.default.attributesOfItem(atPath: micAudioURL.path)
                let micSize = (micAttrs?[.size] as? Int) ?? 0
                DebugLog.shared.send("[Transcription] Mic audio file size: \(micSize) bytes")

                let result = try await eng.transcribe(audioURL: micAudioURL)
                DebugLog.shared.send("[Transcription] Mic ASR text (\(result.text.count) chars, \(result.wordTimings?.count ?? 0) words): \(result.text.prefix(200))")
                micAsr = result
            }

            // Step 6: Build structured transcript
            states[id] = .transcribing(progress: 0.9)
            let speakerMatches = matchSpeakers(diarization: diarizationResult)

            let transcript = Self.buildTwoTrackTranscript(
                systemAsr: systemAsr,
                micAsr: micAsr,
                diarization: diarizationResult,
                speakerMatches: speakerMatches,
                recordingId: id
            )

            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(transcript)
            try data.write(to: recording.transcriptURL, options: .atomic)

            states[id] = .done
        } catch {
            states[id] = .error(error.localizedDescription)
        }
    }

    // MARK: - Speaker Matching

    private func matchSpeakers(diarization: DiarizationResult) -> [String: SpeakerMatch] {
        var matches: [String: SpeakerMatch] = [:]
        guard let profiles = speakerProfileStore?.profiles, !profiles.isEmpty else { return matches }

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

    // MARK: - Build Structured Transcript

    static func buildTranscript(
        asr: ASROutput,
        diarization: DiarizationResult,
        speakerMatches: [String: SpeakerMatch],
        recordingId: String
    ) -> Transcript {
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
                speakers.append(TranscriptSpeaker(
                    id: speakerId,
                    name: Self.defaultSpeakerName(index: index),
                    color: index % TranscriptSpeaker.colors.count
                ))
            }
        }

        var segments: [TranscriptSegment] = []
        if let wordTimings = asr.wordTimings, !wordTimings.isEmpty {
            segments = alignWordsWithSpeakers(words: wordTimings, speakers: diarization.segments)
        } else {
            for segment in diarization.segments {
                segments.append(TranscriptSegment(
                    speakerId: segment.speakerId,
                    startTime: Double(segment.startTimeSeconds),
                    endTime: Double(segment.endTimeSeconds),
                    text: ""
                ))
            }
            if !segments.isEmpty {
                segments[0] = TranscriptSegment(
                    speakerId: segments[0].speakerId,
                    startTime: segments[0].startTime,
                    endTime: segments[0].endTime,
                    text: asr.text
                )
            }
        }

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

    static func alignWordsWithSpeakers(
        words: [WordTiming],
        speakers: [TimedSpeakerSegment]
    ) -> [TranscriptSegment] {
        var segments: [TranscriptSegment] = []
        var currentSpeaker: String?
        var currentText = ""
        var segmentStart: TimeInterval = 0
        var segmentEnd: TimeInterval = 0

        for word in words {
            let midpoint = (word.startTime + word.endTime) / 2.0
            let speaker = findSpeaker(at: Float(midpoint), in: speakers)

            if speaker != currentSpeaker {
                if let prev = currentSpeaker, !currentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(TranscriptSegment(
                        speakerId: prev,
                        startTime: segmentStart,
                        endTime: segmentEnd,
                        text: currentText.trimmingCharacters(in: .whitespacesAndNewlines),
                        confidence: word.confidence
                    ))
                }
                currentSpeaker = speaker
                currentText = ""
                segmentStart = word.startTime
            }
            currentText += word.word
            segmentEnd = word.endTime
        }

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
        systemAsr: ASROutput,
        micAsr: ASROutput?,
        diarization: DiarizationResult,
        speakerMatches: [String: SpeakerMatch],
        recordingId: String
    ) -> Transcript {
        let remoteTranscript = buildTranscript(
            asr: systemAsr,
            diarization: diarization,
            speakerMatches: speakerMatches,
            recordingId: recordingId
        )

        DebugLog.shared.send("[Transcription] Remote segments: \(remoteTranscript.segments.count), speakers: \(remoteTranscript.speakers.map { $0.name })")

        guard let micAsr = micAsr else {
            DebugLog.shared.send("[Transcription] No mic ASR, returning remote-only transcript")
            return remoteTranscript
        }

        DebugLog.shared.send("[Transcription] Mic ASR text: '\(micAsr.text.prefix(100))', words: \(micAsr.wordTimings?.count ?? 0)")

        var micSegments: [TranscriptSegment] = []
        if let wordTimings = micAsr.wordTimings, !wordTimings.isEmpty {
            var currentText = ""
            var segStart: TimeInterval = 0
            var segEnd: TimeInterval = 0
            var lastEnd: TimeInterval = 0

            for word in wordTimings {
                let gap = word.startTime - lastEnd
                if !currentText.isEmpty && (gap > 1.0 || (word.startTime - segStart) > 10.0) {
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
                    segStart = word.startTime
                }
                if currentText.isEmpty { segStart = word.startTime }
                currentText += word.word
                segEnd = word.endTime
                lastEnd = word.endTime
            }

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
            micSegments.append(TranscriptSegment(
                speakerId: localSpeakerId,
                startTime: 0,
                endTime: 0,
                text: TextNormalizer.shared.normalizeSentence(micAsr.text)
            ))
        }

        DebugLog.shared.send("[Transcription] Built \(micSegments.count) mic segments")

        var allSegments = remoteTranscript.segments + micSegments
        allSegments.sort { $0.startTime < $1.startTime }

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

// MARK: - Supporting types

struct SpeakerMatch {
    let profileId: String
    let name: String
    let photoFileName: String?
}

enum TranscriptionError: LocalizedError {
    case modelNotLoaded
    case audioExtractionFailed
    case audioTrackNotFound(Int)
    case engineNotAvailable

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded: return "AI models failed to load."
        case .audioExtractionFailed: return "Could not extract audio from video."
        case .audioTrackNotFound(let index): return "Audio track \(index) not found in video."
        case .engineNotAvailable: return "Apple SpeechAnalyzer requires the macOS 26 SDK. Enable SPEECH_ANALYZER_AVAILABLE in project.yml."
        }
    }
}
