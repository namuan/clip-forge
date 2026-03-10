import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Control panel tabs

private enum ControlPanel: String, CaseIterable {
    case zoom        = "Zoom"
    case annotations = "Annotations"
    case canvas      = "Canvas"
    case clip        = "Clip"
    case subtitles   = "Subtitles"

    var icon: String {
        switch self {
        case .zoom:        return "magnifyingglass"
        case .annotations: return "text.bubble"
        case .canvas:      return "paintpalette"
        case .clip:        return "scissors"
        case .subtitles:   return "captions.bubble"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var vm = ClipForgeViewModel()

    @State private var showFilePicker      = false
    @State private var importingProject    = false   // true = project pick, false = video pick
    @State private var showSaveSheet       = false
    @State private var showExportSheet     = false
    @State private var newProjectName      = ""
    @State private var selectedExportQuality: ExportQualityOption = .p1080
    @State private var activePanel: ControlPanel = .zoom
    @State private var timelinePanelHeight: CGFloat = 220
    @State private var timelineDragBase: CGFloat = 220

    var body: some View {
        configured(navigationStack)
            .preferredColorScheme(.light)
    }

    private var navigationStack: some View {
        NavigationStack {
            Group {
                if vm.player == nil {
                    StartScreenView(vm: vm,
                                    onOpenVideo:   { importingProject = false; showFilePicker = true },
                                    onOpenProject: { importingProject = true;  showFilePicker = true })
                    .frame(width: 660, height: 440)
                    .onAppear { configureWindow(startScreen: true) }
                } else {
                    Group {
                        #if canImport(AppKit)
                        HSplitView {
                            leftColumn.frame(minWidth: 400, maxWidth: .infinity)
                            rightColumn.frame(minWidth: 260, idealWidth: 320, maxWidth: 420)
                        }
                        #else
                        HStack(spacing: 0) { leftColumn; Divider(); rightColumn }
                        #endif
                    }
                    .onAppear { configureWindow(startScreen: false) }
                }
            }
            .frame(
                minWidth:  vm.player == nil ? 660  : 900,
                maxWidth:  vm.player == nil ? 660  : .infinity,
                minHeight: vm.player == nil ? 440  : 600,
                maxHeight: vm.player == nil ? 440  : .infinity
            )
            .navigationTitle(navigationTitle)
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
    }

    // Applies all modal / lifecycle modifiers in one place, broken into
    // smaller functions so the type checker doesn't time out.
    private func configured(_ base: some View) -> some View {
        base
            .fileImporter(isPresented: $showFilePicker,
                          allowedContentTypes: importingProject ? projectContentTypes : videoContentTypes,
                          allowsMultipleSelection: false) { result in
                guard case .success(let urls) = result, let url = urls.first else { return }
                if importingProject {
                    do { try vm.loadProject(from: url); activePanel = .zoom }
                    catch { vm.showError(error.localizedDescription) }
                } else {
                    loadFromURL(url)
                }
            }
            .sheet(isPresented: $showSaveSheet) { saveNameSheet }
            .sheet(isPresented: $showExportSheet) { exportSheet }
            .alert("Error", isPresented: $vm.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.alertMessage ?? "")
            }
            .onChange(of: vm.selectedAnnotationID) { _, id  in if id  != nil { activePanel = .annotations } }
            .onChange(of: vm.selectedSegmentID)    { _, id  in if id  != nil { activePanel = .zoom } }
            .onChange(of: vm.backgroundSettings)   { _,  _  in vm.hasUnsavedChanges = true }
            .onChange(of: vm.trimStart)            { _,  _  in vm.hasUnsavedChanges = true }
            .onChange(of: vm.trimEnd)              { _,  _  in vm.hasUnsavedChanges = true }
            .onChange(of: vm.player) { old, new in
                guard old == nil, new != nil else { return }
                // Delay lets the window resize to editor dimensions before maximising
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    #if canImport(AppKit)
                    if let w = activeWindow, !w.isZoomed { w.zoom(nil) }
                    #endif
                }
            }
    }

    // MARK: - Window chrome

    private func configureWindow(startScreen: Bool) {
        #if canImport(AppKit)
        DispatchQueue.main.async {
            guard let window = activeWindow else { return }
            if startScreen {
                let dialogSize = NSSize(width: 660, height: 440)
                if window.isZoomed { window.zoom(nil) }
                window.title = ""
                window.titleVisibility          = .hidden
                window.titlebarAppearsTransparent = true
                window.styleMask.insert(.titled)
                window.styleMask.remove(.resizable)
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = true
                window.titlebarSeparatorStyle = .none
                window.toolbar?.isVisible = false
                window.standardWindowButton(.closeButton)?.isHidden = true
                window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                window.standardWindowButton(.zoomButton)?.isHidden = true
                window.setContentSize(dialogSize)
                centerOnActiveScreen(window)
            } else {
                window.styleMask.insert(.titled)
                window.styleMask.insert(.resizable)
                window.titleVisibility          = .visible
                window.titlebarAppearsTransparent = false
                window.styleMask.remove(.fullSizeContentView)
                window.isMovableByWindowBackground = false
                window.titlebarSeparatorStyle = .automatic
                window.standardWindowButton(.closeButton)?.isHidden = false
                window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                window.standardWindowButton(.zoomButton)?.isHidden = false
                window.title = "ClipForge"
                window.toolbar?.isVisible = true
                window.toolbar?.displayMode = .iconOnly
                window.toolbar?.sizeMode = .regular

                // Re-zoom after style restoration so the editor reliably maximizes.
                if !window.isZoomed { window.zoom(nil) }
            }
        }
        #endif
    }

    #if canImport(AppKit)
    private var activeWindow: NSWindow? {
        NSApplication.shared.keyWindow
            ?? NSApplication.shared.mainWindow
            ?? NSApplication.shared.windows.first(where: { $0.isVisible })
    }

    private func centerOnActiveScreen(_ window: NSWindow) {
        let mouse = NSEvent.mouseLocation
        let activeScreen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? window.screen
            ?? NSScreen.main

        guard let screen = activeScreen else {
            window.center()
            return
        }

        let visible = screen.visibleFrame
        var frame = window.frame
        frame.origin.x = visible.minX + (visible.width - frame.width) / 2
        frame.origin.y = visible.minY + (visible.height - frame.height) / 2
        window.setFrame(frame, display: true)
    }
    #endif

    private var videoContentTypes: [UTType] {
        [.movie, .video,
         UTType(filenameExtension: "mp4") ?? .data,
         UTType(filenameExtension: "mov") ?? .data,
         UTType(filenameExtension: "m4v") ?? .data]
    }

    private var projectContentTypes: [UTType] {
        [UTType(filenameExtension: "clipforge") ?? .data]
    }

    // MARK: - Navigation title

    private var navigationTitle: String {
        if vm.player == nil { return "" }
        if !vm.projectName.isEmpty {
            return vm.projectName + (vm.hasUnsavedChanges ? " •" : "")
        }
        return "Untitled •"
    }

    // MARK: - Columns

    private var leftColumn: some View {
        VStack(spacing: 0) {
            VideoPlayerView(vm: vm)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            timelinePanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timelinePanel: some View {
        VStack(spacing: 0) {
            // Drag handle
            Color.clear
                .frame(height: 6)
                .overlay(
                    Capsule()
                        .fill(Color.secondary.opacity(0.35))
                        .frame(width: 36, height: 3)
                )
                .contentShape(Rectangle())
                #if canImport(AppKit)
                .onHover { inside in
                    if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
                }
                #endif
                .gesture(
                    DragGesture(coordinateSpace: .global)
                        .onChanged { value in
                            timelinePanelHeight = (timelineDragBase - value.translation.height)
                                .clamped(to: 140...520)
                        }
                        .onEnded { _ in
                            timelineDragBase = timelinePanelHeight
                        }
                )

            TimelineView(vm: vm)
                .padding(.top, 8)

            VisualTimelineView(vm: vm)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .frame(height: timelinePanelHeight)
        .animation(nil, value: timelinePanelHeight)
    }

    private var rightColumn: some View {
        ScrollView {
            VStack(spacing: 0) {
                if vm.player != nil {

                    // ── Control panel tabs ─────────────────────────────────
                    Picker("", selection: $activePanel) {
                        ForEach(ControlPanel.allCases, id: \.self) { panel in
                            Label(panel.rawValue, systemImage: panel.icon).tag(panel)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding([.horizontal, .top], 12)

                    // ── Active panel ───────────────────────────────────────
                    Group {
                        switch activePanel {
                        case .zoom:        ZoomControlsView(vm: vm)
                        case .annotations: AnnotationControlsView(vm: vm)
                        case .canvas:      BackgroundControlsView(vm: vm)
                        case .clip:        ClipControlsView(vm: vm)
                        case .subtitles:   SubtitleControlsView(vm: vm)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                Spacer(minLength: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Save name sheet

    private var saveNameSheet: some View {
        VStack(spacing: 20) {
            Text("Save Project")
                .font(.headline)

            TextField("Project name", text: $newProjectName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
                #if canImport(AppKit)
                .onSubmit { commitSave() }
                #endif

            Text("Saved to: ~/Documents/ClipForge/")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                Button("Cancel") { showSaveSheet = false }
                    .keyboardShortcut(.cancelAction)

                Button("Save") { commitSave() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(28)
    }

    private func commitSave() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        showSaveSheet = false
        do {
            try vm.saveProject(name: name)
        } catch {
            vm.showError(error.localizedDescription)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if vm.player != nil {
            ToolbarItem(placement: .primaryAction) {
                HStack(spacing: 0) {
                    Button { handleSave() } label: {
                        Label("Save", systemImage: "arrow.down.to.line")
                            .font(.system(size: 14, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .help("Save Project")
                    .disabled(vm.player == nil)
                    .keyboardShortcut("s", modifiers: .command)

                    Divider()
                        .frame(height: 20)

                    Button {
                        vm.exportURL = nil
                        selectedExportQuality = vm.defaultExportQuality
                        showExportSheet = true
                    } label: {
                        Label("Export", systemImage: "arrow.up.to.line")
                            .font(.system(size: 14, weight: .semibold))
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    .buttonStyle(.plain)
                    .help("Export Video")
                    .disabled(vm.player == nil || vm.isExporting)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(Capsule().fill(.thinMaterial))
                .overlay(Capsule().stroke(Color.primary.opacity(0.14), lineWidth: 1))
            }
        }
    }

    // MARK: - Export sheet

    private var exportSheet: some View {
        VStack(spacing: 16) {
            if let exportedURL = vm.exportURL {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)

                Text("Export Complete")
                    .font(.title3.bold())

                Text(exportedURL.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                #if canImport(AppKit)
                HStack(spacing: 10) {
                    Button("Show Finder") { showInFinder(exportedURL) }
                        .buttonStyle(.borderedProminent)

                    Button("Save As…") { saveExportAs(exportedURL) }
                        .buttonStyle(.bordered)

                    Button("Dismiss") {
                        showExportSheet = false
                        vm.exportURL = nil
                    }
                    .buttonStyle(.bordered)
                }
                #else
                Button("Dismiss") {
                    showExportSheet = false
                    vm.exportURL = nil
                }
                .buttonStyle(.borderedProminent)
                #endif
            } else {
                Text("Export Video")
                    .font(.title3.bold())

                Text("Choose output quality")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Picker("Quality", selection: $selectedExportQuality) {
                    ForEach(vm.availableExportQualities) { quality in
                        Text("\(quality.title)  •  \(quality.subtitle)")
                            .tag(quality)
                    }
                }
                .pickerStyle(.radioGroup)
                .disabled(vm.isExporting)

                if vm.isExporting {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Exporting \(selectedExportQuality.title)…")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 10) {
                    Button("Cancel") {
                        showExportSheet = false
                        vm.exportURL = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.isExporting)

                    Button("Export") {
                        vm.exportVideo(quality: selectedExportQuality)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.isExporting || vm.player == nil)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 360)
        .interactiveDismissDisabled(vm.isExporting)
    }

    private func showInFinder(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #endif
    }

    private func saveExportAs(_ sourceURL: URL) {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = sourceURL.lastPathComponent
        panel.allowedContentTypes = [.mpeg4Movie]
        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
        do {
            try? FileManager.default.removeItem(at: destinationURL)
            try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        } catch {
            vm.showError(error.localizedDescription)
        }
        #endif
    }

    // MARK: - Save logic

    private func handleSave() {
        if vm.currentProjectURL != nil {
            // Already has a project — save in place
            do {
                try vm.saveCurrentProject()
            } catch {
                vm.showError(error.localizedDescription)
            }
        } else {
            // New project — ask for name
            newProjectName = vm.videoOriginalName
                .replacingOccurrences(of: "." + (vm.videoOriginalName as NSString).pathExtension, with: "")
            showSaveSheet = true
        }
    }

    // MARK: - Load helper

    private func loadFromURL(_ url: URL) {
        let originalName = url.lastPathComponent
        let accessing    = url.startAccessingSecurityScopedResource()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        try? FileManager.default.copyItem(at: url, to: dest)
        if accessing { url.stopAccessingSecurityScopedResource() }
        vm.loadVideo(url: dest, originalFileName: originalName)
    }
}
