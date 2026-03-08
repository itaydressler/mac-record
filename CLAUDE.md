# MacRecord

Native macOS screen recorder with transcription and speaker diarization.

## Build & Run

```bash
xcodegen generate          # Regenerate .xcodeproj from project.yml
xcodebuild -scheme MacRecord -configuration Debug build
# App binary: DerivedData/MacRecord-.../Build/Products/Debug/MacRecord.app
```

No tests. Add new source files to `MacRecord/Sources/` — XcodeGen picks them up automatically from the `sources` glob in `project.yml`.

## Architecture

- **project.yml** — XcodeGen project config. Dependencies, signing, entitlements all live here.
- **MacRecordApp.swift** — Entry point. Creates all `@StateObject` stores and injects them as environment objects.
- **RecordingManager.swift** — ScreenCaptureKit capture + AVAssetWriter. `SampleWriter` handles thread-safe sample writing with pause/resume. `MicrophoneCapture` captures mic via AVAudioEngine with echo cancellation, writes as a second audio track.
- **ContentView.swift** — Main UI. Recordings list, floating record button, source picker overlay, active recording bar.
- **RecordingDetailView.swift** — HSplitView with AVPlayerView (custom NSViewRepresentable) and structured transcript with click-to-seek.
- **RecordingsStore.swift** — File-based recording storage in `~/Documents/MacRecord/`. Each recording is a folder with `recording.mov` + optional `transcript.json`.
- **TranscriptionManager.swift** — Orchestrates: extract audio → ASR (FluidAudio Parakeet) → diarization → speaker matching → ITN → save JSON.
- **TranscriptModels.swift** — `Transcript`, `TranscriptSpeaker`, `TranscriptSegment` Codable structs.
- **SpeakerProfile.swift** — `SpeakerProfile` model + `SpeakerProfileStore`. Stored in `~/Library/Application Support/MacRecord/Speakers/{uuid}/`.
- **SpeakerProfilesView.swift** — Speaker profile management UI with voice enrollment.
- **FloatingToolbar.swift** — NSPanel-based floating toolbar during recording.

## Key Libraries

- **FluidAudio** — On-device ASR (`AsrManager`), speaker diarization (`OfflineDiarizerManager`), streaming ASR (`StreamingEouAsrManager`), text normalization (`TextNormalizer`), speaker embeddings.
- **ScreenCaptureKit** — Screen/window capture with system audio.
- **AVFoundation** — Video writing (AVAssetWriter), playback (AVPlayer), audio extraction (AVAssetExportSession).

## Adding Features

1. UI views go in `MacRecord/Sources/`. Wire new stores in `MacRecordApp.swift` as `@StateObject` + `.environmentObject()`.
2. New data models: add Codable structs, store as JSON in the recording folder or app support.
3. Audio processing: FluidAudio SDK handles ASR, diarization, embeddings. See `TranscriptionManager.swift` for the full pipeline.
4. Recording pipeline: `RecordingManager` → `SampleWriter` handles all sample buffers. Mic audio goes through `MicrophoneCapture` with echo cancellation enabled.
5. After changes, run `xcodegen generate` if you added/removed files, then build.
