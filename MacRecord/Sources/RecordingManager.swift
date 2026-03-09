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
    @Published var isPaused: Bool = false
    @Published var displayThumbnails: [CGDirectDisplayID: NSImage] = [:]
    @Published var windowThumbnails: [CGWindowID: NSImage] = [:]

    enum RecordingMode: String, CaseIterable {
        case display = "Screen"
        case window = "Window"
    }

    private var stream: SCStream?
    private var timer: Timer?
    private var outputURL: URL?
    private var recordingStartDate: Date?
    private var totalPausedDuration: TimeInterval = 0
    private var lastPauseDate: Date?
    private let streamOutput = StreamOutput()
    private let writer = SampleWriter()
    let floatingToolbar = FloatingToolbarController()

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
            } catch {}
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
            } catch {}
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
            if recordingMode == .window, let window = selectedWindow {
                config.width = Int(window.frame.width) * 2
                config.height = Int(window.frame.height) * 2
                config.scalesToFit = true
            } else {
                let displaySize = filter.contentRect.size
                config.width = Int(displaySize.width) * 2
                config.height = Int(displaySize.height) * 2
            }
            config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
            config.showsCursor = true
            config.capturesAudio = true
            config.sampleRate = 48000
            config.channelCount = 2
            config.excludesCurrentProcessAudio = true

            if #available(macOS 15, *) {
                config.captureMicrophone = true
                if let defaultMic = AVCaptureDevice.default(for: .audio) {
                    config.microphoneCaptureDeviceID = defaultMic.uniqueID
                }
            }

            // Set up output file in its own folder
            let recordingsDir = RecordingsStore.recordingsDirectory
            try FileManager.default.createDirectory(at: recordingsDir, withIntermediateDirectories: true)

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
            let folderName = "Recording-\(formatter.string(from: Date()))"
            let folderURL = recordingsDir.appendingPathComponent(folderName)
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

            let url = folderURL.appendingPathComponent("recording.mov")
            outputURL = url

            try writer.setUp(url: url, videoWidth: config.width, videoHeight: config.height, includeMicrophone: true)

            let videoQueue = DispatchQueue(label: "com.tinyworks.MacRecord.video", qos: .userInitiated)
            let audioQueue = DispatchQueue(label: "com.tinyworks.MacRecord.audio", qos: .userInitiated)
            let stream = SCStream(filter: filter, configuration: config, delegate: streamOutput)
            try stream.addStreamOutput(streamOutput, type: .screen, sampleHandlerQueue: videoQueue)
            try stream.addStreamOutput(streamOutput, type: .audio, sampleHandlerQueue: audioQueue)

            if #available(macOS 15, *) {
                let micQueue = DispatchQueue(label: "com.tinyworks.MacRecord.mic", qos: .userInitiated)
                try stream.addStreamOutput(streamOutput, type: .microphone, sampleHandlerQueue: micQueue)
            }

            try await stream.startCapture()
            self.stream = stream

            state = .recording
            isPaused = false
            totalPausedDuration = 0
            lastPauseDate = nil
            recordingStartDate = Date()
            startTimer()
        } catch {
            state = .idle
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    func stopRecording() async {
        guard state == .recording else { return }
        state = .stopping

        // If paused, account for remaining pause time
        if isPaused, let pauseDate = lastPauseDate {
            totalPausedDuration += Date().timeIntervalSince(pauseDate)
        }
        isPaused = false

        stopTimer()

        do {
            try await stream?.stopCapture()
        } catch {}
        stream = nil

        await writer.finish()

        state = .idle
        elapsedTime = 0
    }

    func pauseRecording() async {
        guard state == .recording, !isPaused else { return }
        writer.setPaused(true)
        isPaused = true
        lastPauseDate = Date()
        stopTimer()
    }

    func resumeRecording() async {
        guard state == .recording, isPaused else { return }
        if let pauseDate = lastPauseDate {
            totalPausedDuration += Date().timeIntervalSince(pauseDate)
        }
        lastPauseDate = nil
        writer.setPaused(false)
        isPaused = false
        startTimer()
    }

    // MARK: - Timer

    private func startTimer() {
        updateElapsedTime()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateElapsedTime()
            }
        }
    }

    private func updateElapsedTime() {
        guard let start = recordingStartDate else { return }
        let total = Date().timeIntervalSince(start)
        elapsedTime = total - totalPausedDuration
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
    private var micInput: AVAssetWriterInput?
    private var sessionStarted = false
    private var firstVideoTimestamp: CMTime?

    // Pause support: track total paused time and offset timestamps
    private var paused = false
    private var pauseStartTime: CMTime?
    private var totalPausedTime: CMTime = .zero

    func setPaused(_ value: Bool) {
        lock.lock()
        if value && !paused {
            // Starting pause — we'll record the next sample's timestamp as pause start
            paused = true
            pauseStartTime = nil // will be set on next sample
        } else if !value && paused {
            // Resuming — pauseStartTime to now will be calculated on next sample
            paused = false
        }
        lock.unlock()
    }

    func setUp(url: URL, videoWidth: Int, videoHeight: Int, includeMicrophone: Bool = false) throws {
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

        if includeMicrophone {
            let micSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 96000
            ]
            let mInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            mInput.expectsMediaDataInRealTime = true
            writer.add(mInput)
            micInput = mInput
        } else {
            micInput = nil
        }

        assetWriter = writer
        videoInput = vInput
        audioInput = aInput
        sessionStarted = false
        firstVideoTimestamp = nil
        paused = false
        pauseStartTime = nil
        totalPausedTime = .zero
    }

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

        // Handle pause: record when pause started, accumulate when resumed
        if paused {
            if pauseStartTime == nil {
                pauseStartTime = timestamp
            }
            return // Drop samples while paused
        } else if let pauseStart = pauseStartTime {
            // Just resumed: add the pause duration to total offset
            let pauseDuration = CMTimeSubtract(timestamp, pauseStart)
            totalPausedTime = CMTimeAdd(totalPausedTime, pauseDuration)
            pauseStartTime = nil
        }

        // Offset the timestamp to remove paused gaps
        let adjustedTime = CMTimeSubtract(timestamp, totalPausedTime)

        // Start the writer and session on the very first valid sample
        if !sessionStarted {
            guard assetWriter.status == .unknown else { return }
            assetWriter.startWriting()
            assetWriter.startSession(atSourceTime: adjustedTime)
            sessionStarted = true
        }

        guard assetWriter.status == .writing else { return }

        switch type {
        case .screen:
            if firstVideoTimestamp == nil { firstVideoTimestamp = adjustedTime }
            if let videoInput = videoInput, videoInput.isReadyForMoreMediaData {
                if let adjusted = Self.adjustedSampleBuffer(sampleBuffer, newTime: adjustedTime) {
                    videoInput.append(adjusted)
                }
            }
        case .audio:
            guard firstVideoTimestamp != nil else { return }
            if let audioInput = audioInput, audioInput.isReadyForMoreMediaData {
                if let adjusted = Self.adjustedSampleBuffer(sampleBuffer, newTime: adjustedTime) {
                    audioInput.append(adjusted)
                }
            }
        case .microphone:
            guard firstVideoTimestamp != nil else { return }
            if let micInput = micInput, micInput.isReadyForMoreMediaData {
                if let adjusted = Self.adjustedSampleBuffer(sampleBuffer, newTime: adjustedTime) {
                    micInput.append(adjusted)
                }
            }
        @unknown default:
            break
        }
    }

    /// Create a copy of a CMSampleBuffer with an adjusted presentation timestamp
    private static func adjustedSampleBuffer(_ sampleBuffer: CMSampleBuffer, newTime: CMTime) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(sampleBuffer),
            presentationTimeStamp: newTime,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: sampleBuffer,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        return status == noErr ? newBuffer : nil
    }

    func finish() async {
        lock.lock()
        let writer = assetWriter
        let vInput = videoInput
        let aInput = audioInput
        let mInput = micInput
        let started = sessionStarted
        assetWriter = nil
        videoInput = nil
        audioInput = nil
        micInput = nil
        sessionStarted = false
        firstVideoTimestamp = nil
        paused = false
        pauseStartTime = nil
        totalPausedTime = .zero
        lock.unlock()

        guard let writer = writer, started, writer.status == .writing else { return }

        vInput?.markAsFinished()
        aInput?.markAsFinished()
        mInput?.markAsFinished()

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
