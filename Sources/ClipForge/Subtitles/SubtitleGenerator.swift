import AVFoundation
import Foundation
import Speech

// MARK: - Errors

enum SubtitleError: LocalizedError {
    case authorizationDenied
    case recognizerUnavailable(Locale)
    case noAudioTrack
    case audioExtractionFailed(String)
    case transcriptionFailed(String)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition authorization was denied. Please grant permission in System Settings › Privacy & Security › Speech Recognition."
        case .recognizerUnavailable(let locale):
            return "Speech recognizer is not available for language: \(locale.localizedString(forIdentifier: locale.identifier) ?? locale.identifier)."
        case .noAudioTrack:
            return "The video has no audio track to transcribe."
        case .audioExtractionFailed(let reason):
            return "Failed to extract audio: \(reason)"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        }
    }
}

// MARK: - Speech Authorization

/// Bridges SFSpeechRecognizer.requestAuthorization to async/await.
func requestSpeechAuthorization() async -> Bool {
    CFLogInfo("SubtitleGenerator: Requesting speech recognition authorization")
    return await withCheckedContinuation { continuation in
        SFSpeechRecognizer.requestAuthorization { status in
            let authorized = (status == .authorized)
            CFLogInfo("SubtitleGenerator: Authorization status=\(status.rawValue) authorized=\(authorized)")
            continuation.resume(returning: authorized)
        }
    }
}

// MARK: - Audio Extraction

/// Exports the audio track of an AVAsset to a temporary .m4a file.
/// - Returns: URL to the temporary audio file. Caller is responsible for deleting it.
func extractAudio(from asset: AVAsset) async throws -> URL {
    CFLogInfo("SubtitleGenerator: Starting audio extraction")

    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !audioTracks.isEmpty else {
        CFLogError("SubtitleGenerator: No audio track found in asset")
        throw SubtitleError.noAudioTrack
    }
    CFLogDebug("SubtitleGenerator: Found \(audioTracks.count) audio track(s)")

    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("subtitle_audio_\(UUID().uuidString).m4a")
    CFLogDebug("SubtitleGenerator: Audio temp path: \(tempURL.path)")

    guard let exportSession = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetAppleM4A
    ) else {
        CFLogError("SubtitleGenerator: Failed to create AVAssetExportSession")
        throw SubtitleError.audioExtractionFailed("Could not create AVAssetExportSession")
    }

    let assetDuration = try await asset.load(.duration)
    let durationSeconds = CMTimeGetSeconds(assetDuration)
    exportSession.outputURL = tempURL
    exportSession.outputFileType = .m4a
    CFLogInfo("SubtitleGenerator: Exporting \(String(format: "%.1f", durationSeconds))s of audio")

    await exportSession.export()

    switch exportSession.status {
    case .completed:
        CFLogInfo("SubtitleGenerator: Audio extraction complete → \(tempURL.lastPathComponent)")
        return tempURL
    case .failed:
        let reason = exportSession.error?.localizedDescription ?? "unknown"
        CFLogError("SubtitleGenerator: Audio extraction failed: \(reason)")
        throw SubtitleError.audioExtractionFailed(reason)
    case .cancelled:
        CFLogWarn("SubtitleGenerator: Audio extraction was cancelled")
        throw SubtitleError.audioExtractionFailed("Export was cancelled")
    default:
        let reason = "Unexpected status \(exportSession.status.rawValue)"
        CFLogError("SubtitleGenerator: Audio extraction unexpected status: \(reason)")
        throw SubtitleError.audioExtractionFailed(reason)
    }
}

// MARK: - Word Grouping (Legacy Path)

/// Groups word-level `SFTranscriptionSegment`s into subtitle lines.
/// Starts a new line when: silence gap > 0.5 s, or the line would exceed 5 s.
private func groupWordSegments(_ wordSegments: [SFTranscriptionSegment]) -> [SubtitleSegment] {
    CFLogDebug("SubtitleGenerator: Grouping \(wordSegments.count) word segments into subtitle lines")

    var result: [SubtitleSegment] = []
    var currentGroup: [SFTranscriptionSegment] = []

    let maxLineDuration: TimeInterval = 5.0
    let pauseThreshold: TimeInterval = 0.5

    for wordSeg in wordSegments {
        let word = wordSeg.substring.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty else { continue }

        if currentGroup.isEmpty {
            currentGroup.append(wordSeg)
            continue
        }

        let lastWord = currentGroup.last!
        let lastEnd = lastWord.timestamp + lastWord.duration
        let gap = wordSeg.timestamp - lastEnd
        let groupDuration = (wordSeg.timestamp + wordSeg.duration) - currentGroup.first!.timestamp

        if gap > pauseThreshold || groupDuration > maxLineDuration {
            if let subtitle = makeSubtitleFromGroup(currentGroup) {
                result.append(subtitle)
                CFLogDebug("SubtitleGenerator: Line → [\(formatSRTTime(subtitle.start))–\(formatSRTTime(subtitle.end))]: \"\(subtitle.text)\"")
            }
            currentGroup = [wordSeg]
        } else {
            currentGroup.append(wordSeg)
        }
    }

    if !currentGroup.isEmpty, let subtitle = makeSubtitleFromGroup(currentGroup) {
        result.append(subtitle)
    }

    CFLogInfo("SubtitleGenerator: Produced \(result.count) subtitle lines from \(wordSegments.count) words")
    return result
}

