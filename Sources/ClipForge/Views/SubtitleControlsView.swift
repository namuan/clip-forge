import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif
#if canImport(UIKit)
import UIKit
#endif

struct SubtitleControlsView: View {
    @ObservedObject var vm: ClipForgeViewModel
    @State private var customPresetName: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // ── Language & Generate ───────────────────────────────────────
            languageSection

            stylePresetSection

            styleEditorSection

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
        .onAppear {
            vm.refreshSubtitleLocaleOptionsIfNeeded()
        }
    }

    // MARK: - Language section

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Language")
                .font(.caption)
                .foregroundColor(.secondary)

            if vm.isLoadingSubtitleLocales {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Checking offline models…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Picker("", selection: $vm.subtitleLocaleID) {
                if vm.subtitleLocaleOptions.isEmpty {
                    Text("No offline languages available").tag("")
                } else {
                    ForEach(vm.subtitleLocaleOptions) { option in
                        Text(option.name).tag(option.id)
                    }
                }
            }
            .labelsHidden()
            .disabled(vm.isGeneratingSubtitles || vm.isLoadingSubtitleLocales || vm.subtitleLocaleOptions.isEmpty)

            if vm.subtitleLocaleOptions.isEmpty, !vm.isLoadingSubtitleLocales {
                Text("No downloaded offline speech models found.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Generate section

    private var stylePresetSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style Presets")
                .font(.caption)
                .foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    presetButton(
                        title: "Default",
                        preset: .classic,
                        tint: .gray,
                        foreground: .white
                    )

                    presetButton(
                        title: "TikTok",
                        preset: .tikTok,
                        tint: .black,
                        foreground: .white
                    )

                    presetButton(
                        title: "TikTok Yellow",
                        preset: .tikTokYellow,
                        tint: .yellow,
                        foreground: .black
                    )
                }
            }

            if !vm.customSubtitlePresets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(vm.customSubtitlePresets) { preset in
                            customPresetButton(preset)
                        }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Preset name", text: $customPresetName)
                    .textFieldStyle(.roundedBorder)

                Button("Save Preset") {
                    vm.saveCurrentSubtitleStyleAsPreset(named: customPresetName)
                    customPresetName = ""
                }
                .buttonStyle(.bordered)
                .disabled(customPresetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func presetButton(
        title: String,
        preset: SubtitleStylePreset,
        tint: Color,
        foreground: Color
    ) -> some View {
        let isSelected = vm.subtitleStylePreset == preset

        return Button {
            vm.selectSubtitleStylePreset(preset)
        } label: {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                }
                Text(title)
                    .font(.caption.weight(.semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(minHeight: 28)
            .foregroundStyle(isSelected ? foreground : .secondary)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? tint : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(
                        isSelected ? tint.opacity(0.95) : Color.primary.opacity(0.2),
                        lineWidth: isSelected ? 2.2 : 1
                    )
            )
            .shadow(color: isSelected ? tint.opacity(0.55) : .clear, radius: 8)
            .opacity(isSelected ? 1 : 0.55)
        }
        .buttonStyle(.plain)
    }

    private func customPresetButton(_ preset: CustomSubtitlePreset) -> some View {
        let isSelected = vm.selectedCustomSubtitlePresetID == preset.id

        return HStack(spacing: 6) {
            Button {
                vm.applyCustomSubtitlePreset(id: preset.id)
            } label: {
                HStack(spacing: 6) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption)
                    }
                    Text(preset.name)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : .primary)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.16), lineWidth: isSelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)

            Button(role: .destructive) {
                vm.deleteCustomSubtitlePreset(id: preset.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var styleEditorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Style Properties")
                .font(.caption)
                .foregroundColor(.secondary)

            Picker("Font", selection: fontNameBinding) {
                ForEach(availableFontNames, id: \.self) { name in
                    Text(name).tag(name)
                }
            }

            Toggle("Auto scale to fit video width", isOn: autoScaleToFitBinding)
                .font(.caption)

            LabeledSlider("Font Size", value: fontSizeBinding, in: 12...120, format: "%.0f")
            LabeledSlider("Outline Width", value: outlineWidthBinding, in: 0...12, format: "%.1f")
            LabeledSlider("Background Opacity", value: backgroundOpacityBinding, in: 0...1, format: "%.2f")
            LabeledSlider("Background Padding", value: backgroundPaddingBinding, in: 0...40, format: "%.0f")
            LabeledSlider("Shadow Blur", value: shadowBlurBinding, in: 0...20, format: "%.1f")
            LabeledSlider("Shadow Offset X", value: shadowOffsetXBinding, in: -20...20, format: "%.1f")
            LabeledSlider("Shadow Offset Y", value: shadowOffsetYBinding, in: -20...20, format: "%.1f")
            LabeledSlider("Vertical Position", value: verticalPositionBinding, in: 0.05...0.95, format: "%.2f")
            LabeledSlider("Horizontal Margin", value: horizontalMarginBinding, in: 0...0.3, format: "%.2f")

            HStack(spacing: 12) {
                ColorPicker("Text Color", selection: textColorBinding)
                ColorPicker("Outline Color", selection: outlineColorBinding)
                ColorPicker("Background Color", selection: backgroundColorBinding)
                ColorPicker("Shadow Color", selection: shadowColorBinding)
            }
            .font(.caption)
        }
    }

    private var fontNameBinding: Binding<String> {
        Binding(
            get: { vm.subtitleStyle.fontName },
            set: { value in vm.updateSubtitleStyle { $0.fontName = value } }
        )
    }

    private var autoScaleToFitBinding: Binding<Bool> {
        Binding(
            get: { vm.subtitleStyle.autoScaleToFit },
            set: { value in vm.updateSubtitleStyle { $0.autoScaleToFit = value } }
        )
    }

    private var fontSizeBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.fontSize) },
            set: { value in vm.updateSubtitleStyle { $0.fontSize = CGFloat(value) } }
        )
    }

    private var outlineWidthBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.outlineWidth) },
            set: { value in vm.updateSubtitleStyle { $0.outlineWidth = CGFloat(value) } }
        )
    }

    private var backgroundOpacityBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.backgroundOpacity) },
            set: { value in vm.updateSubtitleStyle { $0.backgroundOpacity = CGFloat(value).clamped(to: 0...1) } }
        )
    }

    private var backgroundPaddingBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.backgroundPadding) },
            set: { value in vm.updateSubtitleStyle { $0.backgroundPadding = CGFloat(value) } }
        )
    }

    private var shadowBlurBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.shadowBlur) },
            set: { value in vm.updateSubtitleStyle { $0.shadowBlur = CGFloat(value) } }
        )
    }

    private var shadowOffsetXBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.shadowOffset.width) },
            set: { value in
                vm.updateSubtitleStyle { style in
                    style.shadowOffset = CGSize(width: CGFloat(value), height: style.shadowOffset.height)
                }
            }
        )
    }

    private var shadowOffsetYBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.shadowOffset.height) },
            set: { value in
                vm.updateSubtitleStyle { style in
                    style.shadowOffset = CGSize(width: style.shadowOffset.width, height: CGFloat(value))
                }
            }
        )
    }

    private var verticalPositionBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.verticalPosition) },
            set: { value in vm.updateSubtitleStyle { $0.verticalPosition = CGFloat(value).clamped(to: 0.05...0.95) } }
        )
    }

    private var horizontalMarginBinding: Binding<Double> {
        Binding(
            get: { Double(vm.subtitleStyle.horizontalMargin) },
            set: { value in vm.updateSubtitleStyle { $0.horizontalMargin = CGFloat(value).clamped(to: 0...0.3) } }
        )
    }

    private var textColorBinding: Binding<Color> {
        Binding(
            get: { vm.subtitleStyle.textColor.color },
            set: { color in vm.updateSubtitleStyle { $0.textColor = color.toCodable() } }
        )
    }

    private var outlineColorBinding: Binding<Color> {
        Binding(
            get: { vm.subtitleStyle.outlineColor.color },
            set: { color in vm.updateSubtitleStyle { $0.outlineColor = color.toCodable() } }
        )
    }

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { vm.subtitleStyle.backgroundColor.color },
            set: { color in vm.updateSubtitleStyle { $0.backgroundColor = color.toCodable() } }
        )
    }

    private var shadowColorBinding: Binding<Color> {
        Binding(
            get: { vm.subtitleStyle.shadowColor.color },
            set: { color in vm.updateSubtitleStyle { $0.shadowColor = color.toCodable() } }
        )
    }

    private var availableFontNames: [String] {
        #if canImport(AppKit)
        let names = NSFontManager.shared.availableFonts
        #elseif canImport(UIKit)
        let names = UIFont.familyNames
            .flatMap { UIFont.fontNames(forFamilyName: $0) }
        #else
        let names: [String] = []
        #endif

        let sorted = names.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        let current = vm.subtitleStyle.fontName
        if sorted.contains(current) {
            return sorted
        }
        return [current] + sorted
    }

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
            .disabled(vm.isGeneratingSubtitles || vm.isLoadingSubtitleLocales || vm.subtitleLocaleOptions.isEmpty)

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
