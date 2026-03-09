import AVFoundation
import Combine
import CoreGraphics
import Foundation
import SwiftUI

enum ExportQualityOption: String, CaseIterable, Identifiable, Sendable {
    case p480
    case p720
    case p1080
    case p4k
    case original

    var id: String { rawValue }

    var title: String {
        switch self {
        case .p480:    return "480p"
        case .p720:    return "720p"
        case .p1080:   return "1080p"
        case .p4k:     return "4K"
        case .original:return "Best"
        }
    }

    var subtitle: String {
        switch self {
        case .p480:    return "640 × 480"
        case .p720:    return "1280 × 720"
        case .p1080:   return "1920 × 1080"
        case .p4k:     return "3840 × 2160"
        case .original:return "Highest quality"
        }
    }

    var presetName: String {
        switch self {
        case .p480:    return AVAssetExportPreset640x480
        case .p720:    return AVAssetExportPreset1280x720
        case .p1080:   return AVAssetExportPreset1920x1080
        case .p4k:     return AVAssetExportPreset3840x2160
        case .original:return AVAssetExportPresetHighestQuality
        }
    }
}

struct SubtitleLocaleOption: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
}

@MainActor
final class ClipForgeViewModel: ObservableObject {

    // MARK: - Player state
    @Published var player: AVPlayer?
    @Published var duration: Double = 0
    @Published var currentTime: Double = 0
    @Published var isPlaying: Bool = false
    @Published var videoAspectRatio: CGFloat = 16.0 / 9.0

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
    private static let subtitleStyleConfigKey = "subtitleStyleConfiguration"
    private static let maxRecents = 10

    // MARK: - Export state
    @Published var isExporting: Bool = false
    @Published var exportURL: URL?
    @Published var alertMessage: String?
    @Published var showAlert: Bool = false

    // MARK: - Subtitle state
    @Published var subtitles: [SubtitleSegment] = []
    @Published var isGeneratingSubtitles: Bool = false
    @Published var subtitleProgress: String = ""
    @Published var subtitleError: String? = nil
    @Published var includeSubtitlesInExport: Bool = true
    @Published var subtitleStylePreset: SubtitleStylePreset = .classic
    @Published var subtitleStyle: SubtitleStyle = .classic
    @Published var customSubtitlePresets: [CustomSubtitlePreset] = []
    @Published var selectedCustomSubtitlePresetID: UUID? = nil
    @Published var subtitleLocaleOptions: [SubtitleLocaleOption] = []
    @Published var isLoadingSubtitleLocales: Bool = false
    /// BCP-47 locale identifier for transcription.
    @Published var subtitleLocaleID: String = ""

    // MARK: - Internal
    private var asset: AVURLAsset?
    private var timeObserverToken: Any?
    private var playerItemCancellable: AnyCancellable?

    // MARK: - Init

    private struct SubtitleStyleConfiguration: Codable {
        var preset: SubtitleStylePreset
        var style: SubtitleStyle
        var customPresets: [CustomSubtitlePreset]
        var selectedCustomPresetID: UUID?
    }

    init() { 
        loadRecents()
        loadSubtitleStyleConfiguration()
        Task { await refreshSubtitleLocaleOptions() }
        CFLogInfo("ClipForgeViewModel initialized")
    }

    // MARK: - Recent projects

    private func loadRecents() {
        CFLogDebug("Loading recent projects from UserDefaults")
        guard let data = UserDefaults.standard.data(forKey: Self.recentsKey),
              let decoded = try? JSONDecoder().decode([RecentProject].self, from: data)
        else { 
            CFLogDebug("No recent projects found in UserDefaults")
            return 
        }
        recentProjects = decoded.filter {
            FileManager.default.fileExists(atPath: $0.projectFileURL.path)
        }
        CFLogInfo("Loaded \(self.recentProjects.count) recent projects")
    }

    private func persistRecents() {
        guard let data = try? JSONEncoder().encode(recentProjects) else { return }
        UserDefaults.standard.set(data, forKey: Self.recentsKey)
    }