private func makeSubtitleFromGroup(_ group: [SFTranscriptionSegment]) -> SubtitleSegment? {
    guard !group.isEmpty else { return nil }
    let start = group.first!.timestamp
    let lastWord = group.last!
    let end = lastWord.timestamp + max(lastWord.duration, 0.1)
    let text = group.map { $0.substring }.joined(separator: " ")
    return SubtitleSegment(start: start, end: end, text: text)
}

// MARK: - Legacy Transcription (macOS 14+ / iOS 17+)

/// Transcribes using the legacy `SFSpeechRecognizer` API with on-device recognition.
func transcribeLegacy(audioURL: URL, locale: Locale) async throws -> [SubtitleSegment] {
    CFLogInfo("SubtitleGenerator: [Legacy] Starting transcription, locale=\(locale.identifier)")

    // Try requested locale, fall back to device locale if unavailable.
    let recognizer: SFSpeechRecognizer
    if let r = SFSpeechRecognizer(locale: locale), r.isAvailable {
        recognizer = r
        CFLogInfo("SubtitleGenerator: [Legacy] Using recognizer for \(locale.identifier)")
    } else if let fallback = SFSpeechRecognizer(), fallback.isAvailable {
        CFLogWarn("SubtitleGenerator: [Legacy] \(locale.identifier) unavailable, falling back to device locale \(fallback.locale.identifier)")
        recognizer = fallback
    } else {
        CFLogError("SubtitleGenerator: [Legacy] No available speech recognizer found")
        throw SubtitleError.recognizerUnavailable(locale)
    }

    return try await transcribeWithRecognizer(recognizer, audioURL: audioURL)
}

private func transcribeWithRecognizer(
    _ recognizer: SFSpeechRecognizer,
    audioURL: URL
) async throws -> [SubtitleSegment] {
    CFLogInfo("SubtitleGenerator: [Legacy] Creating recognition request for \(audioURL.lastPathComponent)")

    let request = SFSpeechURLRecognitionRequest(url: audioURL)
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = false

    if #available(macOS 13.0, iOS 16.0, *) {
        request.addsPunctuation = true
        CFLogDebug("SubtitleGenerator: [Legacy] Punctuation enabled")
    }

    CFLogInfo("SubtitleGenerator: [Legacy] Launching recognition task (on-device, no time limit)")

    return try await withCheckedThrowingContinuation { continuation in
        var resumed = false

        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                guard !resumed else { return }
                resumed = true
                CFLogError("SubtitleGenerator: [Legacy] Recognition error: \(error.localizedDescription)")
                continuation.resume(throwing: SubtitleError.transcriptionFailed(error.localizedDescription))
                return
            }

            guard let result, result.isFinal else {
                CFLogDebug("SubtitleGenerator: [Legacy] Partial result received, waiting for final…")
                return
            }

            guard !resumed else { return }
            resumed = true

            let wordSegs = result.bestTranscription.segments
            CFLogInfo("SubtitleGenerator: [Legacy] Final result: \(wordSegs.count) word segment(s)")
            CFLogDebug("SubtitleGenerator: [Legacy] Raw transcript: \"\(result.bestTranscription.formattedString)\"")

            let subtitles = groupWordSegments(wordSegs)
            continuation.resume(returning: subtitles)
        }

        CFLogDebug("SubtitleGenerator: [Legacy] Recognition task created: \(task)")
    }
}

// MARK: - New SpeechAnalyzer Transcription (macOS 26+ / iOS 26+)

