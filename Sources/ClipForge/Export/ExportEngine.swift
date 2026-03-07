import AVFoundation
import CoreGraphics
import CoreText
import QuartzCore
import Foundation

// MARK: - Easing

private func easeInOut(_ t: Double) -> Double {
    let t = max(0, min(1, t))
    return t * t * (3 - 2 * t)
}

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
    let base    = preferredTransform
        .concatenating(CGAffineTransform(translationX: paddingX, y: paddingY))

    guard !enabled.isEmpty else {
        instruction.setTransform(base, at: .zero)
        return
    }

    let step  = 1.0 / fps
    let count = Int(ceil(exportDuration / step))

    for i in 0...count {
        let t  = min(Double(i) * step, exportDuration)
        let T  = segmentZoomTransform(at: t, segments: enabled,
                                      videoSize: videoSize, paddingX: paddingX, paddingY: paddingY,
                                      preferredTransform: preferredTransform)
        let t1 = CMTime(seconds: t, preferredTimescale: 6000)
        if i == 0 {
            instruction.setTransform(T, at: t1)
        } else {
            let prev = min(Double(i - 1) * step, exportDuration)
            let T0   = segmentZoomTransform(at: prev, segments: enabled,
                                            videoSize: videoSize, paddingX: paddingX, paddingY: paddingY,
                                            preferredTransform: preferredTransform)
            instruction.setTransformRamp(fromStart: T0, toEnd: T,
                                         timeRange: CMTimeRange(
                                            start: CMTime(seconds: prev, preferredTimescale: 6000),
                                            end:   t1))
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
    let total = max(0.001, totalDuration)
    let start = max(0, min(startTime, total))
    let end = max(start, min(start + max(0, duration), total))
    let fade = min(0.3, (end - start) / 2)
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
    let drawSize = CGSize(width: max(1, size.width), height: max(1, size.height))
    let scale: CGFloat = 2
    let pixelW = max(1, Int(ceil(drawSize.width * scale)))
    let pixelH = max(1, Int(ceil(drawSize.height * scale)))

    guard let ctx = CGContext(
        data: nil,
        width: pixelW,
        height: pixelH,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    ctx.scaleBy(x: scale, y: scale)
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

    let textRect = CGRect(origin: .zero, size: drawSize).insetBy(dx: 2, dy: 2)
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
            offset: CGSize(width: 1, height: -1),
            blur: 3,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.8)
        )
    }

    CTFrameDraw(frame, ctx)
    return ctx.makeImage()
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
    background: BackgroundSettings,
    trimStart: Double,
    trimEnd: Double,
    speed: Double,
    outputURL: URL
) async throws {

    // ── 1. Composition ────────────────────────────────────────────────────────
    let composition = AVMutableComposition()

    guard
        let srcVideo = try await asset.loadTracks(withMediaType: .video).first,
        let compVideo = composition.addMutableTrack(
            withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
    else { throw ExportError.noVideoTrack }

    let assetDuration = try await asset.load(.duration)
    let clampedEnd    = min(trimEnd, CMTimeGetSeconds(assetDuration))
    let trimRange     = CMTimeRange(
        start:    CMTime(seconds: trimStart,  preferredTimescale: 600),
        duration: CMTime(seconds: clampedEnd - trimStart, preferredTimescale: 600)
    )

    try compVideo.insertTimeRange(trimRange, of: srcVideo, at: .zero)

    var compAudio: AVMutableCompositionTrack?
    if let srcAudio = try await asset.loadTracks(withMediaType: .audio).first,
       let ca = composition.addMutableTrack(
           withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
        try ca.insertTimeRange(trimRange, of: srcAudio, at: .zero)
        compAudio = ca
    }

    // Apply speed by scaling the inserted time range
    let insertedRange = CMTimeRange(start: .zero, duration: trimRange.duration)
    if abs(speed - 1.0) > 0.005 {
        let scaledDuration = CMTime(seconds: (clampedEnd - trimStart) / speed,
                                    preferredTimescale: 600)
        compVideo.scaleTimeRange(insertedRange, toDuration: scaledDuration)
        compAudio?.scaleTimeRange(insertedRange, toDuration: scaledDuration)
    }

    let exportDuration = CMTime(seconds: (clampedEnd - trimStart) / speed, preferredTimescale: 600)
    let exportDurationSeconds = CMTimeGetSeconds(exportDuration)
    let exportRange    = CMTimeRange(start: .zero, duration: exportDuration)

    // ── 2. Geometry ──────────────────────────────────────────────────────────
    let naturalSize       = try await srcVideo.load(.naturalSize)
    let preferredTransform = try await srcVideo.load(.preferredTransform)

    // Video dimensions after rotation
    let renderSize: CGSize = {
        let t = preferredTransform
        if abs(t.b) > 0.5 || abs(t.c) > 0.5 {
            return CGSize(width: naturalSize.height, height: naturalSize.width)
        }
        return naturalSize
    }()

    let f          = background.paddingFraction
    let hPad       = f * renderSize.width
    let vPad       = f * renderSize.height
    let canvasSize = CGSize(width: renderSize.width + 2 * hPad, height: renderSize.height + 2 * vPad)

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
                              backgroundCornerRadius: ann.backgroundCornerRadius)
        }

    // ── 4. Layer instruction — eased zoom sampled at 30 fps ──────────────────
    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compVideo)

    applyEasedZoomRamps(
        to: layerInstruction,
        segments: adjustedSegments,
        exportDuration: exportDurationSeconds,
        videoSize: renderSize,
        paddingX: hPad, paddingY: vPad,
        preferredTransform: preferredTransform
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
        shadowLayer.shadowRadius  = background.shadowRadius
        shadowLayer.shadowOffset  = CGSize(width: 0, height: 3)
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
        let actualFontSize = max(12, ann.fontSize * renderSize.width)
        let ctFont = annotationCTFont(size: actualFontSize, weight: ann.fontWeight.ctWeight)

        let w: CGFloat = renderSize.width * 0.8
        let h: CGFloat = max(actualFontSize * 2, renderSize.height * 0.08)
        let x = hPad + ann.position.x * renderSize.width  - w / 2
        let y = vPad + ann.position.y * renderSize.height - h / 2

        let visibility = makeVisibilityOpacityAnimation(
            startTime: ann.startTime,
            duration: ann.duration,
            totalDuration: exportDurationSeconds
        )

        // Background box
        if ann.showBackground {
            let hPadding = actualFontSize * 0.4
            let vPadding = actualFontSize * 0.25
            let bgLayer  = CALayer()
            bgLayer.frame = CGRect(x: x - hPadding, y: y - vPadding,
                                   width: w + 2 * hPadding, height: h + 2 * vPadding)
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
            size: CGSize(width: w, height: h),
            drawsShadow: !ann.showBackground
        )
        textLayer.contentsScale = 2
        textLayer.contentsGravity = .resize
        textLayer.frame   = CGRect(x: x, y: y, width: w, height: h)
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
        switch ann.kind {
        case .line:
            let p = CGMutablePath(); p.move(to: CGPoint(x: sx, y: sy))
            p.addLine(to: CGPoint(x: ex, y: ey)); path = p
        case .rectangle:
            path = CGPath(rect: CGRect(x: min(sx, ex), y: min(sy, ey),
                                       width: abs(ex - sx), height: abs(ey - sy)),
                          transform: nil)
        case .circle:
            let r = hypot(ex - sx, ey - sy)
            path = CGPath(ellipseIn: CGRect(x: sx - r, y: sy - r, width: r * 2, height: r * 2),
                          transform: nil)
        case .text: continue
        }

        let shapeLayer            = CAShapeLayer()
        shapeLayer.path           = path
        shapeLayer.fillColor      = CGColor(red: 0, green: 0, blue: 0, alpha: 0)
        shapeLayer.strokeColor    = ann.strokeColor.cgColor
        shapeLayer.lineWidth      = ann.strokeWidth
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

    videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
        postProcessingAsVideoLayer: videoLayer, in: parentLayer)

    // ── 7. Export session ────────────────────────────────────────────────────
    guard let session = AVAssetExportSession(asset: composition,
                                             presetName: AVAssetExportPresetHighestQuality)
    else { throw ExportError.compositionFailed }

    session.videoComposition = videoComposition
    session.outputURL        = outputURL
    session.outputFileType   = .mp4
    await session.export()

    switch session.status {
    case .completed: return
    case .failed:    throw ExportError.exportSessionFailed(session.error?.localizedDescription ?? "unknown")
    case .cancelled: throw ExportError.exportSessionFailed("Cancelled")
    default:         throw ExportError.exportSessionFailed("Unexpected status \(session.status.rawValue)")
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
