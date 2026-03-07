**Technical Document: Implementation Plan for On-Device Subtitle Generation Feature in Swift Video Editor**

**Version:** 1.0  
**Date:** March 2026  
**Target Platforms:** iOS 19+ / macOS 15+ (SpeechAnalyzer requires the post-WWDC 2025 Speech framework enhancements; iOS/macOS 26+ for full offlineTranscription preset in examples)  
**Primary Frameworks:** AVFoundation + Speech (on-device machine learning models via Apple Intelligence / offline models)  

### 1. Overview & Requirements
This feature extends an existing Swift video editor (that already loads MP4 files via `AVAsset` or `AVPlayerItem`) with:

- Audio extraction from the MP4.
- On-device speech-to-text transcription using Apple’s native machine-learning models (no cloud, no network, unlimited duration, no daily limits).
- Timed subtitle generation (segments with precise start/end timestamps).
- Two outputs:
  - Burned-in subtitles on the exported video (hard subs for universal playback).
  - Separate downloadable `.srt` file.
- Fully native Apple APIs — no third-party libraries (e.g., no FFmpeg).

**Key Advantages of Apple’s On-Device Models (2026)**
- Powered by SpeechAnalyzer + SpeechTranscriber (offline preset).
- Uses locally installed on-device ML models (automatically downloaded on first use via Asset Inventory).
- Time-coded results (each transcription segment includes exact audio timeline range).
- Supports volatile (real-time rough) + finalized results for high accuracy on long videos.
- Privacy-first, battery-efficient, works offline.

**Permissions Required**
- Speech recognition authorization (one-time user prompt; no microphone permission needed for file-based transcription).

### 2. High-Level Architecture
```
Video URL (MP4)
    ↓
AVAsset → Extract Audio Track (AVAssetExportSession → temp .m4a)
    ↓
SpeechAnalyzer + SpeechTranscriber(.offlineTranscription)
    ↓
AsyncSequence of timed results → [SubtitleSegment] (start, end, text)
    ↓
├── Generate .srt file (download/share)
└── Burn-in via AVMutableVideoComposition → Export new MP4 (AVAssetExportSession)
```

### 3. Detailed Implementation Steps

#### 3.1 Load Video (existing feature assumption)
```swift
let asset = AVAsset(url: videoURL)
guard asset.isPlayable, !asset.tracks(withMediaType: .video).isEmpty else { ... }
```

#### 3.2 Extract Audio Track
```swift
func extractAudio(from asset: AVAsset) async throws -> URL {
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString + ".m4a")
    
    guard let exportSession = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetAppleM4A
    ) else { throw ... }
    
    exportSession.outputURL = tempURL
    exportSession.outputFileType = .m4a
    exportSession.timeRange = CMTimeRange(start: .zero, duration: asset.duration)
    
    await exportSession.export()
    guard exportSession.status == .completed else { throw exportSession.error! }
    return tempURL
}
```
(Alternative: `AVAssetReader` + `AVAudioPCMBuffer` stream for zero-disk usage if memory allows.)

#### 3.3 Generate Timed Subtitles (On-Device ML)
Use the modern **SpeechAnalyzer** + **SpeechTranscriber** (WWDC 2025 API).

```swift
import Speech

struct SubtitleSegment: Codable {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

func generateSubtitles(from audioURL: URL, locale: Locale = .current) async throws -> [SubtitleSegment] {
    // 1. Request authorization (once per app)
    let status = await SFSpeechRecognizer.requestAuthorization() // or equivalent for new API
    guard status == .authorized else { throw ... }
    
    // 2. Create offline on-device transcriber
    let transcriber = SpeechTranscriber(
        locale: locale,
        preset: .offlineTranscription  // forces Apple on-device ML models
    )
    
    // 3. Collect timed results asynchronously
    async let transcriptionTask = transcriber.results.reduce(into: [SubtitleSegment]()) { segments, result in
        // result contains .text (AttributedString) and audio timeline range
        let range = result.timeRange // CMTimeRange or equivalent
        segments.append(SubtitleSegment(
            start: range.start.seconds,
            end: range.end.seconds,
            text: String(result.text.characters)
        ))
    }
    
    // 4. Analyzer processes the file (time-coded input)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    if let lastSample = try await analyzer.analyzeSequence(from: audioURL) {
        try await analyzer.finalizeAndFinish(through: lastSample)
    } else {
        await analyzer.cancelAndFinishNow()
    }
    
    return try await transcriptionTask
}
```
- Results are delivered in sequence with non-overlapping audio ranges.
- Volatile results (optional via reportingOptions) give early feedback; final results are high-accuracy.
- Handles hours-long videos (no 1-minute limit on-device).

