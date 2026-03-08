import Foundation
import AppKit
import AVFoundation
import Combine

struct Recording: Identifiable, Hashable {
    let id: String
    let folderURL: URL
    let videoURL: URL
    let filename: String
    let date: Date
    let fileSize: String
    let duration: TimeInterval
    let hasTranscription: Bool

    static func == (lhs: Recording, rhs: Recording) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var transcriptionURL: URL {
        folderURL.appendingPathComponent("transcription.md")
    }

    init(folderURL: URL) {
        self.folderURL = folderURL
        self.id = folderURL.lastPathComponent

        // Find the .mov file inside the folder
        let files = (try? FileManager.default.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil))
        let movFile = files?.first(where: { $0.pathExtension == "mov" })
        self.videoURL = movFile ?? folderURL.appendingPathComponent("recording.mov")
        self.filename = folderURL.lastPathComponent

        let attrs = try? FileManager.default.attributesOfItem(atPath: videoURL.path)
        self.date = (attrs?[.creationDate] as? Date) ?? Date()

        let bytes = (attrs?[.size] as? Int64) ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        self.fileSize = formatter.string(fromByteCount: bytes)

        // Check for transcription
        let mdPath = folderURL.appendingPathComponent("transcription.md")
        self.hasTranscription = FileManager.default.fileExists(atPath: mdPath.path)

        // Load duration
        if FileManager.default.fileExists(atPath: videoURL.path) {
            let asset = AVAsset(url: videoURL)
            let semaphore = DispatchSemaphore(value: 0)
            var dur: TimeInterval = 0
            Task {
                if let d = try? await asset.load(.duration).seconds { dur = d }
                semaphore.signal()
            }
            semaphore.wait()
            self.duration = dur
        } else {
            self.duration = 0
        }
    }

    /// Legacy init for flat .mov files (migration)
    init(legacyMovURL: URL, in parentDir: URL) {
        let folderName = legacyMovURL.deletingPathExtension().lastPathComponent
        let folderURL = parentDir.appendingPathComponent(folderName)
        try? FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let destURL = folderURL.appendingPathComponent("recording.mov")
        if !FileManager.default.fileExists(atPath: destURL.path) {
            try? FileManager.default.moveItem(at: legacyMovURL, to: destURL)
        }
        self.init(folderURL: folderURL)
    }

    var formattedDuration: String {
        let total = Int(duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

@MainActor
final class RecordingsStore: ObservableObject {
    @Published var recordings: [Recording] = []
    @Published var thumbnails: [String: NSImage] = [:]

    static var recordingsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("MacRecord")
    }

    private var directoryMonitor: DispatchSourceFileSystemObject?

    init() {
        migrateIfNeeded()
        refresh()
        startMonitoring()
    }

    /// Migrate flat .mov files to folder-per-recording structure
    private func migrateIfNeeded() {
        let dir = Self.recordingsDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil, options: .skipsHiddenFiles
        ) else { return }

        for item in items where item.pathExtension == "mov" {
            _ = Recording(legacyMovURL: item, in: dir)
        }
    }

    func refresh() {
        let dir = Self.recordingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles
        ) else {
            recordings = []
            return
        }

        recordings = items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { folder in
                // Must contain a .mov file
                let contents = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
                return contents.contains(where: { $0.pathExtension == "mov" })
            }
            .map { Recording(folderURL: $0) }
            .sorted { $0.date > $1.date }

        Task { await generateThumbnails() }
    }

    func generateThumbnails() async {
        for recording in recordings {
            guard thumbnails[recording.id] == nil else { continue }
            let asset = AVAsset(url: recording.videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            do {
                let (image, _) = try await generator.image(at: time)
                thumbnails[recording.id] = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            } catch {}
        }
    }

    /// Create a new recording folder and return the video file URL
    func createRecordingFolder() throws -> URL {
        let dir = Self.recordingsDirectory
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let folderName = "Recording-\(formatter.string(from: Date()))"
        let folderURL = dir.appendingPathComponent(folderName)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        return folderURL.appendingPathComponent("recording.mov")
    }

    func openRecording(_ recording: Recording) {
        NSWorkspace.shared.open(recording.videoURL)
    }

    func deleteRecording(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.folderURL)
        thumbnails.removeValue(forKey: recording.id)
        refresh()
    }

    func revealInFinder(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.videoURL])
    }

    func openRecordingsFolder() {
        let dir = Self.recordingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func loadTranscription(for recording: Recording) -> String? {
        try? String(contentsOf: recording.transcriptionURL, encoding: .utf8)
    }

    private func startMonitoring() {
        let dir = Self.recordingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let fd = open(dir.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.refresh()
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        directoryMonitor = source
    }
}
