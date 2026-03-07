import AVKit
import SwiftUI

// MARK: - Video preview with background canvas

struct VideoPlayerView: View {
    @ObservedObject var vm: ClipForgeViewModel

    var body: some View {
        // Background determines layout size. Overlay fills that exact area so
        // the inner GeometryReader always reads a stable, pre-determined size —
        // no layout feedback is possible.
        backgroundCanvas
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay {
                if let player = vm.player {
                    GeometryReader { geo in
                        videoCard(player: player, canvas: geo.size)
                    }
                }
            }
    }

    // MARK: - Video card

    private func videoCard(player: AVPlayer, canvas: CGSize) -> some View {
        let f      = vm.backgroundSettings.paddingFraction
        let videoW = canvas.width  * (1 - 2 * f)
        let videoH = canvas.height * (1 - 2 * f)
        let zoom   = vm.currentScaleAndOffset
        let visible = vm.visibleAnnotations(at: vm.currentTime)

        return ZStack {
            PlayerLayerView(player: player)
                .scaleEffect(zoom.scale)
                .offset(x: zoom.offset.width  * videoW,
                        y: zoom.offset.height * videoH)
                .clipped()

            // Shape annotations
            ForEach(visible.filter { $0.kind != .text }) { ann in
                shapePath(ann: ann, videoW: videoW, videoH: videoH)
                    .stroke(ann.strokeColor.color, lineWidth: ann.strokeWidth)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: vm.currentTime)
            }

            // Pending shape draft (dashed preview while no annotation selected)
            if vm.selectedAnnotationID == nil, vm.pendingAnnotationKind != .text {
                shapePath(
                    kind: vm.pendingAnnotationKind,
                    start: CGPoint(x: vm.pendingAnnotationPosition.x    * videoW,
                                   y: vm.pendingAnnotationPosition.y    * videoH),
                    end:   CGPoint(x: vm.pendingAnnotationEndPosition.x * videoW,
                                   y: vm.pendingAnnotationEndPosition.y * videoH)
                )
                .stroke(
                    vm.pendingAnnotationStrokeColor.color.opacity(0.75),
                    style: StrokeStyle(lineWidth: vm.pendingAnnotationStrokeWidth, dash: [6, 4])
                )
            }

            // Text annotations
            ForEach(visible.filter { $0.kind == .text }) { ann in
                Text(ann.text)
                    .font(.system(size: max(8, ann.fontSize * videoW),
                                  weight: ann.fontWeight.swiftUIWeight))
                    .foregroundColor(ann.textColor.color)
                    .shadow(color: ann.showBackground ? .clear : .black.opacity(0.8),
                            radius: ann.showBackground ? 0 : 3, x: 1, y: 1)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, ann.showBackground ? 8 : 0)
                    .padding(.vertical,   ann.showBackground ? 4 : 0)
                    .background {
                        if ann.showBackground {
                            RoundedRectangle(cornerRadius: ann.backgroundCornerRadius)
                                .fill(ann.backgroundColor.color
                                        .opacity(ann.backgroundOpacity))
                        }
                    }
                    .position(x: ann.position.x * videoW,
                              y: ann.position.y * videoH)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: vm.currentTime)
            }

            // Placement marker — text kind only
            let showMarker = vm.pendingAnnotationKind == .text && vm.selectedAnnotationID == nil
                          || vm.selectedAnnotation?.kind == .text
            if showMarker {
                let markerPos = vm.selectedAnnotation?.position ?? vm.pendingAnnotationPosition
                AnnotationPlacementMarker(isSelected: vm.selectedAnnotationID != nil)
                    .position(x: markerPos.x * videoW, y: markerPos.y * videoH)
            }
        }
        .frame(width: videoW, height: videoH)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { v in
                    let clamp = { (p: CGPoint) in
                        CGPoint(x: (p.x / videoW).clamped(to: 0.05...0.95),
                                y: (p.y / videoH).clamped(to: 0.05...0.95))
                    }
                    if let id = vm.selectedAnnotationID,
                       vm.selectedAnnotation?.kind != .text {
                        // Live-redraw selected shape annotation
                        vm.updateAnnotation(id: id,
                            position:    clamp(v.startLocation),
                            endPosition: clamp(v.location))
                    } else if vm.selectedAnnotationID == nil,
                              vm.pendingAnnotationKind != .text {
                        // Live-preview pending shape
                        vm.pendingAnnotationPosition    = clamp(v.startLocation)
                        vm.pendingAnnotationEndPosition = clamp(v.location)
                    }
                }
                .onEnded { v in
                    let clamp = { (p: CGPoint) in
                        CGPoint(x: (p.x / videoW).clamped(to: 0.05...0.95),
                                y: (p.y / videoH).clamped(to: 0.05...0.95))
                    }
                    let loc   = clamp(v.location)
                    let start = clamp(v.startLocation)
                    if let id = vm.selectedAnnotationID {
                        if vm.selectedAnnotation?.kind == .text {
                            vm.updateAnnotation(id: id, position: loc)
                        } else {
                            vm.updateAnnotation(id: id, position: start, endPosition: loc)
                        }
                    } else if vm.pendingAnnotationKind == .text {
                        vm.pendingAnnotationPosition = loc
                    } else {
                        vm.pendingAnnotationPosition    = start
                        vm.pendingAnnotationEndPosition = loc
                    }
                }
        )
        .clipShape(RoundedRectangle(cornerRadius: vm.backgroundSettings.cornerRadius))
        .shadow(
            color: .black.opacity(Double(vm.backgroundSettings.shadowOpacity)),
            radius: vm.backgroundSettings.shadowRadius
        )
        .position(x: canvas.width / 2, y: canvas.height / 2)
    }

    // MARK: - Shape path helpers

    private func shapePath(ann: Annotation, videoW: CGFloat, videoH: CGFloat) -> Path {
        shapePath(
            kind:  ann.kind,
            start: CGPoint(x: ann.position.x    * videoW, y: ann.position.y    * videoH),
            end:   CGPoint(x: ann.endPosition.x * videoW, y: ann.endPosition.y * videoH)
        )
    }

    private func shapePath(kind: AnnotationKind, start: CGPoint, end: CGPoint) -> Path {
        switch kind {
        case .text: return Path()
        case .line:
            return Path { p in p.move(to: start); p.addLine(to: end) }
        case .rectangle:
            return Path(CGRect(x: min(start.x, end.x), y: min(start.y, end.y),
                               width: abs(end.x - start.x), height: abs(end.y - start.y)))
        case .circle:
            let r = hypot(end.x - start.x, end.y - start.y)
            return Path(ellipseIn: CGRect(x: start.x - r, y: start.y - r,
                                          width: r * 2, height: r * 2))
        }
    }

    // MARK: - Background

    @ViewBuilder
    private var backgroundCanvas: some View {
        switch vm.backgroundSettings.style {
        case .gradient:
            LinearGradient(
                colors: [vm.backgroundSettings.gradientStart.color,
                         vm.backgroundSettings.gradientEnd.color],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .solid:
            vm.backgroundSettings.solidColor.color
        case .transparent:
            Color.black
        }
    }
}

