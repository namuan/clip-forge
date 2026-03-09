import AVFoundation
import CoreGraphics
import CoreText
import QuartzCore
import Foundation

// MARK: - Zoom transform helpers

/// Builds the in-frame zoom transform for a given scale and focus center.
private func zoomTransform(
    scale: CGFloat,
    center: CGPoint,
    videoSize: CGSize
) -> CGAffineTransform {
    // Match preview semantics:
    // - scale around frame center
    // - then offset by (0.5 - center) * (scale - 1) * size
    // Combined affine translation simplifies to center * (1 - scale) * size.
    let tx = videoSize.width  * center.x * (1 - scale)
    let ty = videoSize.height * center.y * (1 - scale)
    return CGAffineTransform(scaleX: scale, y: scale)
        .concatenating(CGAffineTransform(translationX: tx, y: ty))
}

/// Evaluates the transform at `time` using the segment model, matching ViewModel exactly.
private func segmentZoomTransform(
    at time: Double,
    segments: [ZoomSegment],        // enabled segments, sorted by startTime
    videoSize: CGSize,
    paddingX: CGFloat, paddingY: CGFloat,
    preferredTransform: CGAffineTransform
) -> CGAffineTransform {
    let base = preferredTransform
        .concatenating(CGAffineTransform(translationX: paddingX, y: paddingY))

    guard let seg = segments.first(where: { time >= $0.startTime && time <= $0.endTime })
    else { return base }

    let (scale, center) = seg.interpolated(localT: time - seg.startTime)
    let zoom = zoomTransform(scale: scale, center: center, videoSize: videoSize)
    return base.concatenating(zoom)
}

/// Samples the eased zoom curve at `fps` and writes one linear ramp per frame,
/// so the exported curve exactly matches the live preview's smoothstep easing.
private func applyEasedZoomRamps(
    to instruction: AVMutableVideoCompositionLayerInstruction,
    segments: [ZoomSegment],
    exportDuration: Double,
    videoSize: CGSize,
    paddingX: CGFloat, paddingY: CGFloat,
    preferredTransform: CGAffineTransform,
    fps: Double = 30
) {
    let enabled = segments.filter { $0.isEnabled }.sorted { $0.startTime < $1.startTime }
    let base = preferredTransform
        .concatenating(CGAffineTransform(translationX: paddingX, y: paddingY))
    let rampTimescale: CMTimeScale = 6000

    guard !enabled.isEmpty else {
        instruction.setTransform(base, at: .zero)
        return
    }

    let step = 1.0 / fps
    let count = Int(ceil(exportDuration / step))
    let transformAtTime: (Double) -> CGAffineTransform = { t in
        segmentZoomTransform(
            at: t,
            segments: enabled,
            videoSize: videoSize,
            paddingX: paddingX,
            paddingY: paddingY,
            preferredTransform: preferredTransform
        )
    }

    for i in 0...count {
        let t = min(Double(i) * step, exportDuration)
        let endTransform = transformAtTime(t)
        let endTime = CMTime(seconds: t, preferredTimescale: rampTimescale)

        if i == 0 {
            instruction.setTransform(endTransform, at: endTime)
        } else {
            let prev = min(Double(i - 1) * step, exportDuration)
            let startTransform = transformAtTime(prev)
            let startTime = CMTime(seconds: prev, preferredTimescale: rampTimescale)
            let range = CMTimeRange(start: startTime, end: endTime)
            instruction.setTransformRamp(fromStart: startTransform, toEnd: endTransform, timeRange: range)
        }
    }
}

/// Creates a robust timeline opacity animation for export overlays.
/// Uses the full export timeline to avoid beginTime drift across layer trees.
private func makeVisibilityOpacityAnimation(
    startTime: Double,
    duration: Double,
    totalDuration: Double
) -> CAKeyframeAnimation {
    let minimumTimelineDuration = 0.001
    let maximumFadeDuration = 0.3

    let total = max(minimumTimelineDuration, totalDuration)
    let start = max(0, min(startTime, total))
    let end = max(start, min(start + max(0, duration), total))
    let fade = min(maximumFadeDuration, (end - start) / 2)
    let fadeInEnd = min(end, start + fade)
    let fadeOutStart = max(start, end - fade)

    let anim = CAKeyframeAnimation(keyPath: "opacity")
    anim.values = [0, 0, 1, 1, 0, 0]
    anim.keyTimes = [
        0,
        NSNumber(value: start / total),
        NSNumber(value: fadeInEnd / total),
        NSNumber(value: fadeOutStart / total),
        NSNumber(value: end / total),
        1
    ]
    anim.beginTime = AVCoreAnimationBeginTimeAtZero
    anim.duration = total
    anim.isRemovedOnCompletion = false
    anim.fillMode = .both
    anim.calculationMode = .linear
    return anim
}

