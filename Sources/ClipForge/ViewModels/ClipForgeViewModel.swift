import AVFoundation
import Combine
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
final class ClipForgeViewModel: ObservableObject {

    // MARK: - Player state
    @Published var player: AVPlayer?
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false

    // MARK: - Zoom segments & annotations
    @Published var segments: [ZoomSegment] = []
    @Published var selectedSegmentID: UUID? = nil
    @Published var annotations: [Annotation] = []

    // MARK: - Annotation selection
    @Published var selectedAnnotationID: UUID? = nil

    var selectedAnnotation: Annotation? {
        annotations.first { $0.id == selectedAnnotationID }
    }

    // MARK: - Pending annotation controls
    @Published var pendingAnnotationKind: AnnotationKind = .text
    @Published var pendingAnnotationText: String = ""
    @Published var pendingAnnotationDuration: Double = 3.0
    @Published var pendingAnnotationPosition: CGPoint    = CGPoint(x: 0.25, y: 0.5)
    @Published var pendingAnnotationEndPosition: CGPoint = CGPoint(x: 0.75, y: 0.5)
    @Published var pendingAnnotationStrokeColor: CodableColor = .init(red: 1, green: 1, blue: 1)
    @Published var pendingAnnotationStrokeWidth: CGFloat = 3

    // MARK: - Canvas / background
    @Published var backgroundSettings: BackgroundSettings = BackgroundSettings()

    // MARK: - Clip
    @Published var trimStart: Double = 0
    @Published var trimEnd: Double? = nil
    @Published var playbackSpeed: Double = 1.0

    var effectiveTrimEnd: Double { trimEnd ?? duration }

    var selectedSegment: ZoomSegment? {
        get { segments.first { $0.id == selectedSegmentID } }
    }

    // MARK: - Export state
    @Published var isExporting: Bool = false
    @Published var exportURL: URL?
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false

    // MARK: - Internal
    private var asset: AVURLAsset?
    private var timeObserverToken: Any?
    private var playerItemCancellable: AnyCancellable?

    // MARK: - Video loading

    func loadVideo(url: URL) {
        cleanupPlayer()
        trimStart = 0; trimEnd = nil; playbackSpeed = 1.0

        let asset = AVURLAsset(url: url)
        self.asset = asset
        let item = AVPlayerItem(asset: asset)
        let player = AVPlayer(playerItem: item)
        self.player = player

        playerItemCancellable = item.publisher(for: \.status)
            .sink { [weak self] status in
                guard let self, status == .readyToPlay else { return }
                Task { @MainActor in
                    let d = try? await asset.load(.duration)
                    self.duration = d.map { CMTimeGetSeconds($0) } ?? 0
                }
            }

        let interval = CMTime(value: 1, timescale: 30)
        timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            let t = CMTimeGetSeconds(time)
            if !t.isNaN {
                MainActor.assumeIsolated {
                    self.currentTime = t
                    if t >= self.effectiveTrimEnd - 0.01 && self.isPlaying {
                        self.player?.pause(); self.isPlaying = false
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime, object: item)
        player.play(); isPlaying = true
    }

    @objc private func playerDidFinish() { isPlaying = false }

    // MARK: - Playback

    func togglePlayPause() {
        guard let player else { return }
        if isPlaying {
            player.pause(); isPlaying = false
        } else {
            if currentTime >= effectiveTrimEnd - 0.05 { seek(to: trimStart) }
            player.rate = Float(playbackSpeed); isPlaying = true
        }
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private let frameDuration = 1.0 / 30.0
    func stepForward() { let t = min(currentTime + frameDuration, effectiveTrimEnd); currentTime = t; seek(to: t) }
    func stepBack()    { let t = max(currentTime - frameDuration, trimStart);        currentTime = t; seek(to: t) }

    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying { player?.rate = Float(speed) }
    }

    // MARK: - Zoom segments

    func addZoomSegment(at time: Double? = nil) {
        let t = (time ?? currentTime).clamped(to: 0...max(0, duration - 2))
        let seg = ZoomSegment(startTime: t)
        segments.append(seg)
        segments.sort { $0.startTime < $1.startTime }
        selectedSegmentID = seg.id
    }

    func updateSegment(id: UUID, scale: CGFloat? = nil, center: CGPoint? = nil,
                       easeIn: Double? = nil, easeOut: Double? = nil,
                       startTime: Double? = nil, duration: Double? = nil) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        var s = segments[idx]
        if let v = scale     { s.scale = v }
        if let v = center    { s.center = v }
        if let v = startTime { s.startTime = max(0, v) }
        if let v = duration  { s.duration = max(0.3, v) }
        // Clamp easeIn/easeOut so they don't exceed half the duration
        let d = duration ?? s.duration
        if let v = easeIn  { s.easeIn  = max(0, min(v, d / 2)) }
        if let v = easeOut { s.easeOut = max(0, min(v, d / 2)) }
        segments[idx] = s
    }

    func toggleSegmentEnabled(id: UUID) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[idx].isEnabled.toggle()
    }

