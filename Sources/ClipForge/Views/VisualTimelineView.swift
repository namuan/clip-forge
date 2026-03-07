import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct VisualTimelineView: View {
    @ObservedObject var vm: ClipForgeViewModel

    #if canImport(AppKit)
    @State private var keyMonitor: Any?
    #endif

    private let rulerH: CGFloat      = 22
    private let zoomH: CGFloat       = 44
    private let annLaneSlot: CGFloat = 30

    private let annColors: [Color] = [.blue, .purple, .green, .orange, .pink, .teal]

    // ── Zoom / pan state ────────────────────────────────────────────────────────
    @State private var timelineZoom: CGFloat   = 1.0   // 1 = whole duration fits
    @State private var timelineOffset: Double  = 0     // seconds at left edge
    @State private var dragStartOffset: Double = 0     // captured at pan-drag start
    @State private var magnifyBase: CGFloat    = 1.0   // captured at magnify start

    // ── Lane assignment ──────────────────────────────────────────────────────────
    private var lanedAnnotations: [(Annotation, Int)] {
        let sorted = vm.annotations.sorted { $0.startTime < $1.startTime }
        var result: [(Annotation, Int)] = []
        var laneEndTimes: [Double] = []
        for ann in sorted {
            let idx = laneEndTimes.firstIndex(where: { $0 <= ann.startTime }) ?? laneEndTimes.count
            if idx == laneEndTimes.count { laneEndTimes.append(ann.startTime + ann.duration) }
            else { laneEndTimes[idx] = ann.startTime + ann.duration }
            result.append((ann, idx))
        }
        return result
    }

    private var laneCount: Int      { max(1, (lanedAnnotations.map { $0.1 }.max() ?? 0) + 1) }
    private var annH: CGFloat       { CGFloat(laneCount) * annLaneSlot + 6 }
    private var totalH: CGFloat     { rulerH + zoomH + annH + 2 }
    private var visibleDuration: Double { vm.duration / Double(timelineZoom) }

    // Fraction [0,1] of where the playhead sits in the current visible window
    private var playheadFraction: Double {
        guard visibleDuration > 0 else { return 0.5 }
        return ((vm.currentTime - timelineOffset) / visibleDuration).clamped(to: 0...1)
    }

    // ── Drag state ───────────────────────────────────────────────────────────────
    private enum DragTarget: Equatable {
        case pan
        case playhead
        case trimStart, trimEnd
        case segmentBody(UUID), segmentLeft(UUID), segmentRight(UUID)
        case annotationBody(UUID), annotationLeft(UUID), annotationRight(UUID)
    }

    @State private var dragTarget: DragTarget       = .playhead
    @State private var dragSegmentStartTime: Double = 0
    @State private var dragSegmentDuration: Double  = 0
    @State private var dragStartX: CGFloat          = 0

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {

            // ── Zoom controls ─────────────────────────────────────────────────
            HStack(spacing: 6) {
                Spacer()
                Button { applyZoom(timelineZoom / 2, anchorFraction: playheadFraction) } label: {
                    Image(systemName: "minus.magnifyingglass")
                }
                .buttonStyle(.borderless)
                .disabled(timelineZoom <= 1)

                Text(timelineZoom > 1.05 ? String(format: "%.0f×", timelineZoom) : "Fit")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 30, alignment: .center)

                Button { applyZoom(timelineZoom * 2, anchorFraction: playheadFraction) } label: {
                    Image(systemName: "plus.magnifyingglass")
                }
                .buttonStyle(.borderless)

                if timelineZoom > 1.05 {
                    Button { applyZoom(1) } label: {
                        Image(systemName: "arrow.uturn.left")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)

            // ── Selection hint ────────────────────────────────────────────────
            selectionHint

            // ── Timeline canvas ───────────────────────────────────────────────
            GeometryReader { geo in
                let w = geo.size.width

                ZStack(alignment: .topLeading) {
                    Canvas { ctx, size in
                        guard vm.duration > 0 else { return }
                        drawRuler(ctx: ctx, w: size.width, h: size.height)
                        drawZoomRow(ctx: ctx, w: size.width)
                        drawAnnotationRow(ctx: ctx, w: size.width)
                        drawTrimOverlay(ctx: ctx, w: size.width, h: size.height)
                        drawPlayhead(ctx: ctx, w: size.width, h: size.height)
                    }

                    // ── Per-block context menus ────────────────────────────────
                    if vm.duration > 0 {
                        ForEach(vm.segments) { seg in
                            let rawX  = xFor(seg.startTime, w: w)
                            let rawX2 = xFor(seg.endTime,   w: w)
                            let visX  = max(0, rawX)
                            let visW  = max(4, min(w, rawX2) - visX)
                            if rawX2 > 0 && rawX < w {
                                Color.clear
                                    .frame(width: visW, height: zoomH)
                                    .offset(x: visX, y: rulerH + 1)
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
                        }

                        let laned = lanedAnnotations
                        ForEach(vm.annotations) { ann in
                            let lane  = laned.first(where: { $0.0.id == ann.id })?.1 ?? 0
                            let rawX  = xFor(ann.startTime, w: w)
                            let rawX2 = xFor(ann.startTime + ann.duration, w: w)
                            let visX  = max(0, rawX)
                            let visW  = max(4, min(w, rawX2) - visX)
                            let laneY = CGFloat(lane) * annLaneSlot
                            if rawX2 > 0 && rawX < w {
                                Color.clear
                                    .frame(width: visW, height: annLaneSlot - 4)
                                    .offset(x: visX, y: rulerH + zoomH + 3 + laneY)
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
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            guard vm.duration > 0 else { return }
                            if v.translation == .zero {
                                dragTarget      = pickTarget(x: v.startLocation.x,
                                                             y: v.startLocation.y, w: w)
                                dragStartX      = v.startLocation.x
                                dragStartOffset = timelineOffset
                                switch dragTarget {
                                case .segmentBody(let id), .segmentLeft(let id):
                                    if let s = vm.segments.first(where: { $0.id == id }) {
                                        dragSegmentStartTime = s.startTime
                                        dragSegmentDuration  = s.duration
                                    }
                                case .segmentRight(let id):
                                    if let s = vm.segments.first(where: { $0.id == id }) {
                                        dragSegmentDuration = s.duration
                                    }
                                case .annotationBody(let id), .annotationLeft(let id):
                                    if let a = vm.annotations.first(where: { $0.id == id }) {
                                        dragSegmentStartTime = a.startTime
                                        dragSegmentDuration  = a.duration
                                    }
                                case .annotationRight(let id):
                                    if let a = vm.annotations.first(where: { $0.id == id }) {
                                        dragSegmentDuration = a.duration
                                    }
                                default: break
                                }
                            }

                            let t  = timeForX(v.location.x, w: w)
                            let dt = Double((v.location.x - dragStartX) / w) * visibleDuration

                            switch dragTarget {
                            case .pan:
                                timelineOffset = (dragStartOffset - dt)
                                    .clamped(to: 0...max(0, vm.duration - visibleDuration))

                            case .playhead:
                                vm.seek(to: t); vm.currentTime = t

                            case .trimStart:
                                vm.trimStart = min(t, vm.effectiveTrimEnd - 0.1)

                            case .trimEnd:
                                let c = max(t, vm.trimStart + 0.1)
                                vm.trimEnd = c >= vm.duration - 0.01 ? nil : c

                            case .segmentBody(let id):
                                vm.updateSegment(id: id,
                                    startTime: (dragSegmentStartTime + dt)
                                        .clamped(to: 0...(vm.duration - dragSegmentDuration)))

                            case .segmentLeft(let id):
                                let newStart = (dragSegmentStartTime + dt)
                                    .clamped(to: 0...(dragSegmentStartTime + dragSegmentDuration - 0.3))
                                vm.updateSegment(id: id, startTime: newStart,
                                                 duration: dragSegmentDuration - (newStart - dragSegmentStartTime))

                            case .segmentRight(let id):
                                guard let seg = vm.segments.first(where: { $0.id == id }) else { break }
                                vm.updateSegment(id: id,
                                    duration: (t - seg.startTime).clamped(to: 0.3...vm.duration))

                            case .annotationBody(let id):
                                vm.updateAnnotation(id: id,
                                    startTime: (dragSegmentStartTime + dt)
                                        .clamped(to: 0...(vm.duration - dragSegmentDuration)))

                            case .annotationLeft(let id):
                                let newStart = (dragSegmentStartTime + dt)
                                    .clamped(to: 0...(dragSegmentStartTime + dragSegmentDuration - 0.3))
                                vm.updateAnnotation(id: id, startTime: newStart,
                                                    duration: dragSegmentDuration - (newStart - dragSegmentStartTime))

                            case .annotationRight(let id):
                                guard let ann = vm.annotations.first(where: { $0.id == id }) else { break }
                                vm.updateAnnotation(id: id,
                                    duration: (t - ann.startTime).clamped(to: 0.3...vm.duration))
                            }
                        }
                        .onEnded { v in
                            let moved = v.translation.width.magnitude + v.translation.height.magnitude
                            if moved < 6 {
                                let tapT = timeForX(v.startLocation.x, w: w)
                                let canCreateFromClick = isCreationModifierPressed()
                                if isInZoomRow(y: v.startLocation.y) {
                                    if let hit = segmentAt(time: tapT) {
                                        vm.selectedSegmentID = hit.id
                                        vm.selectedAnnotationID = nil
                                    } else if canCreateFromClick {
                                        vm.addZoomSegment(at: tapT)
                                    }
                                } else if isInAnnotationRow(y: v.startLocation.y) {
                                    if let hit = annotationAt(x: v.startLocation.x,
                                                              y: v.startLocation.y, w: w) {
                                        vm.selectedAnnotationID = hit.id
                                        vm.selectedSegmentID = nil
                                    } else if canCreateFromClick {
                                        vm.addAnnotationSegment(at: tapT)
                                    }
                                }
                            }
                            dragTarget = .playhead
                        }
                )
                .simultaneousGesture(
                    MagnificationGesture()
                        .onChanged { scale in applyZoom(magnifyBase * scale) }
                        .onEnded   { _     in magnifyBase = timelineZoom }
                )
            }
            .frame(height: totalH)
            .background(Color(red: 0.11, green: 0.12, blue: 0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.14), lineWidth: 1))
            .padding(.horizontal)
        }
        #if canImport(AppKit)
        .onAppear  { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        #endif
    }

    // MARK: - Selection hint

    @ViewBuilder
    private var selectionHint: some View {
        if let ann = vm.selectedAnnotation {
            selectionBar(
                color: .blue,
                icon: ann.kind.systemImage,
                label: ann.kind == .text
                    ? (ann.text.isEmpty ? "Text annotation" : "\"\(ann.text)\"")
                    : ann.kind.rawValue
            )
        } else if let seg = vm.segments.first(where: { $0.id == vm.selectedSegmentID }) {
            selectionBar(
                color: .purple,
                icon: "magnifyingglass",
                label: String(format: "%.1f× zoom segment", seg.scale)
            )
        }
    }

    private func selectionBar(color: Color, icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text("Delete to remove")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(color.opacity(0.3), lineWidth: 0.5))
        .padding(.horizontal)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .animation(.easeInOut(duration: 0.15), value: vm.selectedAnnotationID)
        .animation(.easeInOut(duration: 0.15), value: vm.selectedSegmentID)
    }

    // MARK: - Delete key

    #if canImport(AppKit)
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }
            // Delete (51) or Forward-delete (117)
            guard event.keyCode == 51 || event.keyCode == 117 else { return event }
            if let id = vm.selectedAnnotationID {
                vm.removeAnnotation(id: id)
                return nil
            }
            if let id = vm.selectedSegmentID {
                vm.removeSegment(id: id)
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
    #endif

    // MARK: - Zoom

    private func applyZoom(_ newZoom: CGFloat, anchorFraction: Double = 0.5) {
        guard vm.duration > 0 else { return }
        let clamped    = newZoom.clamped(to: 1...64)
        let anchorTime = timelineOffset + anchorFraction * visibleDuration
        let newVD      = vm.duration / Double(clamped)
        timelineZoom   = clamped
        timelineOffset = (anchorTime - anchorFraction * newVD)
            .clamped(to: 0...max(0, vm.duration - newVD))
    }

    // MARK: - Coordinate helpers

    private func xFor(_ time: Double, w: CGFloat) -> CGFloat {
        guard vm.duration > 0 else { return 0 }
        return CGFloat((time - timelineOffset) / visibleDuration) * w
    }

    private func timeForX(_ x: CGFloat, w: CGFloat) -> Double {
        (timelineOffset + Double(x / w) * visibleDuration).clamped(to: 0...vm.duration)
    }

    private func niceStep(w: CGFloat) -> Double {
        let raw = visibleDuration / (Double(w) / 60)
        for c in [0.1, 0.25, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600] {
            if c >= raw { return c }
        }
        return raw
    }

    private func formatTime(_ t: Double) -> String {
        let t = max(0, t)
        let m = Int(t) / 60; let s = Int(t) % 60
        if visibleDuration < 60 {
            return String(format: "%d:%02d.%d", m, s, Int(t.truncatingRemainder(dividingBy: 1) * 10))
        }
        return String(format: "%d:%02d", m, s)
    }

    private func isCreationModifierPressed() -> Bool {
        #if canImport(AppKit)
        NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.option)
        #else
        false
        #endif
    }

    // MARK: - Hit testing

    private func isInZoomRow(y: CGFloat) -> Bool       { y >= rulerH && y <= rulerH + zoomH }
    private func isInAnnotationRow(y: CGFloat) -> Bool { y >= rulerH + zoomH && y <= rulerH + zoomH + annH }

    private func segmentAt(time: Double) -> ZoomSegment? {
        vm.segments.first { time >= $0.startTime && time <= $0.endTime }
    }

    private func annotationAt(x: CGFloat, y: CGFloat, w: CGFloat) -> Annotation? {
        let tapLane = Int((y - (rulerH + zoomH + 2)) / annLaneSlot)
        return lanedAnnotations.first(where: { ann, lane in
            lane == tapLane &&
            x >= xFor(ann.startTime, w: w) &&
            x <= xFor(ann.startTime + ann.duration, w: w)
        })?.0
    }

    private func pickTarget(x: CGFloat, y: CGFloat, w: CGFloat) -> DragTarget {
        guard vm.duration > 0 else { return .playhead }
        let tsX = xFor(vm.trimStart, w: w)
        let teX = xFor(vm.effectiveTrimEnd, w: w)
        let phX = xFor(vm.currentTime, w: w)
        let hit: CGFloat = 12

        if abs(x - tsX) <= hit { return .trimStart }
        if abs(x - teX) <= hit { return .trimEnd   }

        // Ruler: scrub playhead or pan
        if y < rulerH {
            return abs(x - phX) <= hit ? .playhead : .pan
        }

        if isInZoomRow(y: y) {
            let eh: CGFloat = 10
            for seg in vm.segments {
                let sx = xFor(seg.startTime, w: w); let ex = xFor(seg.endTime, w: w)
                if abs(x - sx) <= eh { return .segmentLeft(seg.id)  }
                if abs(x - ex) <= eh { return .segmentRight(seg.id) }
                if x >= sx && x <= ex { return .segmentBody(seg.id) }
            }
        }

        if isInAnnotationRow(y: y) {
            let tapLane = Int((y - (rulerH + zoomH + 2)) / annLaneSlot)
            let eh: CGFloat = 10
            for (ann, lane) in lanedAnnotations {
                guard lane == tapLane else { continue }
                let ax = xFor(ann.startTime, w: w); let ex = xFor(ann.startTime + ann.duration, w: w)
                if abs(x - ax) <= eh { return .annotationLeft(ann.id)  }
                if abs(x - ex) <= eh { return .annotationRight(ann.id) }
                if x >= ax && x <= ex { return .annotationBody(ann.id) }
            }
        }

        if abs(x - phX) <= hit { return .playhead }
        return .playhead
    }

    // MARK: - Ruler

    private func drawRuler(ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: rulerH)),
                 with: .color(Color(red: 0.17, green: 0.18, blue: 0.21)))

        let majorStep = niceStep(w: w)
        let minorStep = majorStep / 5
        var t = floor(timelineOffset / minorStep) * minorStep

        while t <= timelineOffset + visibleDuration + minorStep * 0.5 {
            defer { t += minorStep }
            guard t >= -minorStep * 0.1 else { continue }
            let px = xFor(t, w: w)
            guard px >= -1 && px <= w + 1 else { continue }

            let rem     = t.truncatingRemainder(dividingBy: majorStep)
            let isMajor = abs(rem) < minorStep * 0.4 || abs(rem - majorStep) < minorStep * 0.4

            if isMajor {
                // Major tick
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: rulerH - 8))
                    p.addLine(to: CGPoint(x: px, y: rulerH))
                }, with: .color(Color.white.opacity(0.6)), lineWidth: 1)

                // Vertical grid line through all rows
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: rulerH))
                    p.addLine(to: CGPoint(x: px, y: h))
                }, with: .color(Color.white.opacity(0.08)), lineWidth: 0.5)

                // Label
                let clampedT = min(max(t, 0), vm.duration)
                ctx.draw(ctx.resolve(
                    Text(formatTime(clampedT))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.75))),
                    at: CGPoint(x: px + 3, y: rulerH - 10), anchor: .bottomLeading)
            } else {
                // Minor tick
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: px, y: rulerH - 4))
                    p.addLine(to: CGPoint(x: px, y: rulerH))
                }, with: .color(Color.white.opacity(0.35)), lineWidth: 0.5)
            }
        }

        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 0, y: rulerH)); p.addLine(to: CGPoint(x: w, y: rulerH))
        }, with: .color(Color.white.opacity(0.16)), lineWidth: 0.5)
    }

    // MARK: - Zoom row

    private func drawZoomRow(ctx: GraphicsContext, w: CGFloat) {
        let rowTop = rulerH + 1
        ctx.draw(ctx.resolve(Text("ZOOM").font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.72))),
            at: CGPoint(x: 5, y: rowTop + 4), anchor: .topLeading)

        for seg in vm.segments {
            let segX  = xFor(seg.startTime, w: w)
            let segX2 = xFor(seg.endTime,   w: w)
            let segW  = max(4, segX2 - segX)
            let isSelected = seg.id == vm.selectedSegmentID
            let isDisabled = !seg.isEnabled
            let blockRect  = CGRect(x: segX, y: rowTop + 3, width: segW, height: zoomH - 6)

            ctx.fill(Path(roundedRect: blockRect, cornerRadius: 4),
                     with: .color(isDisabled ? Color.purple.opacity(0.25) : Color.purple.opacity(0.6)))

            for (easeW, fromLeft) in [
                (CGFloat(seg.easeIn  / seg.duration) * segW, true),
                (CGFloat(seg.easeOut / seg.duration) * segW, false)
            ] where easeW > 0 && segW > 8 {
                let r = CGRect(x: fromLeft ? segX : segX2 - easeW,
                               y: blockRect.minY, width: easeW, height: blockRect.height)
                var fc = ctx; fc.clip(to: Path(roundedRect: blockRect, cornerRadius: 4))
                fc.fill(Path(r), with: .color(Color.white.opacity(0.12)))
            }

            let borderColor: Color = isSelected ? .white
                : (isDisabled ? Color.white.opacity(0.1) : Color.purple.opacity(0.9))
            ctx.stroke(Path(roundedRect: blockRect, cornerRadius: 4),
                       with: .color(borderColor), lineWidth: isSelected ? 1.5 : 1)

            if segW > 28 {
                let lbl = isDisabled
                    ? ctx.resolve(Text("off").font(.system(size: 9)).foregroundColor(Color.white.opacity(0.4)))
                    : ctx.resolve(Text(String(format: "%.1f×", seg.scale))
                        .font(.system(size: 9, weight: .semibold)).foregroundColor(.white))
                var sub = ctx; sub.clip(to: Path(blockRect.insetBy(dx: 3, dy: 0)))
                sub.draw(lbl, at: CGPoint(x: blockRect.midX, y: blockRect.midY), anchor: .center)
            }

            let hc = isSelected ? Color.white.opacity(0.9) : Color.white.opacity(0.4)
            for hx in [segX + 2, segX2 - 2] {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: hx, y: blockRect.minY + 4))
                    p.addLine(to: CGPoint(x: hx, y: blockRect.maxY - 4))
                }, with: .color(hc), lineWidth: 2)
            }
        }

        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: 0, y: rowTop + zoomH)); p.addLine(to: CGPoint(x: w, y: rowTop + zoomH))
        }, with: .color(Color.white.opacity(0.16)), lineWidth: 0.5)
    }

    // MARK: - Annotation row

    private func drawAnnotationRow(ctx: GraphicsContext, w: CGFloat) {
        let rowTop = rulerH + zoomH + 2
        let blockH = annLaneSlot - 4
        ctx.draw(ctx.resolve(Text("ANN").font(.system(size: 8, weight: .semibold))
            .foregroundColor(Color.white.opacity(0.72))),
            at: CGPoint(x: 5, y: rowTop + 4), anchor: .topLeading)

        for (i, (ann, lane)) in lanedAnnotations.enumerated() {
            let x1    = xFor(ann.startTime, w: w)
            let x2    = xFor(ann.startTime + ann.duration, w: w)
            let barW  = max(4, x2 - x1)
            let laneY = CGFloat(lane) * annLaneSlot
            let rect  = CGRect(x: x1, y: rowTop + 3 + laneY, width: barW, height: blockH)
            let col   = annColors[i % annColors.count]
            let isSel = ann.id == vm.selectedAnnotationID

            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(col.opacity(0.5)))
            ctx.stroke(Path(roundedRect: rect, cornerRadius: 3),
                       with: .color(isSel ? .white : col), lineWidth: isSel ? 1.5 : 1)

            if barW > 18 {
                let label = ann.kind == .text ? ann.text : ann.kind.rawValue
                let lbl = ctx.resolve(Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(.white))
                var sub = ctx; sub.clip(to: Path(rect.insetBy(dx: 3, dy: 1)))
                sub.draw(lbl, at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
            }

            let hc = isSel ? Color.white.opacity(0.9) : Color.white.opacity(0.4)
            for hx in [x1 + 2, x2 - 2] {
                ctx.stroke(Path { p in
                    p.move(to: CGPoint(x: hx, y: rect.minY + 3))
                    p.addLine(to: CGPoint(x: hx, y: rect.maxY - 3))
                }, with: .color(hc), lineWidth: 2)
            }
        }
    }

    // MARK: - Trim overlay

    private func drawTrimOverlay(ctx: GraphicsContext, w: CGFloat, h: CGFloat) {
        guard vm.duration > 0 else { return }
        let tsX = xFor(vm.trimStart, w: w)
        let teX = xFor(vm.effectiveTrimEnd, w: w)
        let dim = Color.black.opacity(0.18)
        if tsX > 0 { ctx.fill(Path(CGRect(x: 0,   y: 0, width: max(0, tsX),    height: h)), with: .color(dim)) }
        if teX < w { ctx.fill(Path(CGRect(x: teX, y: 0, width: max(0, w - teX), height: h)), with: .color(dim)) }
        for hx in [tsX, teX] {
            let right = hx == tsX
            ctx.fill(Path(CGRect(x: hx - 2, y: 0, width: 4, height: h)), with: .color(.orange))
            ctx.fill(Path(roundedRect: CGRect(x: right ? hx : hx - 8, y: 0, width: 8, height: 14),
                          cornerRadius: 2), with: .color(.orange))
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
        }, with: .color(.red))
        ctx.stroke(Path { p in
            p.move(to: CGPoint(x: px, y: 8)); p.addLine(to: CGPoint(x: px, y: h))
        }, with: .color(Color.red.opacity(0.8)), lineWidth: 1.5)
    }
}
