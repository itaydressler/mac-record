# Spoke (formerly MacRecord)

Local-first meeting recorder with AI transcription, speaker diarization, and AI agent integration.

## Build & Run

```bash
xcodegen generate          # Regenerate .xcodeproj from project.yml
xcodebuild -scheme MacRecord -configuration Debug build
# App binary: DerivedData/MacRecord-.../Build/Products/Debug/MacRecord.app
```

No tests. Add new source files to `MacRecord/Sources/` — XcodeGen picks them up automatically from the `sources` glob in `project.yml`.

## Architecture

- **project.yml** — XcodeGen project config. Dependencies, signing, entitlements all live here.
- **MacRecordApp.swift** — Entry point. Creates all `@StateObject` stores and injects them as environment objects. Forces dark mode.
- **AppTheme.swift** — `SpokeTheme` color palette and custom button styles. Superlist-inspired dark navy theme with purple accents.
- **ContentView.swift** — Main UI. HSplitView sidebar (recordings list) + detail area. Source picker as sheet.
- **RecordingDetailView.swift** — HSplitView with AVPlayerView and structured transcript with click-to-seek.
- **RecordingsStore.swift** — File-based recording storage in `~/Documents/MacRecord/`. Each recording is a folder with `recording.mov` + optional `transcript.json`.
- **RecordingManager.swift** — ScreenCaptureKit capture + AVAssetWriter. `SampleWriter` handles thread-safe sample writing with pause/resume. `MicrophoneCapture` captures mic via AVAudioEngine with echo cancellation, writes as a second audio track.
- **TranscriptionManager.swift** — Orchestrates: extract audio → ASR (FluidAudio Parakeet) → diarization → speaker matching → ITN → save JSON.
- **TranscriptModels.swift** — `Transcript`, `TranscriptSpeaker`, `TranscriptSegment` Codable structs.
- **SpeakerProfile.swift** — `SpeakerProfile` model + `SpeakerProfileStore`. Stored in `~/Library/Application Support/MacRecord/Speakers/{uuid}/`.
- **SpeakerProfilesView.swift** — Speaker profile management UI with voice enrollment.
- **FloatingToolbar.swift** — NSPanel-based floating toolbar during recording.

## Design System

All colors and styles are in `AppTheme.swift` via `SpokeTheme`. Dark navy backgrounds, purple accents, muted text hierarchy. Button styles: `SpokeAccentButtonStyle`, `SpokeRecordButtonStyle`, `SpokeGhostButtonStyle`.

## Key Libraries

- **FluidAudio** — On-device ASR (`AsrManager`), speaker diarization (`OfflineDiarizerManager`), streaming ASR (`StreamingEouAsrManager`), text normalization (`TextNormalizer`), speaker embeddings.
- **ScreenCaptureKit** — Screen/window capture with system audio.
- **AVFoundation** — Video writing (AVAssetWriter), playback (AVPlayer), audio extraction (AVAssetExportSession).

## Adding Features

1. UI views go in `MacRecord/Sources/`. Wire new stores in `MacRecordApp.swift` as `@StateObject` + `.environmentObject()`.
2. Use `SpokeTheme` colors and button styles for consistency.
3. New data models: add Codable structs, store as JSON in the recording folder or app support.
4. Audio processing: FluidAudio SDK handles ASR, diarization, embeddings. See `TranscriptionManager.swift` for the full pipeline.
5. Recording pipeline: `RecordingManager` → `SampleWriter` handles all sample buffers. Mic audio goes through `MicrophoneCapture` with echo cancellation enabled.
6. After changes, run `xcodegen generate` if you added/removed files, then build.