private func makeTikTokPopInAnimation(
    startTime: Double,
    duration: Double,
    totalDuration: Double
) -> CAAnimationGroup {
    let minimumTimelineDuration = 0.001
    let total = max(minimumTimelineDuration, totalDuration)
    let start = max(0, min(startTime, total))
    let end = max(start, min(start + max(0, duration), total))
    let visibleDuration = max(0.001, end - start)

    let popDuration = min(0.24, max(0.10, visibleDuration * 0.35))
    let popMid = min(end, start + popDuration * 0.5)
    let popEnd = min(end, start + popDuration)

    let fadeOutDuration = min(0.22, visibleDuration * 0.22)
    let fadeOutStart = max(start, end - fadeOutDuration)

    let opacity = CAKeyframeAnimation(keyPath: "opacity")
    opacity.values = [0, 0, 1, 1, 0, 0]
    opacity.keyTimes = [
        0,
        NSNumber(value: start / total),
        NSNumber(value: popEnd / total),
        NSNumber(value: fadeOutStart / total),
        NSNumber(value: end / total),
        1
    ]
    opacity.calculationMode = .linear

    let scale = CAKeyframeAnimation(keyPath: "transform.scale")
    scale.values = [0.86, 0.86, 1.12, 0.98, 1.0, 1.0]
    scale.keyTimes = [
        0,
        NSNumber(value: start / total),
        NSNumber(value: popMid / total),
        NSNumber(value: popEnd / total),
        NSNumber(value: end / total),
        1
    ]
    scale.calculationMode = .cubic

    let group = CAAnimationGroup()
    group.animations = [opacity, scale]
    group.beginTime = AVCoreAnimationBeginTimeAtZero
    group.duration = total
    group.isRemovedOnCompletion = false
    group.fillMode = .both
    return group
}

/// Builds a CoreText font descriptor with the requested weight for export text layers.
private func annotationCTFont(size: CGFloat, weight: CGFloat) -> CTFont {
    let traits: [CFString: Any] = [kCTFontWeightTrait: weight]
    let attrs: [CFString: Any] = [
        kCTFontNameAttribute: "HelveticaNeue" as CFString,
        kCTFontTraitsAttribute: traits as CFDictionary
    ]
    let desc = CTFontDescriptorCreateWithAttributes(attrs as CFDictionary)
    return CTFontCreateWithFontDescriptor(desc, size, nil)
}

private func annotationParagraphStyle() -> CTParagraphStyle {
    var alignment = CTTextAlignment.center
    var lineBreak = CTLineBreakMode.byWordWrapping

    return withUnsafePointer(to: &alignment) { alignmentPtr in
        withUnsafePointer(to: &lineBreak) { lineBreakPtr in
            var settings: [CTParagraphStyleSetting] = [
                CTParagraphStyleSetting(
                    spec: .alignment,
                    valueSize: MemoryLayout<CTTextAlignment>.size,
                    value: alignmentPtr
                ),
                CTParagraphStyleSetting(
                    spec: .lineBreakMode,
                    valueSize: MemoryLayout<CTLineBreakMode>.size,
                    value: lineBreakPtr
                )
            ]
            return CTParagraphStyleCreate(&settings, settings.count)
        }
    }
}

private func annotationTextImage(
    text: String,
    font: CTFont,
    textColor: CGColor,
    size: CGSize,
    drawsShadow: Bool
) -> CGImage? {
    let textRasterScale: CGFloat = 2
    let shadowBlur: CGFloat = 3

    let drawSize = CGSize(width: max(1, size.width), height: max(1, size.height))
    let pixelW = max(1, Int(ceil(drawSize.width * textRasterScale)))
    let pixelH = max(1, Int(ceil(drawSize.height * textRasterScale)))

    guard let ctx = CGContext(
        data: nil,
        width: pixelW,
        height: pixelH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.scaleBy(x: textRasterScale, y: textRasterScale)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(origin: .zero, size: drawSize))

    let style = annotationParagraphStyle()
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
        NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): textColor,
        NSAttributedString.Key(rawValue: kCTParagraphStyleAttributeName as String): style
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)

    let textRect = CGRect(origin: .zero, size: drawSize)
    let path = CGMutablePath()
    path.addRect(textRect)
    let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: 0, length: attributed.length),
        path,
        nil
    )

    if drawsShadow {
        ctx.setShadow(
            offset: CGSize(width: 1, height: 1),
            blur: shadowBlur,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.8)
        )
    }

    CTFrameDraw(frame, ctx)
    return ctx.makeImage()
}