// MARK: - Annotation placement crosshair

private struct AnnotationPlacementMarker: View {
    var isSelected: Bool = false
    var body: some View {
        let c: Color = isSelected ? .cyan : .yellow
        ZStack {
            Circle().stroke(c, lineWidth: 2).frame(width: 22, height: 22)
            Circle().fill(c.opacity(0.25)).frame(width: 22, height: 22)
            Rectangle().fill(c).frame(width: 12, height: 1.5)
            Rectangle().fill(c).frame(width: 1.5, height: 12)
        }
        .shadow(color: .black.opacity(0.6), radius: 2)
    }
}

// MARK: - Platform AVPlayerLayer wrappers

#if canImport(UIKit)
import UIKit

struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> PlayerUIView {
        let v = PlayerUIView(); v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect; return v
    }
    func updateUIView(_ uiView: PlayerUIView, context: Context) { uiView.playerLayer.player = player }
}

final class PlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        // Disable implicit CALayer animations so the player layer snaps to its
        // new frame instantly instead of animating — prevents "drunken" movement
        // when SwiftUI resizes this view (e.g. while dragging the padding slider).
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}

#elseif canImport(AppKit)
import AppKit

struct PlayerLayerView: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> PlayerNSView {
        let v = PlayerNSView(); v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect; return v
    }
    func updateNSView(_ nsView: PlayerNSView, context: Context) { nsView.playerLayer.player = player }
}

final class PlayerNSView: NSView {
    let playerLayer = AVPlayerLayer()
    override init(frame: NSRect) {
        super.init(frame: frame); wantsLayer = true; layer?.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }
}
#endif
