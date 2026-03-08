import SwiftUI
import AVKit

struct RecordingDetailView: View {
    let recording: Recording
    @EnvironmentObject var recordingsStore: RecordingsStore
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    @StateObject private var playerModel = VideoPlayerModel()
    @State private var transcriptionText: String?

    var body: some View {
        HSplitView {
            // Left: Video player
            videoPlayerSection
                .frame(minWidth: 400)

            // Right: Transcription
            transcriptionSection
                .frame(minWidth: 280, idealWidth: 320)
        }
        .onAppear {
            playerModel.load(url: recording.videoURL)
            transcriptionText = recordingsStore.loadTranscription(for: recording)
        }
        .onDisappear {
            playerModel.pause()
        }
    }

    // MARK: - Video Player

    private var videoPlayerSection: some View {
        VStack(spacing: 0) {
            PlayerView(player: playerModel.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom bar
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
            // Header
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

            // Content
            transcriptionContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var transcriptionActions: some View {
        let state = transcriptionManager.states[recording.id] ?? .idle

        switch state {
        case .idle:
            if recording.hasTranscription || transcriptionText != nil {
                Button {
                    copyTranscription()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                Task { await transcriptionManager.transcribe(recording: recording) }
            } label: {
                Label(
                    recording.hasTranscription ? "Re-transcribe" : "Transcribe",
                    systemImage: "waveform"
                )
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)

        case .extractingAudio, .downloadingModel, .loadingModel, .transcribing:
            ProgressView()
                .controlSize(.small)

        case .done:
            Button {
                copyTranscription()
            } label: {
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

        if let text = transcriptionText, state == .idle || state == .done {
            ScrollView {
                Text(LocalizedStringKey(text))
                    .textSelection(.enabled)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch state {
            case .extractingAudio:
                progressView("Extracting audio...", progress: nil)
            case .downloadingModel:
                progressView("Downloading Whisper model (first time only)...", progress: nil)
            case .loadingModel:
                progressView("Loading Whisper model...", progress: nil)
            case .transcribing(let progress):
                progressView("Transcribing...", progress: progress)
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
                    Text("Click \"Transcribe\" to generate a\ntranscription using Whisper AI.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
        }
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
        guard let text = transcriptionText else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
}
