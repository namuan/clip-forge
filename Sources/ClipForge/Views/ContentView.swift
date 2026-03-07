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

    @State private var showFilePicker  = false
    @State private var showShareSheet  = false
    @State private var activePanel: ControlPanel = .zoom

    #if canImport(UIKit)
    @State private var photosPickerItem: PhotosPickerItem?
    #endif

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {

                    // ── Video preview ──────────────────────────────────────
                    VideoPlayerView(vm: vm)
                        .padding(.horizontal)
                        .padding(.top, 8)

                    // ── Empty state ────────────────────────────────────────
                    if vm.player == nil {
                        ContentUnavailableView(
                            "No Video",
                            systemImage: "film",
                            description: Text("Tap \"Load Video\" to get started.")
                        )
                        .frame(height: 160)
                        .padding(.horizontal)
                    }

                    if vm.player != nil {

                        // ── Transport + scrub ──────────────────────────────
                        TimelineView(vm: vm)
                            .padding(.top, 10)

                        // ── Visual keyframe / annotation timeline ──────────
                        VisualTimelineView(vm: vm)
                            .padding(.top, 6)

                        Divider().padding(.vertical, 12)

                        // ── Control panel tabs ─────────────────────────────
                        Picker("", selection: $activePanel) {
                            ForEach(ControlPanel.allCases, id: \.self) { panel in
                                Label(panel.rawValue, systemImage: panel.icon).tag(panel)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)

                        // ── Active panel ───────────────────────────────────
                        Group {
                            switch activePanel {
                            case .zoom:
                                ZoomControlsView(vm: vm)
                            case .text:
                                AnnotationControlsView(vm: vm)
                            case .canvas:
                                BackgroundControlsView(vm: vm)
                            case .clip:
                                ClipControlsView(vm: vm)
                            }
                        }
                        .padding(.top, 8)

                        // ── Keyframe & annotation lists ────────────────────
                        KeyframeListView(vm: vm)
                            .padding(.top, 4)
                    }

                    // ── Export progress ────────────────────────────────────
                    if vm.isExporting {
                        GroupBox {
                            HStack {
                                ProgressView()
                                Text("Exporting…").foregroundColor(.secondary)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }

                    Spacer(minLength: 32)
                }
            }
            .navigationTitle("ClipForge")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { toolbarContent }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.movie, .video,
                                  UTType(filenameExtension: "mp4")!,
                                  UTType(filenameExtension: "mov")!,
                                  UTType(filenameExtension: "m4v")!],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            loadFromURL(url)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = vm.exportURL { ShareSheet(url: url) }
        }
        .alert("Error", isPresented: $vm.showAlert, actions: {
            Button("OK", role: .cancel) {}
        }, message: {
            Text(vm.alertMessage ?? "")
        })
        .onChange(of: vm.exportURL) { _, url in if url != nil { showShareSheet = true } }
        #if canImport(UIKit)
        .onChange(of: photosPickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let tmp = FileManager.default.temporaryDirectory
                        .appendingPathComponent(UUID().uuidString + ".mp4")
                    try? data.write(to: tmp)
                    await MainActor.run { loadFromURL(tmp) }
                }
            }
        }
        #endif
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            #if canImport(UIKit)
            Menu {
                PhotosPicker(selection: $photosPickerItem,
                             matching: .videos, photoLibrary: .shared()) {
                    Label("From Photos", systemImage: "photo")
                }
                Button { showFilePicker = true } label: {
                    Label("From Files", systemImage: "folder")
                }
            } label: {
                Label("Load Video", systemImage: "plus.circle")
            }
            #else
            Button { showFilePicker = true } label: {
                Label("Load Video", systemImage: "plus.circle")
            }
            #endif
        }

        ToolbarItem(placement: .primaryAction) {
            Button { vm.exportVideo() } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(vm.player == nil || vm.isExporting)
        }
    }

    // MARK: - Load helper

    private func loadFromURL(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(url.pathExtension)
        try? FileManager.default.copyItem(at: url, to: dest)
        if accessing { url.stopAccessingSecurityScopedResource() }
        vm.loadVideo(url: dest)
    }
}
