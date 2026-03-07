import SwiftUI

struct VisualTimelineView: View {
    @ObservedObject var vm: VideoEditorViewModel

    private let rulerH: CGFloat   = 22
    private let zoomH: CGFloat    = 44
    private let annH: CGFloat     = 34
    private var totalH: CGFloat   { rulerH + zoomH + annH + 2 }

    private let annColors: [Color] = [.blue, .purple, .green, .orange, .pink, .teal]

    // ── Drag state ─────────────────────────────────────────────────────────────
    private enum DragTarget: Equatable {
        case playhead
        case trimStart, trimEnd
        case segmentBody(UUID)
        case segmentLeft(UUID)
        case segmentRight(UUID)
        case annotationBody(UUID)
        case annotationLeft(UUID)
        case annotationRight(UUID)
    }

    @State private var dragTarget: DragTarget          = .playhead
    @State private var dragSegmentStartTime: Double    = 0
    @State private var dragSegmentDuration: Double     = 0
    @State private var dragStartX: CGFloat             = 0

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width

            ZStack(alignment: .topLeading) {
                // ── Canvas: static drawing ─────────────────────────────────
                Canvas { ctx, size in
                    guard vm.duration > 0 else { return }
                    drawRuler(ctx: ctx, w: size.width)
                    drawZoomRow(ctx: ctx, w: size.width)
                    drawAnnotationRow(ctx: ctx, w: size.width)
                    drawTrimOverlay(ctx: ctx, w: size.width, h: size.height)
                    drawPlayhead(ctx: ctx, w: size.width, h: size.height)
                }

                // ── Per-block context menus (invisible overlay per segment) ─
                if vm.duration > 0 {
                    ForEach(vm.segments) { seg in
                        let x = xFor(seg.startTime, w: w)
                        let bw = max(4, xFor(seg.endTime, w: w) - x)
                        Color.clear
                            .frame(width: bw, height: zoomH)
                            .offset(x: x, y: rulerH + 1)
                            .contextMenu {
                                Button {
                                    vm.toggleSegmentEnabled(id: seg.id)
                                } label: {
                                    Label(seg.isEnabled ? "Disable" : "Enable",
                                          systemImage: seg.isEnabled ? "eye.slash" : "eye")
                                }
                                Button(role: .destructive) {
                                    vm.removeSegment(id: seg.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }

                    ForEach(vm.annotations) { ann in
                        let x = xFor(ann.startTime, w: w)
                        let bw = max(4, xFor(ann.startTime + ann.duration, w: w) - x)
                        Color.clear
                            .frame(width: bw, height: annH)
                            .offset(x: x, y: rulerH + zoomH + 2)
                            .contextMenu {
                                Button(role: .destructive) {
                                    vm.removeAnnotation(id: ann.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard vm.duration > 0 else { return }
                        if v.translation == .zero {
                            // First event: decide what's being dragged
                            dragTarget = pickTarget(x: v.startLocation.x,
                                                    y: v.startLocation.y, w: w)
                            dragStartX = v.startLocation.x
                            switch dragTarget {
                            case .segmentBody(let id), .segmentLeft(let id):
                                if let seg = vm.segments.first(where: { $0.id == id }) {
                                    dragSegmentStartTime = seg.startTime
                                    dragSegmentDuration  = seg.duration
                                }
                            case .segmentRight(let id):
                                if let seg = vm.segments.first(where: { $0.id == id }) {
                                    dragSegmentDuration = seg.duration
                                }
                            case .annotationBody(let id), .annotationLeft(let id):
                                if let ann = vm.annotations.first(where: { $0.id == id }) {
                                    dragSegmentStartTime = ann.startTime
                                    dragSegmentDuration  = ann.duration
                                }
                            case .annotationRight(let id):
                                if let ann = vm.annotations.first(where: { $0.id == id }) {
                                    dragSegmentDuration = ann.duration
                                }
                            default: break
                            }
                        }

                        let t  = (Double(v.location.x / w) * vm.duration)
                            .clamped(to: 0...vm.duration)
                        let dt = Double((v.location.x - dragStartX) / w) * vm.duration

                        switch dragTarget {
                        case .playhead:
                            vm.seek(to: t); vm.currentTime = t

                        case .trimStart:
                            vm.trimStart = min(t, vm.effectiveTrimEnd - 0.1)

                        case .trimEnd:
                            let c = max(t, vm.trimStart + 0.1)
                            vm.trimEnd = c >= vm.duration - 0.01 ? nil : c

                        case .segmentBody(let id):
                            let newStart = (dragSegmentStartTime + dt)
                                .clamped(to: 0...(vm.duration - dragSegmentDuration))
                            vm.updateSegment(id: id, startTime: newStart)

                        case .segmentLeft(let id):
                            let newStart = (dragSegmentStartTime + dt)
                                .clamped(to: 0...(dragSegmentStartTime + dragSegmentDuration - 0.3))
                            let newDur = dragSegmentDuration - (newStart - dragSegmentStartTime)
                            vm.updateSegment(id: id, startTime: newStart, duration: newDur)

                        case .segmentRight(let id):
                            guard let seg = vm.segments.first(where: { $0.id == id }) else { break }
                            let newDur = (t - seg.startTime).clamped(to: 0.3...vm.duration)
                            vm.updateSegment(id: id, duration: newDur)

                        case .annotationBody(let id):
                            let newStart = (dragSegmentStartTime + dt)
                                .clamped(to: 0...(vm.duration - dragSegmentDuration))
                            vm.updateAnnotation(id: id, startTime: newStart)

                        case .annotationLeft(let id):
                            let newStart = (dragSegmentStartTime + dt)
                                .clamped(to: 0...(dragSegmentStartTime + dragSegmentDuration - 0.3))
                            let newDur = dragSegmentDuration - (newStart - dragSegmentStartTime)
                            vm.updateAnnotation(id: id, startTime: newStart, duration: newDur)

                        case .annotationRight(let id):
                            guard let ann = vm.annotations.first(where: { $0.id == id }) else { break }
                            let newDur = (t - ann.startTime).clamped(to: 0.3...vm.duration)
                            vm.updateAnnotation(id: id, duration: newDur)
                        }
                    }
                    .onEnded { v in
                        let moved = v.translation.width.magnitude + v.translation.height.magnitude
                        if moved < 6 {
                            let tapT = Double(v.startLocation.x / w) * vm.duration
                            if isInZoomRow(y: v.startLocation.y) {
                                if let hit = segmentAt(time: tapT) {
                                    vm.selectedSegmentID = hit.id
                                } else {
                                    vm.addZoomSegment(at: tapT)
                                }
                            } else if isInAnnotationRow(y: v.startLocation.y) {
                                if let hit = annotationAt(time: tapT) {
                                    vm.selectedAnnotationID = hit.id
                                } else {
                                    vm.addAnnotationSegment(at: tapT)
                                }
                            }
                        }
                        dragTarget = .playhead
                    }
            )
        }
        .frame(height: totalH)
        .background(Color(white: 0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .padding(.horizontal)
    }

    // MARK: - Hit testing

    private func isInZoomRow(y: CGFloat) -> Bool {
        y >= rulerH && y <= rulerH + zoomH
    }

    private func isInAnnotationRow(y: CGFloat) -> Bool {
        y >= rulerH + zoomH && y <= rulerH + zoomH + annH
    }

    private func segmentAt(time: Double) -> ZoomSegment? {
        vm.segments.first { time >= $0.startTime && time <= $0.endTime }
    }

    private func annotationAt(time: Double) -> Annotation? {
        vm.annotations.first { time >= $0.startTime && time <= $0.startTime + $0.duration }
    }

    private func pickTarget(x: CGFloat, y: CGFloat, w: CGFloat) -> DragTarget {
        guard vm.duration > 0 else { return .playhead }

        let tsX  = xFor(vm.trimStart, w: w)
        let teX  = xFor(vm.effectiveTrimEnd, w: w)
        let phX  = xFor(vm.currentTime, w: w)
        let hit: CGFloat = 12

        if abs(x - tsX) <= hit { return .trimStart }
        if abs(x - teX) <= hit { return .trimEnd   }

        // Zoom segment edges and bodies
        if isInZoomRow(y: y) {
            let edgeHit: CGFloat = 10
            for seg in vm.segments {
                let segX  = xFor(seg.startTime, w: w)
                let segX2 = xFor(seg.endTime,   w: w)
                if abs(x - segX)  <= edgeHit { return .segmentLeft(seg.id)  }
                if abs(x - segX2) <= edgeHit { return .segmentRight(seg.id) }
                if x >= segX && x <= segX2   { return .segmentBody(seg.id)  }
            }
        }

        // Annotation edges and bodies
        if isInAnnotationRow(y: y) {
            let edgeHit: CGFloat = 10
            for ann in vm.annotations {
                let annX  = xFor(ann.startTime, w: w)
                let annX2 = xFor(ann.startTime + ann.duration, w: w)
                if abs(x - annX)  <= edgeHit { return .annotationLeft(ann.id)  }
                if abs(x - annX2) <= edgeHit { return .annotationRight(ann.id) }
                if x >= annX && x <= annX2   { return .annotationBody(ann.id)  }
            }
        }

        if abs(x - phX) <= hit { return .playhead }
        return .playhead
    }

    // MARK: - Coordinate helpers

    private func xFor(_ time: Double, w: CGFloat) -> CGFloat {
        guard vm.duration > 0 else { return 0 }
        return CGFloat(time / vm.duration) * w
    }

    private func niceStep(w: CGFloat) -> Double {
        let raw = vm.duration / (Double(w) / 55)
        for c in [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600] {
            if c >= raw { return c }
        }
        return raw
    }

    private func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        if vm.duration < 60 {
            return String(format: "%d:%02d.%d", m, s, Int(t.truncatingRemainder(dividingBy: 1) * 10))
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Ruler

    private func drawRuler(ctx: GraphicsContext, w: CGFloat) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: rulerH)),
                 with: .color(Color(white: 0.15)))
        let step = niceStep(w: w); var t = 0.0
        while t <= vm.duration + step * 0.01 {
            let px = xFor(min(t, vm.duration), w: w)
            ctx.stroke(Path { p in
                p.move(to: CGPoint(x: px, y: rulerH - 6)); p.addLine(to: CGPoint(x: px, y: rulerH))
            }, with: .color(.gray), lineWidth: 1)
            ctx.draw(ctx.resolve(Text(formatTime(min(t, vm.duration)))
                .font(.system(size: 9, design: .monospaced)).foregroundColor(.secondary)),
                at: CGPoint(x: px + 3, y: rulerH - 8), anchor: .bottomLeading)
            t += step
        }
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 0, y: rulerH)); p.addLine(to: CGPoint(x: w, y: rulerH))
        }, with: .color(Color(white: 0.3)), lineWidth: 0.5)
    }

