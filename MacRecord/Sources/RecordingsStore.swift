import Foundation
import AppKit
import AVFoundation
import Combine

struct Recording: Identifiable, Hashable {
    let id: String
    let url: URL
    let filename: String
    let date: Date
    let fileSize: String
    let duration: TimeInterval

    static func == (lhs: Recording, rhs: Recording) -> Bool {
        lhs.id == rhs.id
    }
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    init(url: URL) {
        self.id = url.lastPathComponent
        self.url = url
        self.filename = url.deletingPathExtension().lastPathComponent
        self.date = (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate] as? Date) ?? Date()

        let bytes = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        self.fileSize = formatter.string(fromByteCount: bytes)

        let asset = AVAsset(url: url)
        let semaphore = DispatchSemaphore(value: 0)
        var dur: TimeInterval = 0
        Task {
            if let d = try? await asset.load(.duration).seconds {
                dur = d
            }
            semaphore.signal()
        }
        semaphore.wait()
        self.duration = dur
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
        refresh()
        startMonitoring()
    }

    func refresh() {
        let dir = Self.recordingsDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ) else {
            recordings = []
            return
        }

        recordings = files
            .filter { $0.pathExtension == "mov" }
            .map { Recording(url: $0) }
            .sorted { $0.date > $1.date }

        Task { await generateThumbnails() }
    }

    func generateThumbnails() async {
        for recording in recordings {
            guard thumbnails[recording.id] == nil else { continue }
            let asset = AVAsset(url: recording.url)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 180)
            let time = CMTime(seconds: 0.5, preferredTimescale: 600)
            do {
                let (image, _) = try await generator.image(at: time)
                let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                thumbnails[recording.id] = nsImage
            } catch {
                // Skip failed thumbnails
            }
        }
    }

    func openRecording(_ recording: Recording) {
        NSWorkspace.shared.open(recording.url)
    }

    func deleteRecording(_ recording: Recording) {
        try? FileManager.default.removeItem(at: recording.url)
        thumbnails.removeValue(forKey: recording.id)
        refresh()
    }

    func revealInFinder(_ recording: Recording) {
        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
    }

    func openRecordingsFolder() {
        let dir = Self.recordingsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
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
        source.setCancelHandler {
            close(fd)
        }
        source.resume()
        directoryMonitor = source
    }
}