#### 3.4 Create & Download Separate .srt File
```swift
func createSRT(segments: [SubtitleSegment]) -> URL {
    var srt = ""
    for (index, seg) in segments.enumerated() {
        let startStr = formatSRTTime(seg.start)
        let endStr = formatSRTTime(seg.end)
        srt += "\(index + 1)\n\(startStr) --> \(endStr)\n\(seg.text)\n\n"
    }
    
    let srtURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("subtitles_\(UUID().uuidString).srt")
    try? srt.write(to: srtURL, atomically: true, encoding: .utf8)
    return srtURL
}

private func formatSRTTime(_ seconds: TimeInterval) -> String {
    let h = Int(seconds / 3600)
    let m = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
    let s = seconds.truncatingRemainder(dividingBy: 60)
    return String(format: "%02d:%02d:%06.3f", h, m, s)
}
```
Expose via `UIDocumentInteractionController`, `ShareLink`, or Files app.

#### 3.5 Add Subtitles to Video (Burn-In)
Use `AVMutableVideoComposition` + custom compositor (or multiple instructions) to overlay text at the exact timestamps.

High-level steps:
1. Create `AVMutableVideoComposition` from original asset.
2. Implement `AVVideoCompositing` protocol (or use built-in layer instructions).
3. In the compositor’s `render` method, check current frame time against subtitle segments and draw `NSAttributedString` / `CATextLayer` onto the pixel buffer using Core Graphics / TextKit.
4. Attach: `exportSession.videoComposition = videoComposition`

(Full custom compositor example is ~100 lines; see Apple’s “Bringing advanced speech-to-text” sample code + AVVideoCompositing docs. Burn-in ensures subtitles appear on every player.)

Alternative (softer but more complex): Add `.subtitle` track to `AVMutableComposition` + `AVAssetWriter` with `CMTextSampleBuffer`. Not recommended for broad compatibility.

#### 3.6 Export Final Video
```swift
let composition = AVMutableComposition()
let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality)
exportSession?.videoComposition = videoCompositionWithSubtitles
exportSession?.outputURL = finalVideoURL
exportSession?.outputFileType = .mp4
await exportSession?.export()
```

### 4. Performance, Error Handling & Edge Cases
- **On-device only**: Zero network, unlimited length, model caching after first use.
- **Progress UI**: Wrap in `Task` + `@Published` properties; update every few seconds from `results` stream.
- **Languages**: Check `SpeechTranscriber.supportedLocales`; fallback to device locale.
- **Errors**: Handle `SpeechAnalyzer` cancellation, unsupported locale, export failures, low disk space.
- **Memory**: For very long videos, stream audio in chunks via `AVAssetReader` + `analyzeSequence`.
- **Custom vocabulary**: Pass `transcriptionOptions` or language model boosts (WWDC 2023+ style).
- **Minimum OS fallback**: On older devices use legacy `SFSpeechURLRecognitionRequest` + `requiresOnDeviceRecognition = true`.

### 5. Integration into Existing Video Editor
- Add a “Generate Subtitles” button after video loads.
- Show progress sheet: “Extracting audio… → Transcribing (on-device)… → Rendering subtitles…”
- Final screen: “Video with subtitles ready” + “Download .srt” button.
- Clean up temp files in `deinit` or on completion.
