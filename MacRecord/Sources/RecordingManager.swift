import Foundation
import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreMedia
import Combine

enum RecordingState: Equatable {
    case idle
    case preparingToRecord
    case recording
    case stopping
}

@MainActor
final class RecordingManager: NSObject, ObservableObject {
    @Published var state: RecordingState = .idle
    @Published var availableDisplays: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var selectedDisplay: SCDisplay?
    @Published var selectedWindow: SCWindow?
    @Published var recordingMode: RecordingMode = .display
    @Published var elapsedTime: TimeInterval = 0
    @Published var errorMessage: String?
    @Published var displayThumbnails: [CGDirectDisplayID: NSImage] = [:]
    @Published var windowThumbnails: [CGWindowID: NSImage] = [:]

    enum RecordingMode: String, CaseIterable {
        case display = "Screen"
        case window = "Window"
    }

    private var stream: SCStream?
    private var sessionStartDate: Date?
    private var timer: Timer?
    private var outputURL: URL?
    private let streamOutput = StreamOutput()
    private let writer = SampleWriter()

    override init() {
        super.init()
        streamOutput.writer = writer
        Task { await refreshAvailableContent() }
    }

    func refreshAvailableContent() async {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            availableDisplays = content.displays
            availableWindows = content.windows.filter { window in
                guard let title = window.title, !title.isEmpty else { return false }
                guard let app = window.owningApplication else { return false }
                let excluded = ["", "Window Server", "SystemUIServer"]
                return !excluded.contains(app.applicationName)
            }
            if selectedDisplay == nil {
                selectedDisplay = availableDisplays.first
            }
            await captureThumbnails()
        } catch {
            errorMessage = "Failed to get available content: \(error.localizedDescription)"
        }
    }

    func captureThumbnails() async {
        for display in availableDisplays {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let excludedApps = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
                let filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 200
                config.showsCursor = true
                config.scalesToFit = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                displayThumbnails[display.displayID] = nsImage
            } catch {
                // Skip failed thumbnails
            }
        }

        for window in availableWindows {
            do {
                let filter = SCContentFilter(desktopIndependentWindow: window)
                let config = SCStreamConfiguration()
                config.width = 320
                config.height = 200
                config.showsCursor = false
                config.scalesToFit = true
                let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                let nsImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                windowThumbnails[window.windowID] = nsImage
            } catch {
                // Skip failed thumbnails
            }
        }
    }

    func appIcon(for window: SCWindow) -> NSImage? {
        guard let bundleID = window.owningApplication?.bundleIdentifier,
              let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    func startRecording() async {
        guard state == .idle else { return }
        state = .preparingToRecord
        errorMessage = nil

        do {
            let filter: SCContentFilter
            if recordingMode == .window, let window = selectedWindow {
                filter = SCContentFilter(desktopIndependentWindow: window)
            } else if let display = selectedDisplay {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                let excludedApps = content.applications.filter { app in
                    app.bundleIdentifier == Bundle.main.bundleIdentifier
                }
                filter = SCContentFilter(display: display, excludingApplications: excludedApps, exceptingWindows: [])
            } else {
                throw RecordingError.noSource
            }

            let config = SCStreamConfiguration()
            let displaySize = filter.contentRect.size
            config.width = Int(displaySize.width) * 2
            config.height = Int(displaySize.height) * 2
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.showsCursor = true
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true

            // Set up output file
            let recordingsDir = RecordingsStore.recordingsDirectory
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let filename = "Recording-\(formatter.string(from: Date())).mov"
            let url = recordingsDir.appendingPathComponent(filename)
            outputURL = url

            // Configure the writer (thread-safe, writes on capture queue)
            try writer.setUp(url: url, videoWidth: config.width, videoHeight: config.height)

            // Start the stream — separate queues for video and audio to prevent starvation
            let videoQueue = DispatchQueue(label: "com.tinyworks.MacRecord.video", qos: .userInitiated)
            let audioQueue = DispatchQueue(label: "com.tinyworks.MacRecord.audio", qos: .userInitiated)
            let stream = SCStream(filter: filter, configuration: config, delegate: streamOutput)
            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoQueue)
            try stream.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: audioQueue)

            try await stream.startCapture()
            self.stream = stream

            state = .recording
            sessionStartDate = Date()
            startTimer()
        } catch {
            state = .idle
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        guard state == .recording else { return }
        state = .stopping

        do {
            try await stream?.stopCapture()
            stream = nil

            await writer.finish()

            stopTimer()
            state = .idle
            elapsedTime = 0
        } catch {
            errorMessage = "Failed to stop recording: \(error.localizedDescription)"
            state = .idle
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let start = self.sessionStartDate else { return }
                self.elapsedTime = Date().timeIntervalSince(start)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Sample Writer (thread-safe, operates on capture queue)

final class SampleWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var audioInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var firstVideoTimestamp: CMTime?
    private var firstAudioTimestamp: CMTime?

    func setUp(url: URL, videoWidth: Int, videoHeight: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: videoWidth,
            AVVideoHeightKey: videoHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        vInput.mediaTimeScale = CMTimeScale(NSEC_PER_SEC)

        // Build a source format hint matching ScreenCaptureKit's 32-bit float interleaved LPCM
        var audioDesc = AudioStreamBasicDescription(
            mSampleRate: 48000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var sourceFormat: CMAudioFormatDescription?
        CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &audioDesc,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &sourceFormat
        )

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]
        let aInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings, sourceFormatHint: sourceFormat)
        aInput.expectsMediaDataInRealTime = true

        writer.add(vInput)
        writer.add(aInput)

        assetWriter = writer
        videoInput = vInput
        audioInput = aInput
        sessionStarted = false
        firstVideoTimestamp = nil
        firstAudioTimestamp = nil
    }

    private var videoFrameCount: Int = 0
    private var audioFrameCount: Int = 0
    private var audioDropCount: Int = 0

    func appendSampleBuffer(_ sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        lock.lock()
        defer { lock.unlock() }

        guard let assetWriter = assetWriter else { return }

        // For video frames, check the ScreenCaptureKit frame status
        if type == .screen {
            guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let attachments = attachmentsArray.first,
                  let statusRaw = attachments[.status] as? Int,
                  let status = SCFrameStatus(rawValue: statusRaw),
                  status == .complete else {
                return
            }
        }

        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard timestamp.isValid, timestamp.flags.contains(.valid) else { return }

        // Start the writer and session on the very first valid sample
        if !sessionStarted {
            guard assetWriter.status == .unknown else { return }
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: timestamp)
            sessionStarted = true
        }

        guard assetWriter.status == .writing else { return }

        switch type {
        case .screen:
            if firstVideoTimestamp == nil { firstVideoTimestamp = timestamp }
            videoFrameCount += 1
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio, .microphone:
            // Only start writing audio after we have at least one video frame
            guard firstVideoTimestamp != nil else { return }

            audioFrameCount += 1
            if firstAudioTimestamp == nil {
                firstAudioTimestamp = timestamp
                // First audio sample received
            }
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                audioInput.append(sampleBuffer)
            } else {
                audioDropCount += 1
            }
        @unknown default:
            break
        }
    }

    func finish() async {
        lock.lock()
        let writer = assetWriter
        let vInput = videoInput
        let aInput = audioInput
        let started = sessionStarted
        let vCount = videoFrameCount
        let aCount = audioFrameCount
        let aDrop = audioDropCount
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        sessionStarted = false
        firstVideoTimestamp = nil
        firstAudioTimestamp = nil
        videoFrameCount = 0
        audioFrameCount = 0
        audioDropCount = 0
        lock.unlock()

        guard let writer = writer, started, writer.status == .writing else { return }

        vInput?.markAsFinished()
        aInput?.markAsFinished()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }
}

// MARK: - Stream Output Delegate

final class StreamOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    var writer: SampleWriter?

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        writer?.appendSampleBuffer(sampleBuffer, of: type)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Errors handled by writer status
    }
}

enum RecordingError: LocalizedError {
    case noSource

    var errorDescription: String? {
        switch self {
        case .noSource:
            return "No screen or window selected for recording."
        }
    }
}
