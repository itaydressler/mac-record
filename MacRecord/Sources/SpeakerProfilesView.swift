import SwiftUI
import AVFoundation

struct SpeakerProfilesView: View {
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Speaker Profiles")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SpokeTheme.textPrimary)
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.badge.plus")
                            .font(.system(size: 12))
                        Text("Add Speaker")
                    }
                }
                .buttonStyle(SpokeAccentButtonStyle())
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)

            Rectangle()
                .fill(SpokeTheme.divider)
                .frame(height: 1)

            if speakerProfileStore.profiles.isEmpty {
                emptyState
            } else {
                profilesList
            }
        }
        .background(SpokeTheme.contentBg)
        .sheet(isPresented: $showAddSheet) {
            AddSpeakerSheet()
                .environmentObject(speakerProfileStore)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 40))
                .foregroundStyle(SpokeTheme.textTertiary)
            Text("No Speaker Profiles")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(SpokeTheme.textSecondary)
            Text("Add profiles to identify speakers in your recordings.\nStart by adding yourself!")
                .font(.system(size: 13))
                .foregroundStyle(SpokeTheme.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                showAddSheet = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.badge.plus")
                    Text("Set Up Your Profile")
                }
            }
            .buttonStyle(SpokeAccentButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profilesList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(speakerProfileStore.profiles) { profile in
                    SpeakerProfileRow(profile: profile)
                        .padding(.horizontal, 12)
                }
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Profile Row

struct SpeakerProfileRow: View {
    let profile: SpeakerProfile
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @State private var showDeleteConfirmation = false
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 14) {
            profilePhoto
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(SpokeTheme.textPrimary)
                    if profile.isCurrentUser {
                        Text("You")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SpokeTheme.accent))
                    }
                }
                HStack(spacing: 6) {
                    if !profile.embedding.isEmpty {
                        Label("Voice enrolled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(SpokeTheme.success)
                    } else {
                        Label("No voice sample", systemImage: "xmark.circle")
                            .foregroundStyle(SpokeTheme.textTertiary)
                    }
                }
                .font(.system(size: 11))
            }

            Spacer()

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(SpokeTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .opacity(isHovered ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? SpokeTheme.sidebarHover : Color.clear)
        )
        .onHover { isHovered = $0 }
        .alert("Delete Speaker Profile?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                speakerProfileStore.delete(profile)
            }
        } message: {
            Text("Are you sure you want to delete \"\(profile.name)\"?")
        }
    }

    @ViewBuilder
    private var profilePhoto: some View {
        if let image = speakerProfileStore.photoImage(for: profile) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(SpokeTheme.accent.opacity(0.12))
                .overlay(
                    Text(String(profile.name.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(SpokeTheme.accent)
                )
        }
    }
}

// MARK: - Add Speaker Sheet

struct AddSpeakerSheet: View {
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @Environment(\.dismiss) var dismiss

