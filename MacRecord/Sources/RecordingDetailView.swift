import SwiftUI
import AVKit
import CoreMedia

struct RecordingDetailView: View {
    let recording: Recording
    @EnvironmentObject var recordingsStore: RecordingsStore
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @StateObject private var playerModel = VideoPlayerModel()
    @State private var transcript: Transcript?
    @State private var legacyText: String?

    var body: some View {
        HSplitView {
            videoPlayerSection
                .frame(minWidth: 400)

            transcriptionSection
                .frame(minWidth: 280, idealWidth: 320)
        }
        .onAppear {
            playerModel.load(url: recording.videoURL)
            loadTranscript()
        }
        .onDisappear {
            playerModel.pause()
        }
        .onReceive(transcriptionManager.$states) { states in
            if states[recording.id] == .done {
                loadTranscript()
            }
        }
    }

    private func loadTranscript() {
        transcript = recordingsStore.loadTranscript(for: recording)
        if transcript == nil {
            legacyText = recordingsStore.loadTranscription(for: recording)
        }
    }

    // MARK: - Video Player

    private var videoPlayerSection: some View {
        VStack(spacing: 0) {
            PlayerView(player: playerModel.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text(recording.filename)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Text(recording.formattedDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text(recording.fileSize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    // MARK: - Transcription

    private var transcriptionSection: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Transcription", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                transcriptionActions
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            transcriptionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var transcriptionActions: some View {
        let state = transcriptionManager.states[recording.id] ?? .idle

        switch state {
        case .idle:
            if hasTranscript {
                Button { copyTranscription() } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                Task { await transcriptionManager.transcribe(recording: recording) }
            } label: {
                Label(
                    hasTranscript ? "Re-transcribe" : "Transcribe",
                    systemImage: "waveform"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .extractingAudio, .downloadingModels, .transcribing, .diarizing:
            ProgressView()
                .controlSize(.small)

        case .done:
            Button { copyTranscription() } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button {
                Task { await transcriptionManager.transcribe(recording: recording) }
            } label: {
                Label("Re-transcribe", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

        case .error:
            Button {
                Task { await transcriptionManager.transcribe(recording: recording) }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var transcriptionContent: some View {
        let state = transcriptionManager.states[recording.id] ?? .idle

        if let transcript, state == .idle || state == .done {
            structuredTranscriptView(transcript)
        } else if let legacyText, state == .idle || state == .done {
            ScrollView {
                Text(legacyText)
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch state {
            case .extractingAudio:
                progressView("Extracting audio...", progress: nil)
            case .downloadingModels:
                progressView("Downloading AI models (first time only)...", progress: nil)
            case .transcribing(let progress):
                progressView("Transcribing...", progress: progress)
            case .diarizing:
                progressView("Identifying speakers...", progress: nil)
            case .error(let msg):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.red)
                    Text(msg)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            default:
                VStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.system(size: 40))
                        .foregroundStyle(.quaternary)
                    Text("No Transcription")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                    Text("Click \"Transcribe\" to generate a\ntranscription with speaker detection.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
    }

    // MARK: - Structured Transcript View

    private func structuredTranscriptView(_ transcript: Transcript) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                // Speaker summary
                if transcript.speakers.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(transcript.speakers) { speaker in
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(speakerColor(speaker.color))
                                    .frame(width: 8, height: 8)
                                Text(speaker.name)
                                    .font(.caption2)
                            }
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.05))
                }

                // Segments
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(transcript.segments) { segment in
                        let speaker = transcript.speakers.first(where: { $0.id == segment.speakerId })
                        TranscriptSegmentRow(
                            segment: segment,
                            speaker: speaker,
                            speakerProfileStore: speakerProfileStore
                        ) {
                            playerModel.seek(to: segment.startTime)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    private var hasTranscript: Bool {
        transcript != nil || legacyText != nil || recording.hasTranscription
    }

    private func speakerColor(_ index: Int) -> Color {
        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .teal, .pink, .mint]
        return colors[index % colors.count]
    }

    private func progressView(_ label: String, progress: Double?) -> some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 200)
            } else {
                ProgressView()
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copyTranscription() {
        let text: String
        if let transcript {
            text = transcript.renderMarkdown()
        } else if let legacyText {
            text = legacyText
        } else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - Transcript Segment Row

struct TranscriptSegmentRow: View {
    let segment: TranscriptSegment
    let speaker: TranscriptSpeaker?
    let speakerProfileStore: SpeakerProfileStore
    let onSeek: () -> Void

    private var speakerColor: Color {
        let colors: [Color] = [.blue, .red, .green, .orange, .purple, .teal, .pink, .mint]
        let index = speaker?.color ?? 0
        return colors[index % colors.count]
    }

    var body: some View {
        Button(action: onSeek) {
            HStack(alignment: .top, spacing: 10) {
                // Speaker photo or initial
                speakerAvatar
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(speaker?.name ?? "Unknown")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(speakerColor)

                        Text(formatTimestamp(segment.startTime))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    Text(segment.text)
                        .font(.body)
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color.clear)
        .onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }

    @ViewBuilder
    private var speakerAvatar: some View {
        if let profileId = speaker?.profileId,
           let uuid = UUID(uuidString: profileId),
           let profile = speakerProfileStore.profiles.first(where: { $0.id == uuid }),
           let image = speakerProfileStore.photoImage(for: profile) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(speakerColor.opacity(0.15))
                .overlay(
                    Text(String((speaker?.name ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(speakerColor)
                )
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%02d:%02d", m, s)
    }
}

// MARK: - NSViewRepresentable AVPlayerView wrapper

struct PlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = true
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.player = player
    }
}

// MARK: - Video Player Model

@MainActor
final class VideoPlayerModel: ObservableObject {
    let player = AVPlayer()

    func load(url: URL) {
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
    }

    func pause() {
        player.pause()
    }

    func seek(to time: TimeInterval) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}