private func annotationTextSize(
    text: String,
    font: CTFont,
    maxWidth: CGFloat
) -> CGSize {
    let style = annotationParagraphStyle()
    let attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
        NSAttributedString.Key(rawValue: kCTParagraphStyleAttributeName as String): style
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
    let constraint = CGSize(width: max(1, maxWidth), height: .greatestFiniteMagnitude)
    let measured = CTFramesetterSuggestFrameSizeWithConstraints(
        framesetter,
        CFRange(location: 0, length: attributed.length),
        nil,
        constraint,
        nil
    )
    return CGSize(width: ceil(max(1, measured.width)), height: ceil(max(1, measured.height)))
}

private func subtitleCTFont(style: SubtitleStyle, videoWidth: CGFloat) -> CTFont {
    let scale = style.autoScaleToFit ? max(0.5, videoWidth / 1080) : 1
    let fontSize = max(14, style.fontSize * scale)
    let name = style.fontName as CFString
    return CTFontCreateWithName(name, fontSize, nil)
}

private func subtitleTextImage(
    text: String,
    font: CTFont,
    style: SubtitleStyle,
    size: CGSize,
    textInset: CGFloat,
    scale: CGFloat
) -> CGImage? {
    let textRasterScale: CGFloat = 2
    let drawSize = CGSize(width: max(1, size.width), height: max(1, size.height))
    let pixelW = max(1, Int(ceil(drawSize.width * textRasterScale)))
    let pixelH = max(1, Int(ceil(drawSize.height * textRasterScale)))

    guard let ctx = CGContext(
        data: nil,
        width: pixelW,
        height: pixelH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.scaleBy(x: textRasterScale, y: textRasterScale)
    ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 0))
    ctx.fill(CGRect(origin: .zero, size: drawSize))

    let shadowBlur = max(0, style.shadowBlur * scale)
    let shadowOffset = CGSize(width: style.shadowOffset.width * scale, height: style.shadowOffset.height * scale)
    if shadowBlur > 0 || shadowOffset != .zero {
        let c = style.shadowColor
        ctx.setShadow(
            offset: shadowOffset,
            blur: shadowBlur,
            color: CGColor(red: c.red, green: c.green, blue: c.blue, alpha: 0.95)
        )
    }

    let paragraphStyle = annotationParagraphStyle()
    let fg = style.textColor
    let stroke = style.outlineColor
    let outlineWidth = max(0, style.outlineWidth * scale)

    var attrs: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(rawValue: kCTFontAttributeName as String): font,
        NSAttributedString.Key(rawValue: kCTForegroundColorAttributeName as String): CGColor(
            red: fg.red,
            green: fg.green,
            blue: fg.blue,
            alpha: 1
        ),
        NSAttributedString.Key(rawValue: kCTParagraphStyleAttributeName as String): paragraphStyle
    ]

    if outlineWidth > 0 {
        attrs[NSAttributedString.Key(rawValue: kCTStrokeColorAttributeName as String)] = CGColor(
            red: stroke.red,
            green: stroke.green,
            blue: stroke.blue,
            alpha: 1
        )
        attrs[NSAttributedString.Key(rawValue: kCTStrokeWidthAttributeName as String)] = -outlineWidth
    }

    let attributed = NSAttributedString(string: text, attributes: attrs)
    let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
    let textRect = CGRect(
        x: textInset,
        y: textInset,
        width: max(1, drawSize.width - (textInset * 2)),
        height: max(1, drawSize.height - (textInset * 2))
    )
    let path = CGMutablePath()
    path.addRect(textRect)
    let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: 0, length: attributed.length),
        path,
        nil
    )

    CTFrameDraw(frame, ctx)
    return ctx.makeImage()
}