    // MARK: - Zoom row (blocks)

    private func drawZoomRow(ctx: GraphicsContext, w: CGFloat) {
        let rowTop = rulerH + 1

        ctx.draw(ctx.resolve(Text("ZOOM").font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.25))),
            at: CGPoint(x: 5, y: rowTop + 4), anchor: .topLeading)

        for seg in vm.segments {
            let segX  = xFor(seg.startTime, w: w)
            let segX2 = xFor(seg.endTime,   w: w)
            let segW  = max(4, segX2 - segX)
            let isSelected = seg.id == vm.selectedSegmentID
            let isDisabled = !seg.isEnabled

            let blockRect = CGRect(x: segX, y: rowTop + 3, width: segW, height: zoomH - 6)

            let baseColor = Color.purple
            let bodyColor = isDisabled ? baseColor.opacity(0.25) : baseColor.opacity(0.6)
            ctx.fill(Path(roundedRect: blockRect, cornerRadius: 4), with: .color(bodyColor))

            if seg.easeIn > 0 && segW > 8 {
                let easeW = CGFloat(seg.easeIn / seg.duration) * segW
                let easeRect = CGRect(x: segX, y: blockRect.minY, width: easeW, height: blockRect.height)
                var fadeCtx = ctx
                fadeCtx.clip(to: Path(roundedRect: blockRect, cornerRadius: 4))
                fadeCtx.fill(Path(easeRect), with: .color(Color.white.opacity(0.12)))
            }

            if seg.easeOut > 0 && segW > 8 {
                let easeW  = CGFloat(seg.easeOut / seg.duration) * segW
                let easeRect = CGRect(x: segX2 - easeW, y: blockRect.minY,
                                      width: easeW, height: blockRect.height)
                var fadeCtx = ctx
                fadeCtx.clip(to: Path(roundedRect: blockRect, cornerRadius: 4))
                fadeCtx.fill(Path(easeRect), with: .color(Color.white.opacity(0.12)))
            }

            let borderColor: Color = isSelected ? .white : (isDisabled ? Color.white.opacity(0.1) : Color.purple.opacity(0.9))
            ctx.stroke(Path(roundedRect: blockRect, cornerRadius: 4),
                       with: .color(borderColor), lineWidth: isSelected ? 1.5 : 1)

            if segW > 28 {
                let lbl = isDisabled
                    ? ctx.resolve(Text("off").font(.system(size: 9)).foregroundColor(Color.white.opacity(0.4)))
                    : ctx.resolve(Text(String(format: "%.1f×", seg.scale))
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.white))
                var sub = ctx
                sub.clip(to: Path(blockRect.insetBy(dx: 3, dy: 0)))
                sub.draw(lbl, at: CGPoint(x: blockRect.midX, y: blockRect.midY), anchor: .center)
            }

            let handleColor = isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.4)
            for hx in [segX + 2, segX2 - 2] {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: hx, y: blockRect.minY + 4))
                    p.addLine(to: CGPoint(x: hx, y: blockRect.maxY - 4))
                }, with: .color(handleColor), lineWidth: 2)
            }
        }

        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 0, y: rowTop + zoomH))
            p.addLine(to: CGPoint(x: w, y: rowTop + zoomH))
        }, with: .color(Color(white: 0.3)), lineWidth: 0.5)
    }

    // MARK: - Annotation row

    private func drawAnnotationRow(ctx: GraphicsContext, w: CGFloat) {
        let rowTop = rulerH + zoomH + 2
        ctx.draw(ctx.resolve(Text("ANN").font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.25))),
            at: CGPoint(x: 5, y: rowTop + 4), anchor: .topLeading)

        for (i, ann) in vm.annotations.enumerated() {
            let x1   = xFor(ann.startTime, w: w)
            let x2   = xFor(ann.startTime + ann.duration, w: w)
            let barW = max(4, x2 - x1)
            let rect = CGRect(x: x1, y: rowTop + 3, width: barW, height: annH - 6)
            let col  = annColors[i % annColors.count]
            let isSelected = ann.id == vm.selectedAnnotationID

            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(col.opacity(0.5)))

            let borderColor: Color = isSelected ? .white : col
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                       with: .color(borderColor), lineWidth: isSelected ? 1.5 : 1)

            if barW > 18 {
                let blockLabel = ann.kind == .text ? ann.text : ann.kind.rawValue
                let lbl = ctx.resolve(Text(blockLabel)
                    .font(.system(size: 9, weight: .medium)).foregroundColor(.white))
                var sub = ctx; sub.clip(to: Path(rect.insetBy(dx: 3, dy: 1)))
                sub.draw(lbl, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }

            let handleColor = isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.4)
            for hx in [x1 + 2, x2 - 2] {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: hx, y: rect.minY + 3))
                    p.addLine(to: CGPoint(x: hx, y: rect.maxY - 3))
                }, with: .color(handleColor), lineWidth: 2)
            }
        }
    }

    // MARK: - Trim overlay

    private func drawTrimOverlay(ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        guard vm.duration > 0 else { return }
        let tsX = xFor(vm.trimStart, w: w)
        let teX = xFor(vm.effectiveTrimEnd, w: w)
        let dim = Color.black.opacity(0.5)
        if tsX > 0 { ctx.fill(Path(CGRect(x: 0, y: 0, width: tsX, height: h)), with: .color(dim)) }
        if teX < w { ctx.fill(Path(CGRect(x: teX, y: 0, width: w - teX, height: h)), with: .color(dim)) }
        let oc = Color.orange
        for hx in [tsX, teX] {
            let right = hx == tsX
            ctx.fill(Path(CGRect(x: hx - 2, y: 0, width: 4, height: h)), with: .color(oc))
            let flag = CGRect(x: right ? hx : hx - 8, y: 0, width: 8, height: 14)
            ctx.fill(Path(roundedRect: flag, cornerRadius: 2), with: .color(oc))
        }
    }

    // MARK: - Playhead

    private func drawPlayhead(ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        let px = xFor(vm.currentTime, w: w)
        ctx.fill(Path { p in
            p.move(to: CGPoint(x: px - 5, y: 0))
            p.addLine(to: CGPoint(x: px + 5, y: 0))
            p.addLine(to: CGPoint(x: px, y: 8))
            p.closeSubpath()
        }, with: .color(.white))
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: px, y: 8)); p.addLine(to: CGPoint(x: px, y: h))
        }, with: .color(Color.white.opacity(0.8)), lineWidth: 1.5)
    }
}