    @State private var name = ""
    @State private var isCurrentUser = false
    @State private var photo: NSImage?
    @State private var voiceSampleURL: URL?
    @State private var embedding: [Float] = []
    @State private var extractingEmbedding = false
    @State private var errorMessage: String?
    @StateObject private var voiceRecorder = VoiceSampleRecorder()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Speaker Profile")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SpokeTheme.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SpokeTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Rectangle()
                .fill(SpokeTheme.divider)
                .frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SpokeTheme.textSecondary)
                        TextField("e.g. John Smith", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    Toggle("This is me", isOn: $isCurrentUser)
                        .foregroundStyle(SpokeTheme.textPrimary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Photo (optional)")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SpokeTheme.textSecondary)
                        HStack(spacing: 12) {
                            if let photo {
                                Image(nsImage: photo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 56, height: 56)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(SpokeTheme.cardBg)
                                    .frame(width: 56, height: 56)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.system(size: 20))
                                            .foregroundStyle(SpokeTheme.textTertiary)
                                    )
                            }
                            Button("Choose Photo...") { pickPhoto() }
                                .buttonStyle(SpokeGhostButtonStyle())
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice Sample")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(SpokeTheme.textSecondary)
                        Text("Record 5-10 seconds of speech to enable speaker identification.")
                            .font(.system(size: 11))
                            .foregroundStyle(SpokeTheme.textTertiary)

                        HStack(spacing: 12) {
                            if voiceRecorder.isRecording {
                                HStack(spacing: 8) {
                                    Circle().fill(SpokeTheme.recording).frame(width: 8, height: 8)
                                    Text("Recording... \(String(format: "%.0fs", voiceRecorder.duration))")
                                        .font(.system(size: 13, design: .monospaced))
                                        .foregroundStyle(SpokeTheme.textPrimary)
                                }
                                Button("Stop") {
                                    Task {
                                        if let url = await voiceRecorder.stop() {
                                            voiceSampleURL = url
                                            await extractVoiceEmbedding(from: url)
                                        }
                                    }
                                }
                                .buttonStyle(SpokeRecordButtonStyle())
                            } else if extractingEmbedding {
                                ProgressView().controlSize(.small)
                                Text("Analyzing voice...")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SpokeTheme.textSecondary)
                            } else if !embedding.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(SpokeTheme.success)
                                Text("Voice enrolled")
                                    .font(.system(size: 12))
                                    .foregroundStyle(SpokeTheme.textSecondary)
                                Button("Re-record") {
                                    Task { try? await voiceRecorder.start() }
                                }
                                .buttonStyle(SpokeGhostButtonStyle())
                            } else {
                                Button {
                                    Task { try? await voiceRecorder.start() }
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "mic.fill")
                                        Text("Record Voice")
                                    }
                                }
                                .buttonStyle(SpokeAccentButtonStyle())
                            }
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundStyle(SpokeTheme.recording)
                    }
                }
                .padding(24)
            }

            Rectangle()
                .fill(SpokeTheme.divider)
                .frame(height: 1)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SpokeGhostButtonStyle())
                Button("Save Profile") { saveProfile() }
                    .buttonStyle(SpokeAccentButtonStyle())
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(SpokeTheme.contentBg)
        .frame(width: 440, height: 520)
    }

    private func pickPhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            photo = NSImage(contentsOf: url)
        }
    }

    private func extractVoiceEmbedding(from url: URL) async {
        extractingEmbedding = true
        errorMessage = nil
        do {
            embedding = try await speakerProfileStore.extractEmbedding(from: url)
        } catch {
            errorMessage = "Failed to analyze voice: \(error.localizedDescription)"
        }
        extractingEmbedding = false
    }

    private func saveProfile() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        var profile = SpeakerProfile(
            id: UUID(),
            name: trimmedName,
            photoFileName: nil,
            embedding: embedding,
            createdAt: Date(),
            updatedAt: Date(),
            isCurrentUser: isCurrentUser
        )
        do {
            if let photo {
                try speakerProfileStore.savePhoto(photo, for: &profile)
            }
            try speakerProfileStore.save(profile)
            dismiss()
        } catch {
            errorMessage = "Failed to save profile: \(error.localizedDescription)"
        }
    }
}

// MARK: - Voice Sample Recorder

@MainActor
final class VoiceSampleRecorder: ObservableObject {
    @Published var isRecording = false
    @Published var duration: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var outputFile: AVAudioFile?
    private var outputURL: URL?
    private var timer: Timer?
    private var startTime: Date?

    func start() async throws {
        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice_sample_\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: tempURL, settings: format.settings)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, _ in
            try? file.write(from: buffer)
        }
        engine.prepare()
        try engine.start()
        self.audioEngine = engine
        self.outputFile = file
        self.outputURL = tempURL
        self.isRecording = true
        self.startTime = Date()
        self.duration = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let start = self.startTime else { return }
                self.duration = Date().timeIntervalSince(start)
            }
        }
    }

    func stop() async -> URL? {
        timer?.invalidate()
        timer = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        outputFile = nil
        isRecording = false
        return outputURL
    }
}
