import SwiftUI
import ScreenCaptureKit

struct ContentView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var recordingsStore: RecordingsStore
    @State private var selectedTab: Tab = .record

    enum Tab: String, CaseIterable {
        case record = "Record"
        case recordings = "Recordings"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            headerBar
            Divider()

            // Content
            Group {
                switch selectedTab {
                case .record:
                    RecordingView()
                case .recordings:
                    RecordingsListView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environmentObject(recordingManager)
        .environmentObject(recordingsStore)
    }

    private var headerBar: some View {
        HStack {
            Picker("", selection: $selectedTab) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

            Spacer()

            if recordingManager.state == .recording {
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text(formatTime(recordingManager.elapsedTime))
                        .font(.system(.body, design: .monospaced, weight: .medium))
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
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

// MARK: - Recording View (Source Picker + Controls)

struct RecordingView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var recordingsStore: RecordingsStore

    var body: some View {
        VStack(spacing: 0) {
            if recordingManager.state == .recording {
                activeRecordingView
            } else {
                sourcePickerView
            }
        }
    }

    // MARK: - Active Recording

    private var activeRecordingView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 16) {
                Image(systemName: "record.circle")
                    .font(.system(size: 64))
                    .foregroundStyle(.red)
                    .symbolEffect(.pulse, isActive: true)

                Text(formatTime(recordingManager.elapsedTime))
                    .font(.system(.largeTitle, design: .monospaced, weight: .bold))

                Text("Recording in progress")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    await recordingManager.stopRecording()
                    recordingsStore.refresh()
                }
            } label: {
                Label("Stop Recording", systemImage: "stop.circle.fill")
                    .font(.title3.weight(.semibold))
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut(.init("s"), modifiers: [.command, .shift])

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Source Picker

    private var sourcePickerView: some View {
        VStack(spacing: 0) {
            // Mode picker
            HStack {
                Picker("Mode", selection: $recordingManager.recordingMode) {
                    ForEach(RecordingManager.RecordingMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode == .display ? "display" : "macwindow")
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)

                Spacer()

                Button {
                    Task { await recordingManager.refreshAvailableContent() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(recordingManager.state != .idle)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)

            Divider()

            // Thumbnail grid
            ScrollView {
                if recordingManager.recordingMode == .display {
                    displayGrid
                } else {
                    windowGrid
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Bottom bar with record button
            bottomBar
        }
    }

    // MARK: - Display Grid

    private var displayGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260, maximum: 360), spacing: 16)], spacing: 16) {
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
        .padding(24)
    }

    // MARK: - Window Grid

    private var windowGrid: some View {
        Group {
            if recordingManager.availableWindows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 40))
                        .foregroundStyle(.quaternary)
                    Text("No windows found")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text("Open some windows and tap Refresh")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.top, 80)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 16)], spacing: 16) {
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
                .padding(24)
            }
        }
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
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
                Text("Preparing…")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    Task { await recordingManager.startRecording() }
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!canRecord)
                .keyboardShortcut(.init("r"), modifiers: [.command, .shift])
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(.bar)
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

// MARK: - Display Thumbnail Card

struct DisplayThumbnailCard: View {
    let display: SCDisplay
    let thumbnail: NSImage?
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Thumbnail
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

            // Label
            VStack(spacing: 2) {
                Text("Display \(display.displayID)")
                    .font(.caption.weight(.medium))
                Text("\(display.width) × \(display.height)")
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
            // Thumbnail
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

            // Label with app icon
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

// MARK: - Recordings List

struct RecordingsListView: View {
    @EnvironmentObject var recordingsStore: RecordingsStore

    var body: some View {
        Group {
            if recordingsStore.recordings.isEmpty {
                emptyState
            } else {
                recordingsList
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.system(size: 48))
                .foregroundStyle(.quaternary)
            Text("No Recordings Yet")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text("Start a recording to see it here.")
                .font(.body)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recordingsList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(recordingsStore.recordings.count) recording\(recordingsStore.recordings.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    recordingsStore.openRecordingsFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(.bar)

            Divider()

            List {
                ForEach(recordingsStore.recordings) { recording in
                    RecordingRow(recording: recording)
                        .contextMenu {
                            Button("Open") { recordingsStore.openRecording(recording) }
                            Button("Reveal in Finder") { recordingsStore.revealInFinder(recording) }
                            Divider()
                            Button("Delete", role: .destructive) { recordingsStore.deleteRecording(recording) }
                        }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    let recording: Recording
    @EnvironmentObject var recordingsStore: RecordingsStore
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 14) {
            // Video thumbnail
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

                // Duration badge
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
        .onTapGesture(count: 2) {
            recordingsStore.openRecording(recording)
        }
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
