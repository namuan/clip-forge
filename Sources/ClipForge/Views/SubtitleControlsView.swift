import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SubtitleControlsView: View {
    @ObservedObject var vm: ClipForgeViewModel

    /// Common locales offered in the picker. Empty identifier = device locale.
    private let localeOptions: [(id: String, name: String)] = [
        ("",      "Device Default"),
        ("en-US", "English (US)"),
        ("en-GB", "English (UK)"),
        ("de-DE", "Deutsch"),
        ("fr-FR", "Français"),
        ("es-ES", "Español"),
        ("ja-JP", "日本語"),
        ("zh-Hans", "中文 (简体)"),
        ("ko-KR", "한국어"),
        ("it-IT", "Italiano"),
        ("pt-BR", "Português (BR)"),
        ("ru-RU", "Русский"),
        ("ar-SA", "العربية"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Language & Generate ───────────────────────────────────────
            languageSection

            Divider()

            generateSection

            // ── Results ───────────────────────────────────────────────────
            if !vm.subtitles.isEmpty {
                Divider()
                subtitleListSection
                Divider()
                exportSection
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Language section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Language")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("", selection: $vm.subtitleLocaleID) {
                ForEach(localeOptions, id: \.id) { option in
                    Text(option.name).tag(option.id)
                }
            }
            .labelsHidden()
            .disabled(vm.isGeneratingSubtitles)
        }
    }

    // MARK: - Generate section

    private var generateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                CFLogInfo("SubtitleControlsView: Generate button tapped")
                vm.generateSubtitles()
            } label: {
                Label(
                    vm.isGeneratingSubtitles ? "Generating…" : "Generate Subtitles",
                    systemImage: "waveform.badge.mic"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.isGeneratingSubtitles)

            // Progress
            if vm.isGeneratingSubtitles {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text(vm.subtitleProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !vm.subtitleProgress.isEmpty, vm.subtitleError == nil {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text(vm.subtitleProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            // Error
            if let err = vm.subtitleError {
                Label(err, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Subtitle list section

    private var subtitleListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Subtitles (\(vm.subtitles.count))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Toggle("Burn into export", isOn: $vm.includeSubtitlesInExport)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach($vm.subtitles) { $subtitle in
                        SubtitleRowView(subtitle: $subtitle, onDelete: {
                            vm.removeSubtitle(id: subtitle.id)
                        })
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 240)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.1)))
        }
    }

    // MARK: - Export / Clear section

    private var exportSection: some View {
        HStack(spacing: 8) {
            Button {
                saveSRTFile()
            } label: {
                Label("Save .srt", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.bordered)
            .disabled(vm.subtitles.isEmpty)
            .help("Save subtitle file (.srt) to disk")

            Spacer()

            Button(role: .destructive) {
                CFLogInfo("SubtitleControlsView: Clear subtitles tapped")
                vm.clearSubtitles()
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .buttonStyle(.bordered)
            .help("Remove all generated subtitles")
        }
    }

    // MARK: - Save SRT

    private func saveSRTFile() {
        guard let sourceURL = vm.makeSRTFileURL() else {
            CFLogError("SubtitleControlsView: makeSRTFileURL returned nil")
            vm.showError("Could not generate subtitle file.")
            return
        }
        CFLogInfo("SubtitleControlsView: Presenting save panel for SRT: \(sourceURL.lastPathComponent)")
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = vm.videoOriginalName.isEmpty
            ? "subtitles.srt"
            : (vm.videoOriginalName as NSString).deletingPathExtension + ".srt"
        panel.allowedContentTypes = [UTType(filenameExtension: "srt") ?? .plainText]
        guard panel.runModal() == .OK, let destURL = panel.url else {
            CFLogDebug("SubtitleControlsView: SRT save cancelled by user")
            try? FileManager.default.removeItem(at: sourceURL)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destURL)
            try FileManager.default.copyItem(at: sourceURL, to: destURL)
            CFLogInfo("SubtitleControlsView: SRT saved to \(destURL.path)")
        } catch {
            CFLogError("SubtitleControlsView: Failed to save SRT: \(error.localizedDescription)")
            vm.showError(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: sourceURL)
        #endif
    }
}

// MARK: - Subtitle Row

/// A single editable row in the subtitle list.
private struct SubtitleRowView: View {
    @Binding var subtitle: SubtitleSegment
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp badge
            Text(timeLabel)
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 3))
                .frame(minWidth: 80, alignment: .center)
                .padding(.top, 4)

            // Editable text
            TextField("Subtitle text", text: $subtitle.text, axis: .vertical)
                .font(.system(.caption, design: .default))
                .textFieldStyle(.plain)
                .lineLimit(1...3)

            // Delete button
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .help("Delete this subtitle")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var timeLabel: String {
        "\(formatTimecode(subtitle.start))–\(formatTimecode(subtitle.end))"
    }

    private func formatTimecode(_ seconds: TimeInterval) -> String {
        let s = max(0, seconds)
        let m = Int(s / 60)
        let sec = s.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", m, sec)
    }
}
