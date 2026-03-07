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

    @State private var showFilePicker = false
    @State private var showShareSheet = false
    @State private var activePanel: ControlPanel = .zoom

    #if canImport(UIKit)
    @State private var photosPickerItem: PhotosPickerItem?
    #endif

    var body: some View {
        NavigationStack {
            Group {
                #if canImport(AppKit)
                HSplitView {
                    leftColumn
                        .frame(minWidth: 360, maxWidth: .infinity)
                    rightColumn
                        .frame(minWidth: 200, maxWidth: 480)
                }
                #else
                HStack(spacing: 0) {
                    leftColumn
                    Divider()
                    rightColumn
                }
                #endif
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
                    .padding(.top, 8)

                    // ── Keyframe & annotation lists ────────────────────────
                    KeyframeListView(vm: vm)
                        .padding(.top, 4)
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
