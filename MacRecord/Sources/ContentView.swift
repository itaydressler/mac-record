import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var recordingsStore: RecordingsStore
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    @EnvironmentObject var speakerProfileStore: SpeakerProfileStore
    @State private var selectedRecording: Recording?
    @State private var showSourcePicker = false
    @State private var showSpeakerProfiles = false

    var body: some View {
        Group {
            if let recording = selectedRecording {
                VStack(spacing: 0) {
                    HStack {
                        Button {
                            selectedRecording = nil
                        } label: {
                            Label("Back", systemImage: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.bar)
                    Divider()

                    RecordingDetailView(recording: recording)
                }
            } else {
                mainView
            }
        }
        .environmentObject(recordingManager)
        .environmentObject(recordingsStore)
        .environmentObject(transcriptionManager)
        .environmentObject(speakerProfileStore)
        .sheet(isPresented: $showSpeakerProfiles) {
            SpeakerProfilesView()
                .environmentObject(speakerProfileStore)
                .frame(width: 500, height: 450)
        }
        .onReceive(recordingManager.$state) { newState in
            if newState == .idle {
                // Auto-transcribe the latest recording after stopping
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    recordingsStore.refresh()
                    if let latest = recordingsStore.recordings.first, !latest.hasTranscription {
                        Task {
                            await transcriptionManager.transcribe(recording: latest)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Main View (Recordings + Record Button)

    private var mainView: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Recordings")
                        .font(.title2.weight(.bold))

                    Spacer()

                    if recordingManager.state == .recording {
                        recordingIndicator
                    }

                    Button {
                        showSpeakerProfiles = true
                    } label: {
                        Image(systemName: "person.2")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        recordingsStore.openRecordingsFolder()
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(.bar)

                Divider()

                // Recordings list
                if recordingsStore.recordings.isEmpty {
                    emptyState
                } else {
                    recordingsList
                }
            }

            // Floating record button area
            if recordingManager.state == .idle && !showSourcePicker {
                recordButton
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Source picker overlay
            if showSourcePicker {
                sourcePickerOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            // Active recording overlay
            if recordingManager.state == .recording {
                activeRecordingBar
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: showSourcePicker)
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: recordingManager.state)
    }

    // MARK: - Recording Indicator (header)

    private var recordingIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.red)
                .frame(width: 8, height: 8)
                .shadow(color: .red.opacity(0.6), radius: 4)
            Text(formatTime(recordingManager.elapsedTime))
                .font(.system(.body, design: .monospaced, weight: .medium))
                .foregroundStyle(.red)
        }
        .padding(.trailing, 8)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No Recordings Yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Hit the record button to get started.")
                .font(.body)
                .foregroundStyle(.tertiary)

            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        List {
            ForEach(recordingsStore.recordings) { recording in
                RecordingRow(recording: recording)
                    .onTapGesture {
                        selectedRecording = recording
                    }
                    .contextMenu {
                        Button("Open in Player") { recordingsStore.openRecording(recording) }
                        ShareLink(item: recording.videoURL)
                        Button("Reveal in Finder") { recordingsStore.revealInFinder(recording) }
                        Divider()
                        Button("Delete", role: .destructive) { recordingsStore.deleteRecording(recording) }
                    }
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: true))
    }

    // MARK: - Record Button

    private var recordButton: some View {
        Button {
            Task { await recordingManager.refreshAvailableContent() }
            withAnimation { showSourcePicker = true }
        } label: {
            HStack(spacing: 10) {
                RecordButtonDot()
                Text("New Recording")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background(
                Capsule()
                    .fill(.red)
                    .shadow(color: .red.opacity(0.4), radius: 12, y: 4)
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.init("r"), modifiers: [.command, .shift])
    }

    // MARK: - Active Recording Bar

    private var activeRecordingBar: some View {
        HStack(spacing: 16) {
            Circle()
                .fill(.red)
                .frame(width: 10, height: 10)
                .shadow(color: .red.opacity(0.8), radius: 6)

            Text(formatTime(recordingManager.elapsedTime))
                .font(.system(.title3, design: .monospaced, weight: .semibold))

            Button {
                Task {
                    await recordingManager.stopRecording()
                    recordingsStore.refresh()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10))
                    Text("Stop")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(Capsule().fill(.red))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.init("s"), modifiers: [.command, .shift])
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThickMaterial)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        )
    }

    // MARK: - Source Picker Overlay

    private var sourcePickerOverlay: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Choose what to record")
                        .font(.headline)
                    Spacer()
                    Button {
                        withAnimation { showSourcePicker = false }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Divider()

                // Mode picker
                HStack {
                    Picker("Mode", selection: $recordingManager.recordingMode) {
                        ForEach(RecordingManager.RecordingMode.allCases, id: \.self) { mode in
                            Label(mode.rawValue, systemImage: mode == .display ? "display" : "macwindow")
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)

                    Spacer()

                    Button {
                        Task { await recordingManager.refreshAvailableContent() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                // Thumbnail grid
                ScrollView {
                    if recordingManager.recordingMode == .display {
                        displayGrid
                    } else {
                        windowGrid
                    }
                }
                .frame(height: 260)

                Divider()

                // Start button
                HStack {
                    if let error = recordingManager.errorMessage {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    if recordingManager.state == .preparingToRecord {
                        ProgressView()
                            .controlSize(.small)
                        Text("Preparing...")
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            Task {
                                withAnimation { showSourcePicker = false }
                                await recordingManager.startRecording()
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(.white)
                                    .frame(width: 10, height: 10)
                                Text("Start Recording")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(canRecord ? .red : .red.opacity(0.4)))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canRecord)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThickMaterial)
                    .shadow(color: .black.opacity(0.2), radius: 20, y: -4)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { showSourcePicker = false }
                }
        )
    }

    // MARK: - Display Grid

    private var displayGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 14)], spacing: 14) {
            ForEach(recordingManager.availableDisplays, id: \.displayID) { display in
                DisplayThumbnailCard(
                    display: display,
                    thumbnail: recordingManager.displayThumbnails[display.displayID],
                    isSelected: recordingManager.selectedDisplay?.displayID == display.displayID
                )
                .onTapGesture {
                    recordingManager.selectedDisplay = display
                }
            }
        }
        .padding(20)
    }

    // MARK: - Window Grid

    private var windowGrid: some View {
        Group {
            if recordingManager.availableWindows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.quaternary)
                    Text("No windows found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Open some windows and tap Refresh")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)], spacing: 14) {
                    ForEach(recordingManager.availableWindows, id: \.windowID) { window in
                        WindowThumbnailCard(
                            window: window,
                            thumbnail: recordingManager.windowThumbnails[window.windowID],
                            appIcon: recordingManager.appIcon(for: window),
                            isSelected: recordingManager.selectedWindow?.windowID == window.windowID
                        )
                        .onTapGesture {
                            recordingManager.selectedWindow = window
                        }
                    }
                }
                .padding(20)
            }
        }
    }

    private var canRecord: Bool {
        guard recordingManager.state == .idle else { return false }
        if recordingManager.recordingMode == .display {
            return recordingManager.selectedDisplay != nil
        } else {
            return recordingManager.selectedWindow != nil
        }
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Record Button Dot (animated pulsing)

struct RecordButtonDot: View {
    @State private var isPulsing = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.3))
                .frame(width: 20, height: 20)
                .scaleEffect(isPulsing ? 1.4 : 1.0)
                .opacity(isPulsing ? 0.0 : 0.5)

            Circle()
                .fill(.white)
                .frame(width: 12, height: 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Display Thumbnail Card

struct DisplayThumbnailCard: View {
    let display: SCDisplay
    let thumbnail: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.black)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "display")
                        .font(.system(size: 36))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(spacing: 2) {
                Text("Display \(display.displayID)")
                    .font(.caption.weight(.medium))
                Text("\(display.width) x \(display.height)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Window Thumbnail Card

struct WindowThumbnailCard: View {
    let window: SCWindow
    let thumbnail: NSImage?
    let appIcon: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .windowBackgroundColor))

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "macwindow")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.1), radius: 2, y: 1)

            HStack(spacing: 6) {
                if let appIcon {
                    Image(nsImage: appIcon)
                        .resizable()
                        .frame(width: 16, height: 16)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.owningApplication?.applicationName ?? "Unknown")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    if let title = window.title, !title.isEmpty,
                       title != window.owningApplication?.applicationName {
                        Text(title)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2.5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: Recording
    @EnvironmentObject var recordingsStore: RecordingsStore
    @EnvironmentObject var transcriptionManager: TranscriptionManager
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.black)

                if let thumb = recordingsStore.thumbnails[recording.id] {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 68)
                        .clipped()
                } else {
                    Image(systemName: "film")
                        .font(.title3)
                        .foregroundStyle(.white.opacity(0.3))
                }

                if recording.duration > 0 {
                    VStack {
                        Spacer()
                        HStack {
                            Spacer()
                            Text(recording.formattedDuration)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                    .padding(4)
                }
            }
            .frame(width: 120, height: 68)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.filename)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.date, style: .date)
                    Text("·")
                    Text(recording.date, style: .time)
                    Text("·")
                    Text(recording.fileSize)
                    if let state = transcriptionManager.states[recording.id] {
                        Text("·")
                        switch state {
                        case .extractingAudio, .downloadingModels:
                            ProgressView()
                                .controlSize(.mini)
                            Text("Preparing...")
                        case .transcribing:
                            ProgressView()
                                .controlSize(.mini)
                            Text("Transcribing...")
                        case .diarizing:
                            ProgressView()
                                .controlSize(.mini)
                            Text("Identifying speakers...")
                        case .error:
                            Label("Failed", systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.red)
                        default:
                            if recording.hasTranscription {
                                Label("Transcribed", systemImage: "text.alignleft")
                            }
                        }
                    } else if recording.hasTranscription {
                        Text("·")
                        Label("Transcribed", systemImage: "text.alignleft")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    recordingsStore.openRecording(recording)
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                ShareLink(item: recording.videoURL) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .font(.body)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .alert("Delete Recording?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                recordingsStore.deleteRecording(recording)
            }
        } message: {
            Text("Are you sure you want to delete \"\(recording.filename)\"? This cannot be undone.")
        }
    }
}
