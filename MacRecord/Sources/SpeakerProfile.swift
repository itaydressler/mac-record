import Foundation
import AppKit
import FluidAudio

struct SpeakerProfile: Codable, Identifiable {
    let id: UUID
    var name: String
    var photoFileName: String?
    var embedding: [Float]
    var createdAt: Date
    var updatedAt: Date

    var isCurrentUser: Bool  // flag for "me"
}

@MainActor
final class SpeakerProfileStore: ObservableObject {
    @Published var profiles: [SpeakerProfile] = []

    static var speakersDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("MacRecord/Speakers")
    }

    init() {
        loadAll()
    }

    func loadAll() {
        let dir = Self.speakersDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else {
            profiles = []
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        profiles = items.compactMap { folder in
            let jsonURL = folder.appendingPathComponent("profile.json")
            guard let data = try? Data(contentsOf: jsonURL),
                  let profile = try? decoder.decode(SpeakerProfile.self, from: data) else { return nil }
            return profile
        }.sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ profile: SpeakerProfile) throws {
        let dir = Self.speakersDirectory.appendingPathComponent(profile.id.uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(profile)
        try data.write(to: dir.appendingPathComponent("profile.json"), options: .atomic)

        loadAll()
    }

    func delete(_ profile: SpeakerProfile) {
        let dir = Self.speakersDirectory.appendingPathComponent(profile.id.uuidString)
        try? FileManager.default.removeItem(at: dir)
        loadAll()
    }

    func profileDirectory(for profile: SpeakerProfile) -> URL {
        Self.speakersDirectory.appendingPathComponent(profile.id.uuidString)
    }

    func photoURL(for profile: SpeakerProfile) -> URL? {
        guard let fileName = profile.photoFileName else { return nil }
        let url = profileDirectory(for: profile).appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func photoImage(for profile: SpeakerProfile) -> NSImage? {
        guard let url = photoURL(for: profile) else { return nil }
        return NSImage(contentsOf: url)
    }

    func savePhoto(_ image: NSImage, for profile: inout SpeakerProfile) throws {
        let dir = profileDirectory(for: profile)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else { return }

        let fileName = "photo.png"
        try pngData.write(to: dir.appendingPathComponent(fileName), options: .atomic)
        profile.photoFileName = fileName
    }

    /// Extract a speaker embedding from a voice sample audio file
    func extractEmbedding(from audioURL: URL) async throws -> [Float] {
        let config = OfflineDiarizerConfig()
        let diarizer = OfflineDiarizerManager(config: config)
        try await diarizer.prepareModels()

        let result = try await diarizer.process(audioURL)

        // Return the embedding of the dominant speaker
        guard let mainSpeaker = result.segments.sorted(by: { $0.durationSeconds > $1.durationSeconds }).first else {
            throw SpeakerProfileError.noSpeechDetected
        }

        return mainSpeaker.embedding
    }

    var currentUser: SpeakerProfile? {
        profiles.first(where: { $0.isCurrentUser })
    }
}

enum SpeakerProfileError: LocalizedError {
    case noSpeechDetected

    var errorDescription: String? {
        switch self {
        case .noSpeechDetected: return "No speech detected in the voice sample."
        }
    }
}
