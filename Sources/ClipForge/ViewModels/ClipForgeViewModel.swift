import AVFoundation
import Combine
import CoreGraphics
import Foundation
import SwiftUI

enum ExportQualityOption: String, CaseIterable, Identifiable, Sendable {
    case p480
    case p720
    case p1080
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .p480:    return "480p"
        case .p720:    return "720p"
        case .p1080:   return "1080p"
        case .original:return "Best"
        }
    }

    var subtitle: String {
        switch self {
        case .p480:    return "640 × 480"
        case .p720:    return "1280 × 720"
        case .p1080:   return "1920 × 1080"
        case .original:return "Highest quality"
        }
    }

    var presetName: String {
        switch self {
        case .p480:    return AVAssetExportPreset640x480
        case .p720:    return AVAssetExportPreset1280x720
        case .p1080:   return AVAssetExportPreset1920x1080
        case .original:return AVAssetExportPresetHighestQuality
        }
    }
}

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
    @Published var pendingArrowHeadSize: CGFloat = 4.0
    @Published var pendingArrowHeadAngle: CGFloat = 26
    @Published var pendingArrowDoubleHeaded: Bool = false
    @Published var pendingArrowFilled: Bool = false

    // Pending text styling
    @Published var pendingTextColor: CodableColor         = .init(red: 1, green: 1, blue: 1)
    @Published var pendingFontSize: CGFloat               = 0.03
    @Published var pendingFontWeight: TextFontWeight      = .bold
    @Published var pendingShowBackground: Bool            = false
    @Published var pendingBackgroundColor: CodableColor   = .init(red: 0, green: 0, blue: 0)
    @Published var pendingBackgroundOpacity: Double       = 0.6
    @Published var pendingBackgroundCornerRadius: CGFloat = 6

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

    // MARK: - Project state
    @Published var currentProjectURL: URL? = nil
    @Published var projectName: String = ""
    @Published var hasUnsavedChanges: Bool = false
    @Published var recentProjects: [RecentProject] = []
    /// Original filename of the source video (preserved across temp copies)
    private(set) var videoOriginalName: String = ""

    private static let recentsKey = "recentProjects"
    private static let maxRecents = 10

    // MARK: - Export state
    @Published var isExporting: Bool = false
    @Published var exportURL: URL?
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false

    // MARK: - Internal
    private var asset: AVURLAsset?
    private var timeObserverToken: Any?
    private var playerItemCancellable: AnyCancellable?

    // MARK: - Init

    init() { loadRecents() }

    // MARK: - Recent projects

    private func loadRecents() {
        guard let data = UserDefaults.standard.data(forKey: Self.recentsKey),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data)
        else { return }
        // Filter to entries whose file still exists on disk
        recentProjects = decoded.filter {
            FileManager.default.fileExists(atPath: $0.projectFileURL.path)
        }
    }

    private func persistRecents() {
        guard let data = try? JSONEncoder().encode(recentProjects) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentsKey)
    }

    func addToRecents(name: String, projectFileURL: URL) {
        recentProjects.removeAll { $0.projectFileURL == projectFileURL }
        recentProjects.insert(
            RecentProject(id: UUID(), name: name, projectFileURL: projectFileURL, lastOpened: Date()),
            at: 0)
        if recentProjects.count > Self.maxRecents {
            recentProjects = Array(recentProjects.prefix(Self.maxRecents))
        }
        persistRecents()
    }

    func removeFromRecents(id: UUID) {
        recentProjects.removeAll { $0.id == id }
        persistRecents()
    }

    func deleteProject(_ recent: RecentProject) throws {
        let fm = FileManager.default
        let projectFileURL = recent.projectFileURL

        if fm.fileExists(atPath: projectFileURL.path) {
            if shouldDeleteProjectDirectory(for: projectFileURL) {
                try fm.removeItem(at: projectFileURL.deletingLastPathComponent())
            } else {
                try fm.removeItem(at: projectFileURL)
            }
        }

        recentProjects.removeAll {
            $0.id == recent.id || $0.projectFileURL == recent.projectFileURL
        }
        persistRecents()
    }

    private func shouldDeleteProjectDirectory(for projectFileURL: URL) -> Bool {
        guard projectFileURL.lastPathComponent == ClipForgeProject.fileName else {
            return false
        }

        let projectDir = projectFileURL.deletingLastPathComponent().standardizedFileURL
        let rootDir = Self.appDocumentsDir.standardizedFileURL
        let projectDirPath = projectDir.path.hasSuffix("/") ? projectDir.path : projectDir.path + "/"
        let rootDirPath = rootDir.path.hasSuffix("/") ? rootDir.path : rootDir.path + "/"
        return projectDirPath.hasPrefix(rootDirPath) && projectDir != rootDir
    }

    // MARK: - Export quality

    var availableExportQualities: [ExportQualityOption] {
        ExportQualityOption.allCases
    }

    var defaultExportQuality: ExportQualityOption {
        if availableExportQualities.contains(.p1080) { return .p1080 }
        return availableExportQualities.first ?? .p1080
    }

    // MARK: - App documents directory

    static var appDocumentsDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir  = docs.appendingPathComponent("ClipForge")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Video loading

    /// Sets up AVPlayer without resetting any project state.
    private func setupPlayer(url: URL) {
        cleanupPlayer()
        let asset = AVURLAsset(url: url)
        self.asset = asset
        let item   = AVPlayerItem(asset: asset)
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
        timeObserverToken = player.addPeriodicTimeObserver(
            forInterval: interval, queue: .main
        ) { [weak self] time in
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

    /// Load a fresh video, resetting all project state.
    func loadVideo(url: URL, originalFileName: String? = nil) {
        setupPlayer(url: url)
        videoOriginalName    = originalFileName ?? url.lastPathComponent
        segments             = []
        annotations          = []
        selectedSegmentID    = nil
        selectedAnnotationID = nil
        trimStart = 0; trimEnd = nil; playbackSpeed = 1.0
        backgroundSettings   = BackgroundSettings()
        currentProjectURL    = nil
        projectName          = ""
        hasUnsavedChanges    = false
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
        hasUnsavedChanges = true
    }

    // MARK: - Zoom segments

    func addZoomSegment(at time: Double? = nil) {
        let t = (time ?? currentTime).clamped(to: 0...max(0, duration - 2))
        let seg = ZoomSegment(startTime: t)
        segments.append(seg)
        segments.sort { $0.startTime < $1.startTime }
        selectedSegmentID = seg.id
        hasUnsavedChanges = true
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
        let d = duration ?? s.duration
        if let v = easeIn  { s.easeIn  = max(0, min(v, d / 2)) }
        if let v = easeOut { s.easeOut = max(0, min(v, d / 2)) }
        segments[idx] = s
        hasUnsavedChanges = true
    }

    func toggleSegmentEnabled(id: UUID) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return }
        segments[idx].isEnabled.toggle()
        hasUnsavedChanges = true
    }

    func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
        if selectedSegmentID == id { selectedSegmentID = nil }
        hasUnsavedChanges = true
    }

    func removeSegment(at offsets: IndexSet) {
        let ids = offsets.map { segments[$0].id }
        segments.remove(atOffsets: offsets)
        if let sid = selectedSegmentID, ids.contains(sid) { selectedSegmentID = nil }
        hasUnsavedChanges = true
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
            strokeWidth: pendingAnnotationStrokeWidth,
            textColor: pendingTextColor,
            fontSize: pendingFontSize,
            fontWeight: pendingFontWeight,
            showBackground: pendingShowBackground,
            backgroundColor: pendingBackgroundColor,
            backgroundOpacity: pendingBackgroundOpacity,
            backgroundCornerRadius: pendingBackgroundCornerRadius,
            arrowHeadSize: pendingArrowHeadSize,
            arrowHeadAngle: pendingArrowHeadAngle,
            arrowDoubleHeaded: pendingArrowDoubleHeaded,
            arrowFilled: pendingArrowFilled)
        annotations.append(ann)
        pendingAnnotationText = ""
        selectedAnnotationID  = ann.id
        hasUnsavedChanges     = true
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
            strokeWidth: pendingAnnotationStrokeWidth,
            arrowHeadSize: pendingArrowHeadSize,
            arrowHeadAngle: pendingArrowHeadAngle,
            arrowDoubleHeaded: pendingArrowDoubleHeaded,
            arrowFilled: pendingArrowFilled)
        annotations.append(ann)
        selectedAnnotationID = ann.id
        hasUnsavedChanges    = true
    }

    func updateAnnotation(id: UUID, text: String? = nil, startTime: Double? = nil,
                          duration: Double? = nil, position: CGPoint? = nil,
                          endPosition: CGPoint? = nil,
                          strokeColor: CodableColor? = nil, strokeWidth: CGFloat? = nil,
                          textColor: CodableColor? = nil, fontSize: CGFloat? = nil,
                          fontWeight: TextFontWeight? = nil, showBackground: Bool? = nil,
                          backgroundColor: CodableColor? = nil, backgroundOpacity: Double? = nil,
                          backgroundCornerRadius: CGFloat? = nil,
                          arrowHeadSize: CGFloat? = nil, arrowHeadAngle: CGFloat? = nil,
                          arrowDoubleHeaded: Bool? = nil, arrowFilled: Bool? = nil) {
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { return }
        if let v = text                   { annotations[idx].text                   = v }
        if let v = startTime              { annotations[idx].startTime              = max(0, v) }
        if let v = duration               { annotations[idx].duration               = max(0.3, v) }
        if let v = position               { annotations[idx].position               = v }
        if let v = endPosition            { annotations[idx].endPosition            = v }
        if let v = strokeColor            { annotations[idx].strokeColor            = v }
        if let v = strokeWidth            { annotations[idx].strokeWidth            = v }
        if let v = textColor              { annotations[idx].textColor              = v }
        if let v = fontSize               { annotations[idx].fontSize               = max(0.005, v) }
        if let v = fontWeight             { annotations[idx].fontWeight             = v }
        if let v = showBackground         { annotations[idx].showBackground         = v }
        if let v = backgroundColor        { annotations[idx].backgroundColor        = v }
        if let v = backgroundOpacity      { annotations[idx].backgroundOpacity      = v }
        if let v = backgroundCornerRadius { annotations[idx].backgroundCornerRadius = v }
        if let v = arrowHeadSize          { annotations[idx].arrowHeadSize          = max(1, v) }
        if let v = arrowHeadAngle         { annotations[idx].arrowHeadAngle         = v.clamped(to: 8...80) }
        if let v = arrowDoubleHeaded      { annotations[idx].arrowDoubleHeaded      = v }
        if let v = arrowFilled            { annotations[idx].arrowFilled            = v }
        hasUnsavedChanges = true
    }

    func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id { selectedAnnotationID = nil }
        hasUnsavedChanges = true
    }

    func deleteAnnotations(at offsets: IndexSet) {
        let ids = offsets.map { annotations[$0].id }
        annotations.remove(atOffsets: offsets)
        if let sid = selectedAnnotationID, ids.contains(sid) { selectedAnnotationID = nil }
        hasUnsavedChanges = true
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

    // MARK: - Project: Save

    func saveProject(name: String) throws {
        guard let asset else { throw ProjectError.noVideo }
        let fm = FileManager.default

        let safeName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !safeName.isEmpty else { throw ProjectError.noVideo }

        let projectDir = Self.appDocumentsDir.appendingPathComponent(safeName)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)

        // Determine video filename to use inside the project folder
        let ext = asset.url.pathExtension.isEmpty ? "mp4" : asset.url.pathExtension
        let videoSaveName = videoOriginalName.isEmpty ? "video.\(ext)" : videoOriginalName
        let videoDestURL  = projectDir.appendingPathComponent(videoSaveName)

        if !fm.fileExists(atPath: videoDestURL.path) {
            try fm.copyItem(at: asset.url, to: videoDestURL)
        }

        let project = ClipForgeProject(
            name: safeName,
            videoFileName: videoSaveName,
            segments: segments,
            annotations: annotations,
            trimStart: trimStart,
            trimEnd: trimEnd,
            playbackSpeed: playbackSpeed,
            backgroundSettings: backgroundSettings)

        let data = try JSONEncoder().encode(project)
        try data.write(to: projectDir.appendingPathComponent(ClipForgeProject.fileName))

        currentProjectURL = projectDir
        projectName       = safeName
        hasUnsavedChanges = false
        addToRecents(name: safeName,
                     projectFileURL: projectDir.appendingPathComponent(ClipForgeProject.fileName))
    }

    /// Re-saves to the existing project folder (must already have a project URL).
    func saveCurrentProject() throws {
        guard let dir = currentProjectURL else { return }
        try saveProject(name: dir.lastPathComponent)
    }

    // MARK: - Project: Load

    func loadProject(from projectFile: URL) throws {
        let data    = try Data(contentsOf: projectFile)
        let project = try JSONDecoder().decode(ClipForgeProject.self, from: data)
        let dir     = projectFile.deletingLastPathComponent()
        let videoURL = dir.appendingPathComponent(project.videoFileName)

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            throw ProjectError.videoFileMissing(project.videoFileName)
        }

        setupPlayer(url: videoURL)
        videoOriginalName    = project.videoFileName
        segments             = project.segments
        annotations          = project.annotations
        selectedSegmentID    = nil
        selectedAnnotationID = nil
        trimStart            = project.trimStart
        trimEnd              = project.trimEnd
        playbackSpeed        = project.playbackSpeed
        backgroundSettings   = project.backgroundSettings
        currentProjectURL    = dir
        projectName          = project.name
        hasUnsavedChanges    = false
        addToRecents(name: project.name, projectFileURL: projectFile)
    }

    // MARK: - Export

    func exportVideo(quality: ExportQualityOption) {
        guard let asset else { showError("No video loaded."); return }
        guard !isExporting else { return }
        isExporting = true
        exportURL = nil

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        let segs = segments
        let anns = annotations
        let bg = backgroundSettings
        let ts = trimStart
        let te = effectiveTrimEnd
        let spd = playbackSpeed
        let presetName = quality.presetName

        Task {
            do {
                try await ClipForge.exportVideo(
                    asset: asset, segments: segs, annotations: anns,
                    background: bg, trimStart: ts, trimEnd: te, speed: spd,
                    outputURL: outURL,
                    presetName: presetName)
                await MainActor.run { self.exportURL = outURL; self.isExporting = false }
            } catch {
                await MainActor.run { self.isExporting = false; self.showError(error.localizedDescription) }
            }
        }
    }

    func exportVideo() {
        exportVideo(quality: defaultExportQuality)
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
