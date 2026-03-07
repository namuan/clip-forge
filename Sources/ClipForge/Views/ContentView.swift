import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Control panel tabs

private enum ControlPanel: String, CaseIterable {
    case zoom       = "Zoom"
    case text       = "Text"
    case canvas     = "Canvas"
    case clip       = "Clip"

    var icon: String {
        switch self {
        case .zoom:   return "magnifyingglass"
        case .text:   return "text.bubble"
        case .canvas: return "paintpalette"
        case .clip:   return "scissors"
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var vm = ClipForgeViewModel()

    @State private var showFilePicker      = false
    @State private var importingProject    = false   // true = project pick, false = video pick
    @State private var showShareSheet      = false
    @State private var showSaveSheet       = false
    @State private var newProjectName      = ""
    @State private var activePanel: ControlPanel = .zoom

    #if canImport(UIKit)
    @State private var photosPickerItem: PhotosPickerItem?
    #endif

    var body: some View {
        configured(navigationStack)
    }

    private var navigationStack: some View {
        NavigationStack {
            Group {
                #if canImport(AppKit)
                HSplitView {
                    leftColumn.frame(minWidth: 400, maxWidth: .infinity)
                    rightColumn.frame(minWidth: 200, maxWidth: 300)
                }
                #else
                HStack(spacing: 0) { leftColumn; Divider(); rightColumn }
                #endif
            }
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
            .sheet(isPresented: $showShareSheet) {
                if let url = vm.exportURL { ShareSheet(url: url) }
            }
            .sheet(isPresented: $showSaveSheet) { saveNameSheet }
            .alert("Error", isPresented: $vm.showAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(vm.alertMessage ?? "")
            }
            .onChange(of: vm.exportURL)            { _, url in if url != nil { showShareSheet = true } }
            .onChange(of: vm.selectedAnnotationID) { _, id  in if id  != nil { activePanel = .text } }
            .onChange(of: vm.selectedSegmentID)    { _, id  in if id  != nil { activePanel = .zoom } }
            .onChange(of: vm.backgroundSettings)   { _,  _  in vm.hasUnsavedChanges = true }
            .onChange(of: vm.trimStart)            { _,  _  in vm.hasUnsavedChanges = true }
            .onChange(of: vm.trimEnd)              { _,  _  in vm.hasUnsavedChanges = true }
    }

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
        if !vm.projectName.isEmpty {
            return vm.projectName + (vm.hasUnsavedChanges ? " •" : "")
        }
        return vm.player != nil ? "Untitled •" : "ClipForge"
    }

    // MARK: - Columns

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VideoPlayerView(vm: vm)
                .frame(maxWidth: .infinity)

            if vm.player == nil {
                ContentUnavailableView(
                    "No Video",
                    systemImage: "film",
                    description: Text("Load a video to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TimelineView(vm: vm)
                    .padding(.top, 8)

                VisualTimelineView(vm: vm)
                    .padding(.top, 4)
                    .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                        case .zoom:   ZoomControlsView(vm: vm)
                        case .text:   AnnotationControlsView(vm: vm)
                        case .canvas: BackgroundControlsView(vm: vm)
                        case .clip:   ClipControlsView(vm: vm)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                }

                // ── Export progress ────────────────────────────────────────
                if vm.isExporting {
                    GroupBox {
                        HStack {
                            ProgressView()
                            Text("Exporting…").foregroundColor(.secondary)
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
        // Load video
        ToolbarItem(placement: .primaryAction) {
            #if canImport(UIKit)
            Menu {
                PhotosPicker(selection: $photosPickerItem,
                             matching: .videos, photoLibrary: .shared()) {
                    Label("From Photos", systemImage: "photo")
                }
                Button { importingProject = false; showFilePicker = true } label: {
                    Label("From Files", systemImage: "folder")
                }
            } label: {
                Label("Load Video", systemImage: "plus.circle")
            }
            #else
            Button { importingProject = false; showFilePicker = true } label: {
                Label("Load Video", systemImage: "plus.circle")
            }
            #endif
        }

        // Open project
        ToolbarItem(placement: .primaryAction) {
            Button { importingProject = true; showFilePicker = true } label: {
                Label("Open Project", systemImage: "folder.badge.plus")
            }
        }

        // Save
        ToolbarItem(placement: .primaryAction) {
            Button { handleSave() } label: {
                Label("Save", systemImage: vm.hasUnsavedChanges ? "square.and.pencil" : "square.and.arrow.down")
            }
            .disabled(vm.player == nil)
            .keyboardShortcut("s", modifiers: .command)
        }

        // Export
        ToolbarItem(placement: .primaryAction) {
            Button { vm.exportVideo() } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(vm.player == nil || vm.isExporting)
        }
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
