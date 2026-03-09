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
    @State private var sidebarHoveredId: String?
    @StateObject private var sharedPlayer = VideoPlayerModel()
    @State private var mediaPanelWidth: CGFloat = 340

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar
            sidebar
                .frame(width: 250)

            // Main content with rounded background
            mainContent
                .frame(minWidth: 320)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(SpokeTheme.contentBg)
                        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.vertical, 6)
                .padding(.leading, 4)
                .padding(.trailing, 0)

            // Draggable resize handle
            ResizeDivider(position: $mediaPanelWidth, isLeadingEdge: false)

            // Right media panel with rounded corners
            mediaPanel
                .frame(width: mediaPanelWidth)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(.vertical, 6)
                .padding(.trailing, 6)
        }
        .background(SpokeTheme.sidebarBg)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .sheet(isPresented: $showSpeakerProfiles) {
            SpeakerProfilesView()
                .environmentObject(speakerProfileStore)
                .frame(width: 500, height: 480)
                .onExitCommand { showSpeakerProfiles = false }
        }
        .sheet(isPresented: $showSourcePicker) {
            sourcePickerSheet
        }
        .onChange(of: selectedRecording?.id) { _, newId in
            if let recording = selectedRecording {
                sharedPlayer.load(url: recording.videoURL)
            } else {
                sharedPlayer.pause()
            }
        }
        .onReceive(recordingManager.$state) { newState in
            if newState == .idle {
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

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            // Custom traffic lights + window drag area
            ZStack {
                WindowDragArea()
                HStack(spacing: 8) {
                    TrafficLightButtons()
                    Spacer()
                }
                .padding(.horizontal, 18)
            }
            .frame(height: 42)
            .padding(.top, 2)

            // Nav items
            VStack(spacing: 2) {
                sidebarNavItem(
                    icon: "waveform.circle.fill",
                    label: "All Recordings",
                    color: SpokeTheme.accent,
                    isSelected: true
                )
            }
            .padding(.horizontal, 12)

            sidebarSection("Recordings")

            if recordingManager.state == .recording {
                sidebarRecordingStatus
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)
            }

            if recordingsStore.recordings.isEmpty {
                sidebarEmptyHint
            } else {
                sidebarRecordingsList
            }

            Spacer(minLength: 0)

            Rectangle()
                .fill(SpokeTheme.divider)
                .frame(height: 1)

            // Bottom bar
            HStack(spacing: 12) {
                Button {
                    Task { await recordingManager.refreshAvailableContent() }
                    showSourcePicker = true
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(SpokeTheme.windowBg)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(SpokeTheme.border, lineWidth: 1)
                            )
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(SpokeTheme.textSecondary)
                    }
                    .frame(width: 42, height: 42)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.init("r"), modifiers: [.command, .shift])

                Spacer()

                Button {
                    showSpeakerProfiles = true
                } label: {
                    ZStack {
                        Circle()
                            .fill(SpokeTheme.accent.opacity(0.12))
                            .frame(width: 36, height: 36)
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(SpokeTheme.accent)
                    }
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(SpokeTheme.sidebarBg)
    }

    private func sidebarNavItem(icon: String, label: String, color: Color, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(color)
                .frame(width: 22)
            Text(label)
                .font(.system(size: 14, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(SpokeTheme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? SpokeTheme.sidebarSelected : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SpokeTheme.sidebarSelectedBar)
                    .frame(width: 3, height: 18)
                    .offset(x: -1)
            }
        }
    }

    private func sidebarSection(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SpokeTheme.textTertiary)
            Spacer()
            Button { recordingsStore.openRecordingsFolder() } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .foregroundStyle(SpokeTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 6)
    }

    private var sidebarRecordingStatus: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(SpokeTheme.recording)
                .frame(width: 7, height: 7)
            Text(formatTime(recordingManager.elapsedTime))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpokeTheme.recording)
            Spacer()
            Button {
                Task {
                    await recordingManager.stopRecording()
                    recordingsStore.refresh()
                }
            } label: {
                Text("Stop")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(SpokeTheme.recording))
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.init("s"), modifiers: [.command, .shift])
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SpokeTheme.recording.opacity(0.08))
        )
    }

    private var sidebarEmptyHint: some View {
        VStack(spacing: 6) {
            VStack(spacing: 8) {
                placeholderLine(width: 140)
                placeholderLine(width: 110)
                placeholderLine(width: 125)
            }
            .padding(.top, 8)
            Text("No recordings yet")
                .font(.system(size: 12))
                .foregroundStyle(SpokeTheme.textTertiary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private func placeholderLine(width: CGFloat) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(SpokeTheme.divider)
                .frame(width: 18, height: 18)
            WavyLine()
                .stroke(SpokeTheme.textTertiary.opacity(0.25), lineWidth: 2)
                .frame(width: width, height: 8)
        }
        .padding(.horizontal, 22)
    }

    // MARK: - Sidebar Recordings List

    private var sidebarRecordingsList: some View {
        ScrollView {
            LazyVStack(spacing: 1) {
                ForEach(recordingsStore.recordings) { recording in
                    SidebarRecordingRow(
                        recording: recording,
                        thumbnail: recordingsStore.thumbnails[recording.id],
                        isSelected: selectedRecording?.id == recording.id,
                        isHovered: sidebarHoveredId == recording.id,
                        transcriptionState: transcriptionManager.states[recording.id]
                    )
                    .onTapGesture {
                        if selectedRecording?.id == recording.id {
                            selectedRecording = nil
                        } else {
                            selectedRecording = recording
                        }
                    }
                    .onHover { hovering in
                        sidebarHoveredId = hovering ? recording.id : nil
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
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
    }

    // MARK: - Main Content

    @ViewBuilder
    private var mainContent: some View {
        if let recording = selectedRecording {
            RecordingDetailView(recording: recording, playerModel: sharedPlayer)
                .id(recording.id)
        } else {
            welcomeContent
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 0) {
            WindowDragArea()
                .frame(height: 20)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Spoke")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(SpokeTheme.textPrimary)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 8)

                    Text("Record meetings locally, transcribe with AI, connect to agents.")
                        .font(.system(size: 15))
                        .foregroundStyle(SpokeTheme.textSecondary)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 28)

                    VStack(spacing: 12) {
                        featureCard(
                            icon: "lock.shield.fill", iconColor: SpokeTheme.success,
                            title: "100% Local & Private",
                            subtitle: "All processing happens on your Mac. Nothing leaves your device."
                        )
                        featureCard(
                            icon: "cpu.fill", iconColor: SpokeTheme.accent,
                            title: "AI Transcription",
                            subtitle: "On-device speech recognition with speaker identification."
                        )
                        featureCard(
                            icon: "puzzlepiece.extension.fill",
                            iconColor: Color(red: 0.957, green: 0.588, blue: 0.086),
                            title: "AI Agent Ready",
                            subtitle: "Connect your recordings to Claude and other AI agents via MCP."
                        )
                        featureCard(
                            icon: "curlybraces", iconColor: SpokeTheme.textSecondary,
                            title: "Open Source",
                            subtitle: "Free forever. Extend and customize to your needs."
                        )
                    }
                    .padding(.horizontal, 24)

                    HStack(spacing: 12) {
                        Button {
                            Task { await recordingManager.refreshAvailableContent() }
                            showSourcePicker = true
                        } label: {
                            HStack(spacing: 6) {
                                Circle().fill(SpokeTheme.recording).frame(width: 8, height: 8)
                                Text("New Recording")
                            }
                        }
                        .buttonStyle(SpokeAccentButtonStyle())

                        Button {
                            showSpeakerProfiles = true
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "person.2")
                                Text("Speakers")
                            }
                        }
                        .buttonStyle(SpokeGhostButtonStyle())
                    }
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                }
                .padding(.top, 8)
            }
        }
        .background(SpokeTheme.contentBg)
    }

    private func featureCard(icon: String, iconColor: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(iconColor)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 8).fill(iconColor.opacity(0.10)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(SpokeTheme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(SpokeTheme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SpokeTheme.cardBg)
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(SpokeTheme.cardBorder, lineWidth: 1))
        )
    }

    // MARK: - Right Media Panel

    private var mediaPanel: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.180, green: 0.157, blue: 0.282),
                    Color(red: 0.102, green: 0.090, blue: 0.200),
                    Color(red: 0.063, green: 0.067, blue: 0.145),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if selectedRecording != nil {
                PlayerView(player: sharedPlayer.player)
            } else {
                decorativePlaceholder
            }
        }
    }

    private var decorativePlaceholder: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .strokeBorder(Color.white.opacity(0.04 + Double(i) * 0.02), lineWidth: 1)
                        .frame(width: CGFloat(60 + i * 50), height: CGFloat(60 + i * 50))
                }
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(
                        .linearGradient(
                            colors: [SpokeTheme.accent.opacity(0.8), SpokeTheme.accent.opacity(0.4)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("Select a recording")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Video will appear here")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.35))
            }

            Spacer()
            Spacer()
        }
    }

    // MARK: - Source Picker Sheet

    private var sourcePickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Choose what to record")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SpokeTheme.textPrimary)
                Spacer()
                Button { showSourcePicker = false } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(SpokeTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 14)

            Rectangle().fill(SpokeTheme.divider).frame(height: 1)

            HStack {
                Picker("Mode", selection: $recordingManager.recordingMode) {
                    ForEach(RecordingManager.RecordingMode.allCases, id: \.self) { mode in
                        Label(mode.rawValue, systemImage: mode == .display ? "display" : "macwindow").tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                Spacer()
                Button {
                    Task { await recordingManager.refreshAvailableContent() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13))
                        .foregroundStyle(SpokeTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Rectangle().fill(SpokeTheme.divider).frame(height: 1)

            ScrollView {
                if recordingManager.recordingMode == .display { displayGrid }
                else { windowGrid }
            }
            .frame(height: 280)

            Rectangle().fill(SpokeTheme.divider).frame(height: 1)

            HStack {
                if let error = recordingManager.errorMessage {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(SpokeTheme.warning)
                    Text(error).font(.system(size: 12)).foregroundStyle(SpokeTheme.textSecondary).lineLimit(1)
                }
                Spacer()
                if recordingManager.state == .preparingToRecord {
                    ProgressView().controlSize(.small)
                    Text("Preparing...").foregroundStyle(SpokeTheme.textSecondary)
                } else {
                    Button("Cancel") { showSourcePicker = false }.buttonStyle(SpokeGhostButtonStyle())
                    Button {
                        Task { showSourcePicker = false; await recordingManager.startRecording() }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(.white).frame(width: 7, height: 7)
                            Text("Start Recording")
                        }
                    }
                    .buttonStyle(SpokeRecordButtonStyle())
                    .disabled(!canRecord).opacity(canRecord ? 1 : 0.5)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(SpokeTheme.contentBg)
        .frame(width: 600, height: 480)
    }

    private var displayGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240, maximum: 340), spacing: 14)], spacing: 14) {
            ForEach(recordingManager.availableDisplays, id: \.displayID) { display in
                DisplayThumbnailCard(
                    display: display,
                    thumbnail: recordingManager.displayThumbnails[display.displayID],
                    isSelected: recordingManager.selectedDisplay?.displayID == display.displayID
                )
                .onTapGesture { recordingManager.selectedDisplay = display }
            }
        }
        .padding(20)
    }

    private var windowGrid: some View {
        Group {
            if recordingManager.availableWindows.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "macwindow.on.rectangle").font(.system(size: 32)).foregroundStyle(SpokeTheme.textTertiary)
                    Text("No windows found").font(.system(size: 14)).foregroundStyle(SpokeTheme.textSecondary)
                    Text("Open some windows and tap Refresh").font(.system(size: 12)).foregroundStyle(SpokeTheme.textTertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.top, 40)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 14)], spacing: 14) {
                    ForEach(recordingManager.availableWindows, id: \.windowID) { window in
                        WindowThumbnailCard(
                            window: window,
                            thumbnail: recordingManager.windowThumbnails[window.windowID],
                            appIcon: recordingManager.appIcon(for: window),
                            isSelected: recordingManager.selectedWindow?.windowID == window.windowID
                        )
                        .onTapGesture { recordingManager.selectedWindow = window }
                    }
                }
                .padding(20)
            }
        }
    }

    private var canRecord: Bool {
        guard recordingManager.state == .idle else { return false }
        return recordingManager.recordingMode == .display
            ? recordingManager.selectedDisplay != nil
            : recordingManager.selectedWindow != nil
    }

    private func formatTime(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, seconds) }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Window Drag Area

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggableView {
        DraggableView()
    }
    func updateNSView(_ nsView: DraggableView, context: Context) {}

    class DraggableView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

