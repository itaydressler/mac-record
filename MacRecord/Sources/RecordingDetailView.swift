import SwiftUI
import AVKit
import CoreMedia

struct RecordingDetailView: View {
    let recording: Recording
    @ObservedObject var playerModel: VideoPlayerModel
    @EnvironmentObject var recordingsStore: RecordingsStore
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @State private var transcript: Transcript?
    @State private var legacyText: String?

    var body: some View {
        VStack(spacing: 0) {
            WindowDragArea()
                .frame(height: 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Title
                    Text(recording.filename)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(SpokeTheme.textPrimary)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 6)

                    // Metadata
                    HStack(spacing: 8) {
                        Label {
                            Text(recording.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
                        } icon: {
                            Image(systemName: "calendar")
                        }
                        Text("·")
                        Label(recording.formattedDuration, systemImage: "clock")
                        Text("·")
                        Label(recording.fileSize, systemImage: "doc")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(SpokeTheme.textSecondary)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)

                    // Transcript card
                    transcriptCard
                        .padding(.horizontal, 24)
                }
                .padding(.top, 8)
            }
        }
        .background(SpokeTheme.contentBg)
        .onAppear {
            loadTranscript()
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

    // MARK: - Transcript Card (Superlist-style rounded card)

    private var transcriptCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Card header
            HStack(spacing: 12) {
                // Transcript icon
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(SpokeTheme.accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: "text.quote")
                        .font(.system(size: 16))
                        .foregroundStyle(SpokeTheme.accent)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Meeting transcript")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SpokeTheme.textPrimary)
                    HStack(spacing: 6) {
                        Text(recording.date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                        Text("·")
                        Text(recording.date, style: .time)
                        Text("·")
                        Text(recording.formattedDuration)
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(SpokeTheme.textSecondary)
                }

                Spacer()

                // Actions
                HStack(spacing: 6) {
                    if hasTranscript {
                        Button { copyTranscription() } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 12))
                        }
                        .buttonStyle(SpokeGhostButtonStyle())
                    }

                    transcriptionActionButton
                }
            }
            .padding(16)

            Rectangle()
                .fill(SpokeTheme.divider)
                .frame(height: 1)
                .padding(.horizontal, 16)

            // Transcript content
            transcriptionContent
                .padding(.vertical, 8)
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(SpokeTheme.cardBg)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(SpokeTheme.cardBorder, lineWidth: 1)
                )
        )
    }

    // MARK: - Transcription Action Button

    @ViewBuilder
    private var transcriptionActionButton: some View {
        let state = transcriptionManager.states[recording.id] ?? .idle

        switch state {
        case .idle:
            if hasTranscript {
                Button {
                    Task { await transcriptionManager.transcribe(recording: recording) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11))
                        Text("Redo")
                    }
                }
                .buttonStyle(SpokeGhostButtonStyle())
            } else {
                Button {
                    Task { await transcriptionManager.transcribe(recording: recording) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "waveform")
                            .font(.system(size: 11))
                        Text("Transcribe")
                    }
                }
                .buttonStyle(SpokeAccentButtonStyle())
            }

        case .extractingAudio, .downloadingModels, .transcribing, .diarizing:
            ProgressView()
                .controlSize(.small)

        case .done:
            Button {
                Task { await transcriptionManager.transcribe(recording: recording) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Redo")
                }
            }
            .buttonStyle(SpokeGhostButtonStyle())

        case .error:
            Button {
                Task { await transcriptionManager.transcribe(recording: recording) }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                    Text("Retry")
                }
            }
            .buttonStyle(SpokeGhostButtonStyle())
        }
    }

    // MARK: - Transcription Content

    @ViewBuilder
    private var transcriptionContent: some View {
        let state = transcriptionManager.states[recording.id] ?? .idle

        if let transcript, state == .idle || state == .done {
            structuredTranscriptContent(transcript)
        } else if let legacyText, state == .idle || state == .done {
            Text(legacyText)
                .textSelection(.enabled)
                .font(.system(size: 13))
                .foregroundStyle(SpokeTheme.textPrimary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            switch state {
            case .extractingAudio:
                progressContent("Extracting audio...", progress: nil)
            case .downloadingModels:
                progressContent("Downloading AI models (first time only)...", progress: nil)
            case .transcribing(let progress):
                progressContent("Transcribing...", progress: progress)
            case .diarizing:
                progressContent("Identifying speakers...", progress: nil)
            case .error(let msg):
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(SpokeTheme.recording)
                    Text(msg)
                        .font(.system(size: 12))
                        .foregroundStyle(SpokeTheme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity)
            default:
                // Empty state with placeholder lines
                VStack(spacing: 16) {
                    Image(systemName: "waveform")
                        .font(.system(size: 24))
                        .foregroundStyle(SpokeTheme.textTertiary)
                    Text("Click \"Transcribe\" to generate a transcript\nwith speaker detection.")
                        .font(.system(size: 13))
                        .foregroundStyle(SpokeTheme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .padding(32)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func structuredTranscriptContent(_ transcript: Transcript) -> some View {
        VStack(spacing: 0) {
            // Speaker summary
            if transcript.speakers.count > 1 {
                HStack(spacing: 10) {
                    ForEach(transcript.speakers) { speaker in
                        HStack(spacing: 5) {
                            Circle()
                                .fill(speakerColor(speaker.color))
                                .frame(width: 7, height: 7)
                            Text(speaker.name)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(SpokeTheme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Rectangle()
                    .fill(SpokeTheme.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 16)
            }

            // Segments
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(transcript.segments) { segment in
                    let speaker = transcript.speakers.first(where: { $0.id == segment.speakerId })
                    TranscriptSegmentRow(
                        segment: segment,
                        speaker: speaker,
                        speakerProfileStore: speakerProfileStore
                    ) {
                        playerModel.seek(to: segment.startTime)
                        playerModel.player.play()
                    }
                }
            }
        }
    }

    private var hasTranscript: Bool {
        transcript != nil || legacyText != nil || recording.hasTranscription
    }

    private func speakerColor(_ index: Int) -> Color {
        SpokeTheme.speakerColors[index % SpokeTheme.speakerColors.count]
    }

    private func progressContent(_ label: String, progress: Double?) -> some View {
        VStack(spacing: 12) {
            if let progress {
                ProgressView(value: progress)
                    .frame(width: 180)
                    .tint(SpokeTheme.accent)
            } else {
                ProgressView()
                    .tint(SpokeTheme.accent)
            }
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(SpokeTheme.textSecondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
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
    @State private var isHovered = false

    private var speakerColor: Color {
        let index = speaker?.color ?? 0
        return SpokeTheme.speakerColors[index % SpokeTheme.speakerColors.count]
    }

    var body: some View {
        Button(action: onSeek) {
            HStack(alignment: .top, spacing: 10) {
                speakerAvatar
                    .frame(width: 26, height: 26)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(speaker?.name ?? "Unknown")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(speakerColor)

                        Text(formatTimestamp(segment.startTime))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpokeTheme.textTertiary)
                    }

                    Text(segment.text)
                        .font(.system(size: 13))
                        .foregroundStyle(SpokeTheme.textPrimary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isHovered ? SpokeTheme.sidebarHover : Color.clear)
        .onHover { hovering in
            isHovered = hovering
            if hovering { NSCursor.pointingHand.push() }
            else { NSCursor.pop() }
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
                .fill(speakerColor.opacity(0.12))
                .overlay(
                    Text(String((speaker?.name ?? "?").prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
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