    private func loadSubtitleStyleConfiguration() {
        guard
            let data = UserDefaults.standard.data(forKey: Self.subtitleStyleConfigKey),
            let config = try? JSONDecoder().decode(SubtitleStyleConfiguration.self, from: data)
        else {
            return
        }

        subtitleStylePreset = config.preset
        subtitleStyle = config.style
        customSubtitlePresets = config.customPresets

        if let selectedID = config.selectedCustomPresetID,
           customSubtitlePresets.contains(where: { $0.id == selectedID }) {
            selectedCustomSubtitlePresetID = selectedID
        } else {
            selectedCustomSubtitlePresetID = nil
        }
    }

    private func persistSubtitleStyleConfiguration() {
        let config = SubtitleStyleConfiguration(
            preset: subtitleStylePreset,
            style: subtitleStyle,
            customPresets: customSubtitlePresets,
            selectedCustomPresetID: selectedCustomSubtitlePresetID
        )

        guard let data = try? JSONEncoder().encode(config) else { return }
        UserDefaults.standard.set(data, forKey: Self.subtitleStyleConfigKey)
    }

    func addToRecents(name: String, projectFileURL: URL) {
        CFLogDebug("Adding to recents: \(name)")
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
        CFLogDebug("Removing from recents: \(id)")
        recentProjects.removeAll { $0.id == id }
        persistRecents()
    }