// MARK: - Resize Divider

struct ResizeDivider: View {
    @Binding var position: CGFloat
    let isLeadingEdge: Bool
    let minSize: CGFloat = 220
    let maxSize: CGFloat = 600
    @State private var isDragging = false
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() }
                else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            dragStartWidth = position
                        }
                        // Dragging left => right panel grows; dragging right => shrinks
                        let delta = -value.translation.width
                        let newWidth = dragStartWidth + delta
                        position = min(max(newWidth, minSize), maxSize)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 1)
                    .fill(isDragging ? SpokeTheme.accent.opacity(0.5) : SpokeTheme.divider)
                    .frame(width: isDragging ? 2 : 1)
            )
    }
}

// MARK: - Custom Traffic Light Buttons

struct TrafficLightButtons: View {
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            trafficButton(color: Color(red: 1.0, green: 0.38, blue: 0.36), hoverIcon: "xmark") {
                NSApp.keyWindow?.close()
            }
            trafficButton(color: Color(red: 1.0, green: 0.74, blue: 0.21), hoverIcon: "minus") {
                NSApp.keyWindow?.miniaturize(nil)
            }
            trafficButton(color: Color(red: 0.30, green: 0.85, blue: 0.39), hoverIcon: "arrow.up.left.and.arrow.down.right") {
                NSApp.keyWindow?.zoom(nil)
            }
        }
        .onHover { isHovering = $0 }
    }

    private func trafficButton(color: Color, hoverIcon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: 12, height: 12)

                if isHovering {
                    Image(systemName: hoverIcon)
                        .font(.system(size: 6.5, weight: .bold))
                        .foregroundStyle(.black.opacity(0.5))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Wavy Line Shape

struct WavyLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        let amplitude: CGFloat = 3
        let wavelength: CGFloat = 16
        path.move(to: CGPoint(x: 0, y: midY))
        var x: CGFloat = 0
        while x < rect.width {
            let y = midY + sin(x / wavelength * .pi * 2) * amplitude
            path.addLine(to: CGPoint(x: x, y: y))
            x += 1
        }
        return path
    }
}

