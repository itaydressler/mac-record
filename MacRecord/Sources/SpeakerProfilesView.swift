import SwiftUI
import AVFoundation

struct SpeakerProfilesView: View {
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @State private var showAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Speaker Profiles")
                    .font(.title2.weight(.bold))
                Spacer()
                Button {
                    showAddSheet = true
                } label: {
                    Label("Add Speaker", systemImage: "person.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
            .background(.bar)

            Divider()

            if speakerProfileStore.profiles.isEmpty {
                emptyState
            } else {
                profilesList
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSpeakerSheet()
                .environmentObject(speakerProfileStore)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.2.wave.2")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No Speaker Profiles")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Add profiles to identify speakers in your recordings.\nStart by adding yourself!")
                .font(.body)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
            Button {
                showAddSheet = true
            } label: {
                Label("Set Up Your Profile", systemImage: "person.badge.plus")
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var profilesList: some View {
        List {
            ForEach(speakerProfileStore.profiles) { profile in
                SpeakerProfileRow(profile: profile)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// MARK: - Profile Row

struct SpeakerProfileRow: View {
    let profile: SpeakerProfile
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 14) {
            // Photo
            profilePhoto
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(profile.name)
                        .font(.body.weight(.medium))
                    if profile.isCurrentUser {
                        Text("You")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.blue))
                    }
                }
                HStack(spacing: 6) {
                    if !profile.embedding.isEmpty {
                        Label("Voice enrolled", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Label("No voice sample", systemImage: "xmark.circle")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.caption)
            }

            Spacer()

            Button {
                showDeleteConfirmation = true
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
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
                .fill(Color.accentColor.opacity(0.15))
                .overlay(
                    Text(String(profile.name.prefix(1)).uppercased())
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
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
    @State private var isRecording = false
    @State private var voiceSampleURL: URL?
    @State private var embedding: [Float] = []
    @State private var extractingEmbedding = false
    @State private var errorMessage: String?
    @State private var audioLevel: Float = 0
    @StateObject private var voiceRecorder = VoiceSampleRecorder()

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New Speaker Profile")
                    .font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Name
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Name")
                            .font(.subheadline.weight(.medium))
                        TextField("e.g. John Smith", text: $name)
                            .textFieldStyle(.roundedBorder)
                    }

                    // Is current user
                    Toggle("This is me", isOn: $isCurrentUser)

                    // Photo
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Photo (optional)")
                            .font(.subheadline.weight(.medium))
                        HStack(spacing: 12) {
                            if let photo {
                                Image(nsImage: photo)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(Circle())
                            } else {
                                Circle()
                                    .fill(Color.secondary.opacity(0.15))
                                    .frame(width: 64, height: 64)
                                    .overlay(
                                        Image(systemName: "person.fill")
                                            .font(.title2)
                                            .foregroundStyle(.secondary)
                                    )
                            }
                            Button("Choose Photo...") {
                                pickPhoto()
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Voice sample
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Voice Sample")
                            .font(.subheadline.weight(.medium))
                        Text("Record 5-10 seconds of speech to enable speaker identification.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if voiceRecorder.isRecording {
                                // Recording indicator
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(.red)
                                        .frame(width: 8, height: 8)
                                    Text("Recording... \(String(format: "%.0fs", voiceRecorder.duration))")
                                        .font(.system(.body, design: .monospaced))
                                }

                                Button("Stop") {
                                    Task {
                                        if let url = await voiceRecorder.stop() {
                                            voiceSampleURL = url
                                            await extractVoiceEmbedding(from: url)
                                        }
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.red)
                            } else if extractingEmbedding {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Analyzing voice...")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if !embedding.isEmpty {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Voice enrolled")
                                    .font(.caption)
                                Button("Re-record") {
                                    Task { try? await voiceRecorder.start() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button {
                                    Task { try? await voiceRecorder.start() }
                                } label: {
                                    Label("Record Voice", systemImage: "mic.fill")
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    if let error = errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                .padding(20)
            }

            Divider()

            // Save button
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save Profile") {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
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