    func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
        if selectedSegmentID == id { selectedSegmentID = nil }
    }

    func removeSegment(at offsets: IndexSet) {
        let ids = offsets.map { segments[$0].id }
        segments.remove(atOffsets: offsets)
        if let sid = selectedSegmentID, ids.contains(sid) { selectedSegmentID = nil }
    }

    // MARK: - Annotations

    func addAnnotation() {
        if pendingAnnotationKind == .text {
            guard !pendingAnnotationText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        }
        let ann = Annotation(
            id: UUID(), kind: pendingAnnotationKind,
            text: pendingAnnotationText,
            startTime: currentTime, duration: pendingAnnotationDuration,
            position: pendingAnnotationPosition,
            endPosition: pendingAnnotationEndPosition,
            strokeColor: pendingAnnotationStrokeColor,
            strokeWidth: pendingAnnotationStrokeWidth)
        annotations.append(ann)
        pendingAnnotationText = ""
        selectedAnnotationID = ann.id
    }

    func addAnnotationSegment(at time: Double? = nil) {
        let t = (time ?? currentTime).clamped(to: 0...max(0, duration))
        let label = pendingAnnotationKind == .text ? "Annotation" : pendingAnnotationKind.rawValue
        let ann = Annotation(
            id: UUID(), kind: pendingAnnotationKind,
            text: label,
            startTime: t, duration: pendingAnnotationDuration,
            position: pendingAnnotationPosition,
            endPosition: pendingAnnotationEndPosition,
            strokeColor: pendingAnnotationStrokeColor,
            strokeWidth: pendingAnnotationStrokeWidth)
        annotations.append(ann)
        selectedAnnotationID = ann.id
    }

    func updateAnnotation(id: UUID, text: String? = nil, startTime: Double? = nil,
                          duration: Double? = nil, position: CGPoint? = nil,
                          endPosition: CGPoint? = nil,
                          strokeColor: CodableColor? = nil, strokeWidth: CGFloat? = nil) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if let v = text        { annotations[idx].text        = v }
        if let v = startTime   { annotations[idx].startTime   = max(0, v) }
        if let v = duration    { annotations[idx].duration    = max(0.3, v) }
        if let v = position    { annotations[idx].position    = v }
        if let v = endPosition { annotations[idx].endPosition = v }
        if let v = strokeColor { annotations[idx].strokeColor = v }
        if let v = strokeWidth { annotations[idx].strokeWidth = v }
    }

    func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id { selectedAnnotationID = nil }
    }

    func deleteAnnotations(at offsets: IndexSet) {
        let ids = offsets.map { annotations[$0].id }
        annotations.remove(atOffsets: offsets)
        if let sid = selectedAnnotationID, ids.contains(sid) { selectedAnnotationID = nil }
    }

    // MARK: - Live zoom preview

    var currentScaleAndOffset: (scale: CGFloat, offset: CGSize) {
        let t = currentTime
        let active = segments.filter { $0.isEnabled && t >= $0.startTime && t <= $0.endTime }
        guard let seg = active.first else { return (1, .zero) }
        let (scale, center) = seg.interpolated(localT: t - seg.startTime)
        return (scale, offsetFromCenter(center, scale: scale))
    }

    func offsetFromCenter(_ center: CGPoint, scale: CGFloat) -> CGSize {
        CGSize(width:  (0.5 - center.x) * (scale - 1),
               height: (0.5 - center.y) * (scale - 1))
    }

    // MARK: - Visible annotations

    func visibleAnnotations(at time: Double) -> [Annotation] {
        annotations.filter { time >= $0.startTime && time <= $0.startTime + $0.duration }
    }

    // MARK: - Export

    func exportVideo() {
        guard let asset else { showError("No video loaded."); return }
        guard !isExporting else { return }
        isExporting = true

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        let segs = segments; let anns = annotations
        let bg = backgroundSettings
        let ts = trimStart; let te = effectiveTrimEnd; let spd = playbackSpeed

        Task {
            do {
                try await ClipForge.exportVideo(
                    asset: asset, segments: segs, annotations: anns,
                    background: bg, trimStart: ts, trimEnd: te, speed: spd,
                    outputURL: outURL)
                await MainActor.run { self.exportURL = outURL; self.isExporting = false }
            } catch {
                await MainActor.run { self.isExporting = false; self.showError(error.localizedDescription) }
            }
        }
    }

    func showError(_ msg: String) { alertMessage = msg; showAlert = true }

    // MARK: - Cleanup

    private func cleanupPlayer() {
        if let token = timeObserverToken { player?.removeTimeObserver(token); timeObserverToken = nil }
        player?.pause(); player = nil
        playerItemCancellable = nil
        NotificationCenter.default.removeObserver(self)
    }

    deinit {}
}