// MARK: - Sidebar Recording Row

struct SidebarRecordingRow: View {
    let recording: Recording
    let thumbnail: NSImage?
    let isSelected: Bool
    let isHovered: Bool
    let transcriptionState: TranscriptionState?

    var body: some View {
        HStack(spacing: 10) {
            // Thumbnail preview
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black)

                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 40, height: 28)
                        .clipped()
                } else {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .frame(width: 40, height: 28)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(recording.filename)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(SpokeTheme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(recording.date, format: .dateTime.month(.abbreviated).day())
                    Text("·")
                    Text(recording.formattedDuration)

                    if let state = transcriptionState {
                        switch state {
                        case .extractingAudio, .downloadingModels, .transcribing, .diarizing:
                            ProgressView().controlSize(.mini)
                        case .error:
                            Image(systemName: "exclamationmark.circle").foregroundStyle(SpokeTheme.recording)
                        default:
                            if recording.hasTranscription {
                                Image(systemName: "text.alignleft").foregroundStyle(SpokeTheme.success)
                            }
                        }
                    } else if recording.hasTranscription {
                        Image(systemName: "text.alignleft").foregroundStyle(SpokeTheme.success)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(SpokeTheme.textTertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? SpokeTheme.sidebarSelected : (isHovered ? SpokeTheme.sidebarHover : Color.clear))
        )
        .overlay(alignment: .leading) {
            if isSelected {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(SpokeTheme.sidebarSelectedBar)
                    .frame(width: 3, height: 16)
                    .offset(x: -2)
            }
        }
        .contentShape(Rectangle())
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
                RoundedRectangle(cornerRadius: 8).fill(Color.black)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "display").font(.system(size: 36)).foregroundStyle(.white.opacity(0.3))
                }
            }
            .aspectRatio(16/10, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(spacing: 2) {
                Text("Display \(display.displayID)").font(.system(size: 12, weight: .medium)).foregroundStyle(SpokeTheme.textPrimary)
                Text("\(display.width) x \(display.height)").font(.system(size: 11)).foregroundStyle(SpokeTheme.textTertiary)
            }
            .padding(.top, 8)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? SpokeTheme.accentLight : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? SpokeTheme.accent : SpokeTheme.border, lineWidth: isSelected ? 2 : 1))
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
                RoundedRectangle(cornerRadius: 8).fill(SpokeTheme.cardBg)
                if let thumbnail {
                    Image(nsImage: thumbnail).resizable().aspectRatio(contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "macwindow").font(.system(size: 32)).foregroundStyle(SpokeTheme.textTertiary)
                }
            }
            .aspectRatio(16/10, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 6) {
                if let appIcon { Image(nsImage: appIcon).resizable().frame(width: 16, height: 16) }
                VStack(alignment: .leading, spacing: 1) {
                    Text(window.owningApplication?.applicationName ?? "Unknown").font(.system(size: 12, weight: .medium)).foregroundStyle(SpokeTheme.textPrimary).lineLimit(1)
                    if let title = window.title, !title.isEmpty, title != window.owningApplication?.applicationName {
                        Text(title).font(.system(size: 11)).foregroundStyle(SpokeTheme.textTertiary).lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(isSelected ? SpokeTheme.accentLight : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(isSelected ? SpokeTheme.accent : SpokeTheme.border, lineWidth: isSelected ? 2 : 1))
        .contentShape(Rectangle())
    }
}

// MARK: - Record Button Dot

struct RecordButtonDot: View {
    @State private var isPulsing = false
    var body: some View {
        ZStack {
            Circle().fill(SpokeTheme.recording.opacity(0.3)).frame(width: 20, height: 20)
                .scaleEffect(isPulsing ? 1.4 : 1.0).opacity(isPulsing ? 0.0 : 0.5)
            Circle().fill(SpokeTheme.recording).frame(width: 12, height: 12)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: false)) { isPulsing = true }
        }
    }
}