@available(macOS 26.0, iOS 26.0, *)
func transcribeWithSpeechAnalyzer(audioURL: URL, locale: Locale) async throws -> [SubtitleSegment] {
    CFLogInfo("SubtitleGenerator: [SpeechAnalyzer] Starting, locale=\(locale.identifier)")

    // Resolve locale — prefer requested, fall back to device locale.
    let supportedLocales = await SpeechTranscriber.supportedLocales
    let effectiveLocale: Locale
    if supportedLocales.contains(locale) {
        effectiveLocale = locale
        CFLogDebug("SubtitleGenerator: [SpeechAnalyzer] Locale \(locale.identifier) supported (\(supportedLocales.count) locales available)")
    } else {
        effectiveLocale = Locale.current
        CFLogWarn("SubtitleGenerator: [SpeechAnalyzer] Locale \(locale.identifier) not in supported list (\(supportedLocales.count) locales); using device locale \(effectiveLocale.identifier)")
    }

    // Use timeIndexedTranscriptionWithAlternatives for per-result CMTimeRange timing.
    let transcriber = SpeechTranscriber(locale: effectiveLocale, preset: .timeIndexedTranscriptionWithAlternatives)
    let analyzer = SpeechAnalyzer(modules: [transcriber])
    CFLogInfo("SubtitleGenerator: [SpeechAnalyzer] Analyzer created with timeIndexedTranscriptionWithAlternatives preset")

    // Open the audio file for analysis.
    let audioFile = try AVAudioFile(forReading: audioURL)
    CFLogDebug("SubtitleGenerator: [SpeechAnalyzer] Opened audio file: \(audioURL.lastPathComponent), format: \(audioFile.fileFormat)")

    var segments: [SubtitleSegment] = []

    // Run the analyzer as a concurrent child task while consuming results in this task.
    try await withThrowingTaskGroup(of: Void.self) { group in

        // Child task: drive the analyzer (feeds audio frames → produces results into transcriber.results).
        group.addTask {
            CFLogInfo("SubtitleGenerator: [SpeechAnalyzer] Analysis task started")
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                CFLogDebug("SubtitleGenerator: [SpeechAnalyzer] Analysis complete, last sample=\(lastSample.seconds)s")
                try await analyzer.finalizeAndFinish(through: lastSample)
                CFLogInfo("SubtitleGenerator: [SpeechAnalyzer] Finalization complete")
            } else {
                CFLogWarn("SubtitleGenerator: [SpeechAnalyzer] No samples analyzed, cancelling")
                await analyzer.cancelAndFinishNow()
            }
        }

        // Current task: consume results as they stream in from the analyzer.
        CFLogInfo("SubtitleGenerator: [SpeechAnalyzer] Starting result consumption")
        var resultCount = 0
        for try await result in transcriber.results {
            // result.range: CMTimeRange with start and end (= start + duration).
            let range = result.range
            let start = range.start.seconds
            let end   = range.end.seconds
            let text  = String(result.text.characters).trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else {
                CFLogDebug("SubtitleGenerator: [SpeechAnalyzer] Skipping empty result at \(String(format: "%.2f", start))s")
                continue
            }
            resultCount += 1
            CFLogDebug("SubtitleGenerator: [SpeechAnalyzer] Result \(resultCount): [\(formatSRTTime(start))–\(formatSRTTime(end))]: \"\(text)\"")
            segments.append(SubtitleSegment(start: start, end: end, text: text))
        }
        CFLogInfo("SubtitleGenerator: [SpeechAnalyzer] Consumed \(resultCount) result(s)")

        // Propagate any error thrown by the analyzer task.
        try await group.waitForAll()
    }

    CFLogInfo("SubtitleGenerator: [SpeechAnalyzer] Done — \(segments.count) subtitle segment(s)")
    return segments
}

// MARK: - SRT Formatting

/// Formats a time in seconds to SRT timestamp format: `HH:MM:SS,mmm`.
func formatSRTTime(_ seconds: TimeInterval) -> String {
    let totalSeconds = max(0, seconds)
    let h = Int(totalSeconds / 3600)
    let m = Int((totalSeconds.truncatingRemainder(dividingBy: 3600)) / 60)
    let s = totalSeconds.truncatingRemainder(dividingBy: 60)
    // %06.3f → "05.123" (6 chars: 2-digit seconds, dot, 3-digit ms); replace . with ,
    return String(format: "%02d:%02d:%06.3f", h, m, s)
        .replacingOccurrences(of: ".", with: ",")
}

/// Generates an SRT-formatted string from subtitle segments.
func createSRT(from segments: [SubtitleSegment]) -> String {
    CFLogDebug("SubtitleGenerator: Building SRT from \(segments.count) segment(s)")
    var srt = ""
    for (index, seg) in segments.enumerated() {
        srt += "\(index + 1)\n"
        srt += "\(formatSRTTime(seg.start)) --> \(formatSRTTime(seg.end))\n"
        srt += "\(seg.text)\n\n"
    }
    return srt
}

/// Writes SRT content to a temporary file and returns its URL, or nil on failure.
func writeSRTToTemp(segments: [SubtitleSegment], baseName: String = "subtitles") -> URL? {
    let content = createSRT(from: segments)
    let tempURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("\(baseName)_\(UUID().uuidString).srt")
    CFLogInfo("SubtitleGenerator: Writing SRT (\(segments.count) segments) to \(tempURL.lastPathComponent)")
    do {
        try content.write(to: tempURL, atomically: true, encoding: .utf8)
        CFLogInfo("SubtitleGenerator: SRT written successfully")
        return tempURL
    } catch {
        CFLogError("SubtitleGenerator: Failed to write SRT: \(error.localizedDescription)")
        return nil
    }
}