private func annotationArrowPaths(
    start: CGPoint,
    end: CGPoint,
    strokeWidth: CGFloat,
    headSize: CGFloat,
    headAngle: CGFloat,
    doubleHeaded: Bool,
    filled: Bool
) -> (stroke: CGPath, fill: CGPath?) {
    let stroke = CGMutablePath()
    stroke.move(to: start)
    stroke.addLine(to: end)

    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = hypot(dx, dy)
    guard length > 0.0001 else { return (stroke, nil) }

    let ux = dx / length
    let uy = dy / length

    let clampedAngle = headAngle.clamped(to: 8...80)
    let maxHeadFraction: CGFloat = doubleHeaded ? 0.45 : 0.6
    let headLength = min(max(strokeWidth * headSize, strokeWidth * 2), length * maxHeadFraction)
    let wingLength = headLength * tan((clampedAngle * .pi / 180))

    func headPoints(tip: CGPoint, dirX: CGFloat, dirY: CGFloat) -> (left: CGPoint, right: CGPoint) {
        let base = CGPoint(x: tip.x - dirX * headLength,
                           y: tip.y - dirY * headLength)
        let perp = CGPoint(x: -dirY, y: dirX)
        let left = CGPoint(x: base.x + perp.x * wingLength,
                           y: base.y + perp.y * wingLength)
        let right = CGPoint(x: base.x - perp.x * wingLength,
                            y: base.y - perp.y * wingLength)
        return (left, right)
    }

    func addStrokeHead(tip: CGPoint, dirX: CGFloat, dirY: CGFloat) {
        let points = headPoints(tip: tip, dirX: dirX, dirY: dirY)
        stroke.move(to: tip)
        stroke.addLine(to: points.left)
        stroke.move(to: tip)
        stroke.addLine(to: points.right)
    }

    addStrokeHead(tip: end, dirX: ux, dirY: uy)
    if doubleHeaded {
        addStrokeHead(tip: start, dirX: -ux, dirY: -uy)
    }

    guard filled else { return (stroke, nil) }

    let fill = CGMutablePath()
    func addFilledHead(tip: CGPoint, dirX: CGFloat, dirY: CGFloat) {
        let points = headPoints(tip: tip, dirX: dirX, dirY: dirY)
        fill.move(to: tip)
        fill.addLine(to: points.left)
        fill.addLine(to: points.right)
        fill.closeSubpath()
    }

    addFilledHead(tip: end, dirX: ux, dirY: uy)
    if doubleHeaded {
        addFilledHead(tip: start, dirX: -ux, dirY: -uy)
    }

    return (stroke, fill)
}

// MARK: - Export errors

enum ExportError: LocalizedError {
    case noVideoTrack
    case compositionFailed
    case exportSessionFailed(String)

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:               return "The asset has no video track."
        case .compositionFailed:          return "Failed to build the composition."
        case .exportSessionFailed(let r): return "Export failed: \(r)"
        }
    }
}

// MARK: - Export function