    func deleteProject(_ recent: RecentProject) throws {
        CFLogInfo("Deleting project: \(recent.name) at \(recent.projectFileURL.path)")
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
        CFLogInfo("Project deleted successfully: \(recent.name)")
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
        CFLogInfo("Setting up player with URL: \(url.lastPathComponent)")
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

                    if let srcVideo = try? await asset.loadTracks(withMediaType: .video).first,
                       let naturalSize = try? await srcVideo.load(.naturalSize),
                       let preferredTransform = try? await srcVideo.load(.preferredTransform) {
                        let orientedSize: CGSize = {
                            if abs(preferredTransform.b) > 0.5 || abs(preferredTransform.c) > 0.5 {
                                return CGSize(width: naturalSize.height, height: naturalSize.width)
                            }
                            return naturalSize
                        }()
                        if orientedSize.width > 0.001, orientedSize.height > 0.001 {
                            self.videoAspectRatio = (orientedSize.width / orientedSize.height).clamped(to: 0.2...5)
                        }
                    }

                    CFLogInfo("Video ready to play, duration: \(self.duration) seconds")
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
                        CFLogDebug("Playback stopped at end")
                    }
                }
            }
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(playerDidFinish),
            name: .AVPlayerItemDidPlayToEndTime, object: item)
        player.play(); isPlaying = true
        CFLogInfo("Player setup complete, started playback")
    }

    /// Load a fresh video, resetting all project state.
    func loadVideo(url: URL, originalFileName: String? = nil) {
        CFLogInfo("Loading video: \(url.lastPathComponent)")
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
        subtitles            = []
        subtitleProgress     = ""
        subtitleError        = nil
        isGeneratingSubtitles = false
        CFLogInfo("Video loaded successfully, original name: \(videoOriginalName)")
    }

    @objc private func playerDidFinish() { 
        isPlaying = false
        CFLogDebug("Player finished playing")
    }

    // MARK: - Playback

    func togglePlayPause() {
        guard let player else { 
            CFLogWarn("togglePlayPause called but player is nil")
            return 
        }
        if isPlaying {
            player.pause(); isPlaying = false
            CFLogDebug("Playback paused at time: \(currentTime)")
        } else {
            if currentTime >= effectiveTrimEnd - 0.05 { seek(to: trimStart) }
            player.rate = Float(playbackSpeed); isPlaying = true
            CFLogDebug("Playback started at time: \(currentTime), speed: \(playbackSpeed)")
        }
    }

    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600),
                     toleranceBefore: .zero, toleranceAfter: .zero)
        CFLogDebug("Seeked to time: \(time)")
    }

    private let frameDuration = 1.0 / 30.0
    func stepForward() { let t = min(currentTime + frameDuration, effectiveTrimEnd); currentTime = t; seek(to: t); CFLogDebug("Stepped forward to: \(t)") }
    func stepBack()    { let t = max(currentTime - frameDuration, trimStart);        currentTime = t; seek(to: t); CFLogDebug("Stepped back to: \(t)") }

    func setSpeed(_ speed: Double) {
        playbackSpeed = speed
        if isPlaying { player?.rate = Float(speed) }
        hasUnsavedChanges = true
        CFLogInfo("Playback speed changed to: \(speed)")
    }

    // MARK: - Zoom segments

    func addZoomSegment(at time: Double? = nil) {
        let t = (time ?? currentTime).clamped(to: 0...max(0, duration - 2))
        let seg = ZoomSegment(startTime: t)
        segments.append(seg)
        segments.sort { $0.startTime < $1.startTime }
        selectedSegmentID = seg.id
        hasUnsavedChanges = true
        CFLogInfo("Added zoom segment at time: \(t), id: \(seg.id)")
    }

    func updateSegment(id: UUID, scale: CGFloat? = nil, center: CGPoint? = nil,
                       easeIn: Double? = nil, easeOut: Double? = nil,
                       startTime: Double? = nil, duration: Double? = nil) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { 
            CFLogWarn("updateSegment called but segment not found: \(id)")
            return 
        }
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
        CFLogDebug("Updated segment \(id)")
    }

    func toggleSegmentEnabled(id: UUID) {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { 
            CFLogWarn("toggleSegmentEnabled called but segment not found: \(id)")
            return 
        }
        segments[idx].isEnabled.toggle()
        hasUnsavedChanges = true
        CFLogInfo("Segment \(id) enabled: \(segments[idx].isEnabled)")
    }

    func removeSegment(id: UUID) {
        segments.removeAll { $0.id == id }
        if selectedSegmentID == id { selectedSegmentID = nil }
        hasUnsavedChanges = true
        CFLogInfo("Removed segment: \(id)")
    }

    func removeSegment(at offsets: IndexSet) {
        let ids = offsets.map { segments[$0].id }
        segments.remove(atOffsets: offsets)
        if let sid = selectedSegmentID, ids.contains(sid) { selectedSegmentID = nil }
        hasUnsavedChanges = true
        CFLogInfo("Removed segments at offsets: \(offsets)")
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
        CFLogInfo("Added annotation: \(pendingAnnotationKind.rawValue), id: \(ann.id)")
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
        CFLogInfo("Added annotation segment: \(pendingAnnotationKind.rawValue), id: \(ann.id), time: \(t)")
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
        guard let idx = annotations.firstIndex(where: { $0.id == id }) else { 
            CFLogWarn("updateAnnotation called but annotation not found: \(id)")
            return 
        }
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
        CFLogDebug("Updated annotation: \(id)")
    }

    func removeAnnotation(id: UUID) {
        annotations.removeAll { $0.id == id }
        if selectedAnnotationID == id { selectedAnnotationID = nil }
        hasUnsavedChanges = true
        CFLogInfo("Removed annotation: \(id)")
    }

    func deleteAnnotations(at offsets: IndexSet) {
        let ids = offsets.map { annotations[$0].id }
        annotations.remove(atOffsets: offsets)
        if let sid = selectedAnnotationID, ids.contains(sid) { selectedAnnotationID = nil }
        hasUnsavedChanges = true
        CFLogInfo("Removed annotations at offsets: \(offsets)")
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
        CFLogInfo("Saving project: \(name)")
        guard let asset else { 
            CFLogError("saveProject failed: no video loaded")
            throw ProjectError.noVideo 
        }
        let fm = FileManager.default

        let safeName = name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !safeName.isEmpty else { 
            CFLogError("saveProject failed: invalid name")
            throw ProjectError.noVideo 
        }

        let projectDir = Self.appDocumentsDir.appendingPathComponent(safeName)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        CFLogDebug("Created project directory: \(projectDir.path)")

        // Determine video filename to use inside the project folder
        let ext = asset.url.pathExtension.isEmpty ? "mp4" : asset.url.pathExtension
        let videoSaveName = videoOriginalName.isEmpty ? "video.\(ext)" : videoOriginalName
        let videoDestURL  = projectDir.appendingPathComponent(videoSaveName)

        if !fm.fileExists(atPath: videoDestURL.path) {
            try fm.copyItem(at: asset.url, to: videoDestURL)
            CFLogDebug("Copied video to: \(videoDestURL.path)")
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
        CFLogDebug("Wrote project file")

        currentProjectURL = projectDir
        projectName       = safeName
        hasUnsavedChanges = false
        addToRecents(name: safeName,
                     projectFileURL: projectDir.appendingPathComponent(ClipForgeProject.fileName))
        CFLogInfo("Project saved successfully: \(safeName)")
    }

    /// Re-saves to the existing project folder (must already have a project URL).
    func saveCurrentProject() throws {
        guard let dir = currentProjectURL else { 
            CFLogWarn("saveCurrentProject called but no current project URL")
            return 
        }
        CFLogInfo("Saving current project to: \(dir.lastPathComponent)")
        try saveProject(name: dir.lastPathComponent)
    }

    // MARK: - Project: Load

    func loadProject(from projectFile: URL) throws {
        CFLogInfo("Loading project from: \(projectFile.path)")
        let data    = try Data(contentsOf: projectFile)
        let project = try JSONDecoder().decode(ClipForgeProject.self, from: data)
        let dir     = projectFile.deletingLastPathComponent()
        let videoURL = dir.appendingPathComponent(project.videoFileName)

        guard FileManager.default.fileExists(atPath: videoURL.path) else {
            CFLogError("Video file missing: \(project.videoFileName)")
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
        CFLogInfo("Project loaded successfully: \(project.name), segments: \(segments.count), annotations: \(annotations.count)")
    }

    // MARK: - Subtitles

    func refreshSubtitleLocaleOptionsIfNeeded() {
        guard subtitleLocaleOptions.isEmpty, !isLoadingSubtitleLocales else { return }
        Task { await refreshSubtitleLocaleOptions() }
    }

    func refreshSubtitleLocaleOptions() async {
        guard !isLoadingSubtitleLocales else { return }

        isLoadingSubtitleLocales = true
        let locales = await availableOfflineTranscriptionLocales()
        let options = locales.map { locale in
            let displayName = Locale.current.localizedString(forIdentifier: locale.identifier) ?? locale.identifier
            return SubtitleLocaleOption(id: locale.identifier, name: displayName)
        }
        subtitleLocaleOptions = options
        isLoadingSubtitleLocales = false

        guard !options.isEmpty else {
            subtitleLocaleID = ""
            CFLogWarn("ViewModel: No offline subtitle locales found")
            return
        }

        if options.contains(where: { localeIdentifiersMatch($0.id, subtitleLocaleID) }) {
            return
        }

        let currentLocaleID = Locale.current.identifier
        if let currentOption = options.first(where: { localeIdentifiersMatch($0.id, currentLocaleID) }) {
            subtitleLocaleID = currentOption.id
        } else {
            subtitleLocaleID = options[0].id
        }

        CFLogInfo("ViewModel: Loaded \(options.count) offline subtitle locale option(s)")
    }

    private func localeIdentifiersMatch(_ lhs: String, _ rhs: String) -> Bool {
        Locale.identifier(.bcp47, from: lhs) == Locale.identifier(.bcp47, from: rhs)
    }

    /// Effective locale derived from `subtitleLocaleID`.
    var subtitleLocale: Locale {
        subtitleLocaleID.isEmpty ? .current : Locale(identifier: subtitleLocaleID)
    }

    var selectedSubtitleStyle: SubtitleStyle {
        subtitleStyle
    }

    func selectSubtitleStylePreset(_ preset: SubtitleStylePreset) {
        guard preset != .custom else {
            subtitleStylePreset = .custom
            selectedCustomSubtitlePresetID = nil
            persistSubtitleStyleConfiguration()
            return
        }

        subtitleStylePreset = preset
        subtitleStyle = preset.subtitleStyle
        selectedCustomSubtitlePresetID = nil
        persistSubtitleStyleConfiguration()
    }

    func updateSubtitleStyle(_ mutate: (inout SubtitleStyle) -> Void) {
        var updated = subtitleStyle
        mutate(&updated)
        subtitleStyle = updated

        if let builtIn = builtInPreset(matching: updated) {
            subtitleStylePreset = builtIn
            selectedCustomSubtitlePresetID = nil
        } else {
            subtitleStylePreset = .custom

            if let selectedID = selectedCustomSubtitlePresetID,
               let selected = customSubtitlePresets.first(where: { $0.id == selectedID }),
               selected.style != updated {
                selectedCustomSubtitlePresetID = nil
            }
        }

        persistSubtitleStyleConfiguration()
    }

    func saveCurrentSubtitleStyleAsPreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existingIndex = customSubtitlePresets.firstIndex(where: {
            $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            customSubtitlePresets[existingIndex].style = subtitleStyle
            selectedCustomSubtitlePresetID = customSubtitlePresets[existingIndex].id
        } else {
            let preset = CustomSubtitlePreset(name: trimmed, style: subtitleStyle)
            customSubtitlePresets.append(preset)
            selectedCustomSubtitlePresetID = preset.id
        }

        subtitleStylePreset = .custom
        persistSubtitleStyleConfiguration()
    }

    func applyCustomSubtitlePreset(id: UUID) {
        guard let preset = customSubtitlePresets.first(where: { $0.id == id }) else { return }
        subtitleStyle = preset.style
        subtitleStylePreset = .custom
        selectedCustomSubtitlePresetID = preset.id
        persistSubtitleStyleConfiguration()
    }

    func deleteCustomSubtitlePreset(id: UUID) {
        customSubtitlePresets.removeAll { $0.id == id }
        if selectedCustomSubtitlePresetID == id {
            selectedCustomSubtitlePresetID = nil
            subtitleStylePreset = builtInPreset(matching: subtitleStyle) ?? .custom
        }
        persistSubtitleStyleConfiguration()
    }

    private func builtInPreset(matching style: SubtitleStyle) -> SubtitleStylePreset? {
        if style == .classic { return .classic }
        if style == .tikTok { return .tikTok }
        if style == .tikTokYellow { return .tikTokYellow }
        return nil
    }

    /// Starts on-device subtitle generation for the loaded video.
    /// Updates `subtitleProgress`, `subtitleError`, and `subtitles` on completion.
    func generateSubtitles() {
        guard let asset else {
            CFLogError("ViewModel: generateSubtitles called but no asset loaded")
            subtitleError = "No video loaded."
            return
        }
        guard !isGeneratingSubtitles else {
            CFLogWarn("ViewModel: generateSubtitles called but already in progress")
            return
        }
        guard !subtitleLocaleOptions.isEmpty else {
            CFLogWarn("ViewModel: generateSubtitles called with no offline locale options")
            subtitleError = "No offline speech models are installed for transcription."
            return
        }

        let locale = subtitleLocale
        CFLogInfo("ViewModel: Starting subtitle generation, locale=\(locale.identifier)")
        isGeneratingSubtitles = true
        subtitleError = nil
        subtitleProgress = "Requesting authorization…"

        Task {
            do {
                // ── 1. Authorization ──────────────────────────────────────
                let authorized = await requestSpeechAuthorization()
                guard authorized else {
                    CFLogError("ViewModel: Speech authorization denied")
                    subtitleProgress = ""
                    subtitleError = SubtitleError.authorizationDenied.errorDescription
                    isGeneratingSubtitles = false
                    return
                }

                // ── 2. Audio extraction ───────────────────────────────────
                subtitleProgress = "Extracting audio…"
                CFLogInfo("ViewModel: Extracting audio from asset")
                let audioURL = try await extractAudio(from: asset)

                defer {
                    CFLogDebug("ViewModel: Cleaning up temp audio file \(audioURL.lastPathComponent)")
                    try? FileManager.default.removeItem(at: audioURL)
                }

                // ── 3. Transcription ──────────────────────────────────────
                subtitleProgress = "Transcribing on-device…"
                CFLogInfo("ViewModel: Starting transcription")

                let segs: [SubtitleSegment]
                if #available(macOS 26.0, iOS 26.0, *) {
                    CFLogInfo("ViewModel: Using SpeechAnalyzer path (macOS 26+)")
                    segs = try await transcribeWithSpeechAnalyzer(audioURL: audioURL, locale: locale)
                } else {
                    CFLogInfo("ViewModel: Using legacy SFSpeechRecognizer path")
                    segs = try await transcribeLegacy(audioURL: audioURL, locale: locale)
                }

                // ── 4. Merge short segments → done ───────────────────────
                let merged = mergeShortSegments(segs)
                subtitles = merged
                subtitleProgress = merged.isEmpty ? "No speech detected." : "Done — \(merged.count) subtitle(s) generated."
                isGeneratingSubtitles = false
                CFLogInfo("ViewModel: Subtitle generation complete — \(segs.count) raw → \(merged.count) after merge")

            } catch {
                subtitleProgress = ""
                subtitleError = error.localizedDescription
                isGeneratingSubtitles = false
                CFLogError("ViewModel: Subtitle generation failed: \(error.localizedDescription)")
            }
        }
    }

    /// Removes all generated subtitles.
    func clearSubtitles() {
        CFLogInfo("ViewModel: Clearing \(subtitles.count) subtitle(s)")
        subtitles = []
        subtitleProgress = ""
        subtitleError = nil
    }

    /// Removes a single subtitle segment.
    func removeSubtitle(id: UUID) {
        subtitles.removeAll { $0.id == id }
        CFLogInfo("ViewModel: Removed subtitle \(id)")
    }

    /// Writes the current subtitles to a temporary SRT file and returns the URL.
    func makeSRTFileURL() -> URL? {
        guard !subtitles.isEmpty else {
            CFLogWarn("ViewModel: makeSRTFileURL called but subtitles is empty")
            return nil
        }
        let baseName = videoOriginalName.isEmpty ? "subtitles"
            : (videoOriginalName as NSString).deletingPathExtension
        return writeSRTToTemp(segments: subtitles, baseName: baseName)
    }

    // MARK: - Export

    func exportVideo(quality: ExportQualityOption) {
        CFLogInfo("Starting export with quality: \(quality.title)")
        guard let asset else { 
            CFLogError("exportVideo failed: no video loaded")
            showError("No video loaded."); 
            return 
        }
        guard !isExporting else { 
            CFLogWarn("exportVideo called but export already in progress")
            return 
        }
        isExporting = true
        exportURL = nil

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathExtension("mp4")

        let segs = segments
        let anns = annotations
        let subs = includeSubtitlesInExport ? subtitles : []
        let subtitleStyle = selectedSubtitleStyle
        let bg = backgroundSettings
        let ts = trimStart
        let te = effectiveTrimEnd
        let spd = playbackSpeed
        let presetName = quality.presetName
        CFLogInfo("ViewModel: Export will include \(subs.count) subtitle(s) (burn-in: \(includeSubtitlesInExport))")

        Task {
            do {
                try await ClipForge.exportVideo(
                    asset: asset, segments: segs, annotations: anns,
                    subtitles: subs,
                    subtitleStyle: subtitleStyle,
                    background: bg, trimStart: ts, trimEnd: te, speed: spd,
                    outputURL: outURL,
                    presetName: presetName)
                await MainActor.run { 
                    self.exportURL = outURL; 
                    self.isExporting = false
                    CFLogInfo("Export completed successfully: \(outURL.lastPathComponent)")
                }
            } catch {
                await MainActor.run { 
                    self.isExporting = false; 
                    self.showError(error.localizedDescription)
                    CFLogError("Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func exportVideo() {
        exportVideo(quality: defaultExportQuality)
    }

    func showError(_ msg: String) { 
        alertMessage = msg; 
        showAlert = true
        CFLogError("Error shown to user: \(msg)")
    }

    // MARK: - Cleanup

    private func cleanupPlayer() {
        if let token = timeObserverToken { player?.removeTimeObserver(token); timeObserverToken = nil }
        player?.pause(); player = nil
        playerItemCancellable = nil
        NotificationCenter.default.removeObserver(self)
        CFLogDebug("Player cleaned up")
    }

    deinit {
        CFLogInfo("ClipForgeViewModel deallocated")
    }
}