func exportVideo(
    asset: AVURLAsset,
    segments: [ZoomSegment],
    annotations: [Annotation],
    subtitles: [SubtitleSegment] = [],
    subtitleStyle: SubtitleStyle = .classic,
    background: BackgroundSettings,
    trimStart: Double,
    trimEnd: Double,
    speed: Double,
    outputURL: URL,
    presetName: String = AVAssetExportPresetHighestQuality
) async throws {
    CFLogInfo("ExportEngine: Starting export, trim: \(trimStart)-\(trimEnd), speed: \(speed), preset: \(presetName)")

    // ── 1. Composition ────────────────────────────────────────────────────────
    let composition = AVMutableComposition()
    CFLogDebug("ExportEngine: Created composition")

    guard
        let srcVideo = try await asset.loadTracks(withMediaType: .video).first,
        let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { 
        CFLogError("ExportEngine: No video track found")
        throw ExportError.noVideoTrack 
    }
    CFLogDebug("ExportEngine: Added video track to composition")

    let assetDuration = try await asset.load(.duration)
    let clampedEnd    = min(trimEnd, CMTimeGetSeconds(assetDuration))
    let trimRange     = CMTimeRange(
        start:    CMTime(seconds: trimStart,  preferredTimescale: 600),
        duration: CMTime(seconds: clampedEnd - trimStart, preferredTimescale: 600)
    )

    try compVideo.insertTimeRange(trimRange, of: srcVideo, at: .zero)
    CFLogDebug("ExportEngine: Inserted video time range")

    var compAudio: AVMutableCompositionTrack?
    if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first,
       let ca = composition.addMutableTrack(
           withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try ca.insertTimeRange(trimRange, of: srcAudio, at: .zero)
        compAudio = ca
        CFLogDebug("ExportEngine: Added audio track")
    }

    // Apply speed by scaling the inserted time range
    let insertedRange = CMTimeRange(start: .zero, duration: trimRange.duration)
    if abs(speed - 1.0) > 0.005 {
        let scaledDuration = CMTime(seconds: (clampedEnd - trimStart) / speed,
                                    preferredTimescale: 600)
        compVideo.scaleTimeRange(insertedRange, toDuration: scaledDuration)
        compAudio?.scaleTimeRange(insertedRange, toDuration: scaledDuration)
        CFLogDebug("ExportEngine: Applied speed scaling: \(speed)")
    }

    let exportDuration = CMTime(seconds: (clampedEnd - trimStart) / speed, preferredTimescale: 600)
    let exportDurationSeconds = CMTimeGetSeconds(exportDuration)
    let exportRange    = CMTimeRange(start: .zero, duration: exportDuration)
    CFLogDebug("ExportEngine: Export duration: \(exportDurationSeconds) seconds")

    // ── 2. Geometry ──────────────────────────────────────────────────────────
    let naturalSize       = try await srcVideo.load(.naturalSize)
    let preferredTransform = try await srcVideo.load(.preferredTransform)
    CFLogDebug("ExportEngine: Video natural size: \(naturalSize), transform: \(preferredTransform)")

    // Video dimensions after rotation (source resolution)
    let nativeRenderSize: CGSize = {
        let t = preferredTransform
        if abs(t.b) > 0.5 || abs(t.c) > 0.5 {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }()

    let f            = background.paddingFraction
    let nativeHPad   = f * nativeRenderSize.width
    let nativeVPad   = f * nativeRenderSize.height
    let nativeCanvas = CGSize(width:  nativeRenderSize.width  + 2 * nativeHPad,
                              height: nativeRenderSize.height + 2 * nativeVPad)

    // AVFoundation respects the preset's max resolution only downward — it won't
    // upscale beyond videoComposition.renderSize. When the preset requests a
    // higher resolution than the source, enlarge the canvas ourselves.
    let renderScale: CGFloat = {
        let desired: CGSize
        switch presetName {
        case AVAssetExportPreset3840x2160: desired = CGSize(width: 3840, height: 2160)
        default: return 1.0
        }
        let s = min(desired.width / nativeCanvas.width, desired.height / nativeCanvas.height)
        return max(1.0, s)
    }()
    let renderSize = CGSize(width:  nativeRenderSize.width  * renderScale,
                            height: nativeRenderSize.height * renderScale)
    let hPad       = nativeHPad * renderScale
    let vPad       = nativeVPad * renderScale
    let canvasSize = CGSize(width:  nativeCanvas.width  * renderScale,
                            height: nativeCanvas.height * renderScale)
    if renderScale > 1 {
        CFLogInfo("ExportEngine: Upscaling canvas to \(Int(canvasSize.width))×\(Int(canvasSize.height)) (scale ×\(String(format: "%.2f", renderScale)))")
    } else {
        CFLogDebug("ExportEngine: Canvas size: \(canvasSize), padding: \(hPad)x\(vPad)")
    }

    // ── 3. Adjust segment times for trim offset and speed ────────────────────
    let adjustedSegments: [ZoomSegment] = segments
        .filter { $0.isEnabled && $0.startTime < clampedEnd && $0.endTime > trimStart }
        .map { seg in
            ZoomSegment(id: seg.id,
                        startTime: max(0, (seg.startTime - trimStart) / speed),
                        duration:  seg.duration / speed,
                        scale:     seg.scale,
                        center:    seg.center,
                        easeIn:    seg.easeIn  / speed,
                        easeOut:   seg.easeOut / speed,
                        isEnabled: true)
        }
        .sorted { $0.startTime < $1.startTime }
    CFLogDebug("ExportEngine: Adjusted \(adjustedSegments.count) zoom segments for export")

    // Adjust annotation times too
    let adjustedAnnotations: [Annotation] = annotations
        .filter { $0.startTime < clampedEnd && $0.startTime + $0.duration > trimStart }
        .compactMap { ann in
            let clippedStart = max(ann.startTime, trimStart)
            let clippedEnd = min(ann.startTime + ann.duration, clampedEnd)
            guard clippedEnd > clippedStart else { return nil }

            return Annotation(id: ann.id, kind: ann.kind, text: ann.text,
                              startTime: max(0, (clippedStart - trimStart) / speed),
                              duration: (clippedEnd - clippedStart) / speed,
                              position: ann.position,
                              endPosition: ann.endPosition,
                              strokeColor: ann.strokeColor,
                              strokeWidth: ann.strokeWidth,
                              textColor: ann.textColor,
                              fontSize: ann.fontSize,
                              fontWeight: ann.fontWeight,
                              showBackground: ann.showBackground,
                              backgroundColor: ann.backgroundColor,
                              backgroundOpacity: ann.backgroundOpacity,
                              backgroundCornerRadius: ann.backgroundCornerRadius,
                              arrowHeadSize: ann.arrowHeadSize,
                              arrowHeadAngle: ann.arrowHeadAngle,
                              arrowDoubleHeaded: ann.arrowDoubleHeaded,
                              arrowFilled: ann.arrowFilled)
        }
    CFLogDebug("ExportEngine: Adjusted \(adjustedAnnotations.count) annotations for export")

    // Adjust subtitle times for trim offset and speed
    let adjustedSubtitles: [SubtitleSegment] = subtitles
        .filter { $0.start < clampedEnd && $0.end > trimStart }
        .compactMap { seg in
            let clippedStart = max(seg.start, trimStart)
            let clippedEnd   = min(seg.end,   clampedEnd)
            guard clippedEnd > clippedStart else { return nil }
            return SubtitleSegment(
                start: max(0, (clippedStart - trimStart) / speed),
                end:   max(0, (clippedEnd   - trimStart) / speed),
                text:  seg.text
            )
        }
    CFLogDebug("ExportEngine: Adjusted \(adjustedSubtitles.count) subtitle(s) for export (of \(subtitles.count) total)")

    // ── 4. Layer instruction — eased zoom sampled at 30 fps ──────────────────
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)

    // When upscaling, pre-scale the preferred transform so the video fills the
    // larger render space rather than sitting at its original pixel size.
    let exportPreferredTransform = renderScale > 1
        ? preferredTransform.concatenating(CGAffineTransform(scaleX: renderScale, y: renderScale))
        : preferredTransform

    applyEasedZoomRamps(
        to: layerInstruction,
        segments: adjustedSegments,
        exportDuration: exportDurationSeconds,
        videoSize: renderSize,
        paddingX: hPad, paddingY: vPad,
        preferredTransform: exportPreferredTransform
    )

    // ── 5. Video composition ─────────────────────────────────────────────────
    let videoComposition      = AVMutableVideoComposition()
    videoComposition.renderSize    = canvasSize
    videoComposition.frameDuration = CMTime(value: 1, timescale: 30)

    let instruction           = AVMutableVideoCompositionInstruction()
    instruction.timeRange         = exportRange
    instruction.layerInstructions = [layerInstruction]
    videoComposition.instructions = [instruction]

    // ── 6. CALayer tree: background + video + text ───────────────────────────
    let parentLayer = CALayer()
    parentLayer.frame = CGRect(origin: .zero, size: canvasSize)
    parentLayer.isGeometryFlipped = true
    parentLayer.beginTime = AVCoreAnimationBeginTimeAtZero
    parentLayer.speed = 1

    // Background
    let bgLayer = buildBackgroundLayer(background, size: canvasSize)
    parentLayer.addSublayer(bgLayer)

    // Shadow behind video card
    if background.shadowOpacity > 0 {
        let shadowLayer = CAShapeLayer()
        shadowLayer.frame = CGRect(x: hPad, y: vPad, width: renderSize.width, height: renderSize.height)
        shadowLayer.path = CGPath(roundedRect: CGRect(origin: .zero, size: renderSize),
                                  cornerWidth: background.cornerRadius,
                                  cornerHeight: background.cornerRadius, transform: nil)
        shadowLayer.fillColor    = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        shadowLayer.shadowColor  = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        shadowLayer.shadowOpacity = background.shadowOpacity
        shadowLayer.shadowRadius  = background.shadowRadius * renderScale
        shadowLayer.shadowOffset  = CGSize(width: 0, height: 3 * renderScale)
        parentLayer.addSublayer(shadowLayer)
    }

    // Video layer (clipped to rounded rect)
    let videoLayer  = CALayer()
    videoLayer.frame = CGRect(x: hPad, y: vPad, width: renderSize.width, height: renderSize.height)
    if background.cornerRadius > 0 {
        let mask = CAShapeLayer()
        mask.path = CGPath(roundedRect: CGRect(origin: .zero, size: renderSize),
                           cornerWidth: background.cornerRadius,
                           cornerHeight: background.cornerRadius, transform: nil)
        videoLayer.mask = mask
    }
    parentLayer.addSublayer(videoLayer)

    // Text annotations
    for ann in adjustedAnnotations where ann.kind == .text {
        let actualFontSize = max(8, ann.fontSize * renderSize.width)
        let ctFont = annotationCTFont(size: actualFontSize, weight: ann.fontWeight.ctWeight)

        // Match preview layout: intrinsic text size + fixed background paddings.
        let bgPaddingX: CGFloat = ann.showBackground ? 8 * renderScale : 0
        let bgPaddingY: CGFloat = ann.showBackground ? 4 * renderScale : 0
        let maxTextWidth = max(1, renderSize.width - (bgPaddingX * 2))
        let textSize = annotationTextSize(text: ann.text, font: ctFont, maxWidth: maxTextWidth)

        let centerX = hPad + ann.position.x * renderSize.width
        let centerY = vPad + ann.position.y * renderSize.height
        let textFrame = CGRect(
            x: centerX - textSize.width / 2,
            y: centerY - textSize.height / 2,
            width: textSize.width,
            height: textSize.height
        )

        let visibility = makeVisibilityOpacityAnimation(
            startTime: ann.startTime,
            duration: ann.duration,
            totalDuration: exportDurationSeconds
        )

        // Background box
        if ann.showBackground {
            let bgLayer = CALayer()
            bgLayer.frame = textFrame.insetBy(dx: -bgPaddingX, dy: -bgPaddingY)
            let bg = ann.backgroundColor
            bgLayer.backgroundColor = CGColor(red: bg.red, green: bg.green, blue: bg.blue,
                                              alpha: ann.backgroundOpacity)
            bgLayer.cornerRadius = ann.backgroundCornerRadius
            bgLayer.opacity      = 1
            bgLayer.add(visibility, forKey: "visibility")
            parentLayer.addSublayer(bgLayer)
        }

        let textLayer = CALayer()
        textLayer.contents = annotationTextImage(
            text: ann.text,
            font: ctFont,
            textColor: ann.textColor.cgColor,
            size: textSize,
            drawsShadow: !ann.showBackground
        )
        textLayer.contentsScale = 2
        textLayer.contentsGravity = .resize
        textLayer.frame = textFrame
        textLayer.opacity = 1
        textLayer.add(visibility, forKey: "visibility")
        parentLayer.addSublayer(textLayer)
    }

    // Shape annotations
    for ann in adjustedAnnotations where ann.kind != .text {
        let sx = hPad + ann.position.x    * renderSize.width
        let sy = vPad + ann.position.y    * renderSize.height
        let ex = hPad + ann.endPosition.x * renderSize.width
        let ey = vPad + ann.endPosition.y * renderSize.height

        var path: CGPath
        var fillColor: CGColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        switch ann.kind {
        case .line:
            let p = CGMutablePath(); p.move(to: CGPoint(x: sx, y: sy))
            p.addLine(to: CGPoint(x: ex, y: ey)); path = p
        case .arrow:
            let arrowPaths = annotationArrowPaths(
                start: CGPoint(x: sx, y: sy),
                end: CGPoint(x: ex, y: ey),
                strokeWidth: ann.strokeWidth,
                headSize: ann.arrowHeadSize,
                headAngle: ann.arrowHeadAngle,
                doubleHeaded: ann.arrowDoubleHeaded,
                filled: ann.arrowFilled
            )
            path = arrowPaths.stroke
            if ann.arrowFilled, let fillPath = arrowPaths.fill {
                let merged = CGMutablePath()
                merged.addPath(path)
                merged.addPath(fillPath)
                path = merged
                fillColor = ann.strokeColor.cgColor
            }
        case .rectangle:
            path = CGPath(rect: CGRect(x: min(sx, ex), y: min(sy, ey),
                                       width: abs(ex - sx), height: abs(ey - sy)),
                          transform: nil)
        case .circle:
            let r: CGFloat = hypot(ex - sx, ey - sy)
            path = CGPath(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2),
                          transform: nil)
        case .text: continue
        }

        let shapeLayer            = CAShapeLayer()
        shapeLayer.path           = path
        shapeLayer.fillColor      = fillColor
        shapeLayer.strokeColor    = ann.strokeColor.cgColor
        shapeLayer.lineWidth      = ann.strokeWidth * renderScale
        shapeLayer.frame          = CGRect(origin: .zero, size: canvasSize)
        shapeLayer.opacity        = 1

        shapeLayer.add(
            makeVisibilityOpacityAnimation(
                startTime: ann.startTime,
                duration: ann.duration,
                totalDuration: exportDurationSeconds
            ),
            forKey: "visibility"
        )

        parentLayer.addSublayer(shapeLayer)
    }

    // ── Subtitle burn-in (bottom center of video) ─────────────────────────────
    if !adjustedSubtitles.isEmpty {
        CFLogInfo("ExportEngine: Burning in \(adjustedSubtitles.count) subtitle(s)")
        let styleScale = subtitleStyle.autoScaleToFit ? max(0.5, renderSize.width / 1080) : 1
        let ctFont = subtitleCTFont(style: subtitleStyle, videoWidth: renderSize.width)
        let subtitleRelativeY = subtitleStyle.verticalPosition.clamped(to: 0.05...0.95)
        let horizontalMargin = subtitleStyle.horizontalMargin.clamped(to: 0...0.3)
        let maxTextWidth = max(1, renderSize.width * (1 - horizontalMargin * 2))
        let bgPadding = max(6, subtitleStyle.backgroundPadding * styleScale)
        let outline = max(0, subtitleStyle.outlineWidth * styleScale)
        let shadowBlur = max(0, subtitleStyle.shadowBlur * styleScale)
        let shadowOffset = CGSize(
            width: subtitleStyle.shadowOffset.width * styleScale,
            height: subtitleStyle.shadowOffset.height * styleScale
        )
        let shadowMaxOffset = max(abs(shadowOffset.width), abs(shadowOffset.height))
        let textInset: CGFloat = max(2, outline + shadowBlur + shadowMaxOffset)
        let subtitleBG = subtitleStyle.backgroundColor
        let subtitleBGAlpha = subtitleStyle.backgroundOpacity.clamped(to: 0...1)
        let usesTikTokAnimation = subtitleStyle == .tikTok || subtitleStyle == .tikTokYellow

        for (idx, sub) in adjustedSubtitles.enumerated() {
            let textSize = annotationTextSize(text: sub.text, font: ctFont, maxWidth: maxTextWidth)
            let drawSize = CGSize(width: textSize.width + (textInset * 2),
                                  height: textSize.height + (textInset * 2))
            let centerX = hPad + renderSize.width / 2
            let centerY = vPad + subtitleRelativeY * renderSize.height

            let textFrame = CGRect(
                x: centerX - drawSize.width / 2,
                y: centerY - drawSize.height / 2,
                width: drawSize.width,
                height: drawSize.height
            )

            let visibility = makeVisibilityOpacityAnimation(
                startTime: sub.start,
                duration: sub.duration,
                totalDuration: exportDurationSeconds
            )
            let tikTokPopIn = makeTikTokPopInAnimation(
                startTime: sub.start,
                duration: sub.duration,
                totalDuration: exportDurationSeconds
            )

            if subtitleBGAlpha > 0.001 {
                let subtitleBGLayer = CALayer()
                subtitleBGLayer.frame = textFrame.insetBy(dx: -bgPadding, dy: -(bgPadding * 0.45))
                subtitleBGLayer.backgroundColor = CGColor(
                    red: subtitleBG.red,
                    green: subtitleBG.green,
                    blue: subtitleBG.blue,
                    alpha: subtitleBGAlpha
                )
                subtitleBGLayer.cornerRadius = max(5, bgPadding * 0.3)
                subtitleBGLayer.opacity = 1
                subtitleBGLayer.add(visibility, forKey: "visibility")
                parentLayer.addSublayer(subtitleBGLayer)
            }

            // Outlined TikTok-style subtitle text
            let subtitleTextLayer = CALayer()
            subtitleTextLayer.contents = subtitleTextImage(
                text: sub.text,
                font: ctFont,
                style: subtitleStyle,
                size: drawSize,
                textInset: textInset,
                scale: styleScale
            )
            subtitleTextLayer.contentsScale = 2
            subtitleTextLayer.contentsGravity = .resize
            subtitleTextLayer.frame = textFrame
            subtitleTextLayer.opacity = 1
            subtitleTextLayer.add(usesTikTokAnimation ? tikTokPopIn : visibility, forKey: "visibility")
            parentLayer.addSublayer(subtitleTextLayer)

            CFLogDebug("ExportEngine: Subtitle \(idx + 1)/\(adjustedSubtitles.count) layer: [\(String(format: "%.2f", sub.start))s–\(String(format: "%.2f", sub.end))s] \"\(sub.text)\"")
        }
    }

    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer, in: parentLayer)

    // ── 7. Export session ────────────────────────────────────────────────────
    guard let session = AVAssetExportSession(asset: composition,
                                             presetName: presetName)
    else { throw ExportError.compositionFailed }

    session.videoComposition = videoComposition
    session.outputURL        = outputURL
    session.outputFileType   = .mp4
    CFLogInfo("ExportEngine: Starting export session to: \(outputURL.lastPathComponent)")
    
    await session.export()

    switch session.status {
    case .completed: 
        CFLogInfo("ExportEngine: Export completed successfully")
        return
    case .failed:    
        let errorMsg = session.error?.localizedDescription ?? "unknown"
        CFLogError("ExportEngine: Export failed: \(errorMsg)")
        throw ExportError.exportSessionFailed(errorMsg)
    case .cancelled: 
        CFLogWarn("ExportEngine: Export cancelled")
        throw ExportError.exportSessionFailed("Cancelled")
    default:         
        let errorMsg = "Unexpected status \(session.status.rawValue)"
        CFLogError("ExportEngine: \(errorMsg)")
        throw ExportError.exportSessionFailed(errorMsg)
    }
}

// MARK: - Background CALayer factory

private func buildBackgroundLayer(_ bg: BackgroundSettings, size: CGSize) -> CALayer {
    let frame = CGRect(origin: .zero, size: size)
    switch bg.style {
    case .gradient:
        let layer            = CAGradientLayer()
        layer.frame          = frame
        layer.colors         = [bg.gradientStart.cgColor, bg.gradientEnd.cgColor]
        layer.startPoint     = CGPoint(x: 0, y: 0)
        layer.endPoint       = CGPoint(x: 1, y: 1)
        return layer
    case .solid:
        let layer            = CALayer()
        layer.frame          = frame
        layer.backgroundColor = bg.solidColor.cgColor
        return layer
    case .transparent:
        let layer            = CALayer()
        layer.frame          = frame
        layer.backgroundColor = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        return layer
    }
}
