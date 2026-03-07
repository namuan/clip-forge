import SwiftUI

struct BackgroundControlsView: View {
    @ObservedObject var vm: VideoEditorViewModel

    // Local Color state for ColorPicker (two-way sync via onChange)
    @State private var startColor: Color = .purple
    @State private var endColor: Color   = .blue
    @State private var solidColor: Color = .black

    var body: some View {
        GroupBox(label: Label("Canvas", systemImage: "paintpalette")) {
            VStack(alignment: .leading, spacing: 12) {

                // ── Style picker ───────────────────────────────────────────
                Picker("", selection: $vm.backgroundSettings.style) {
                    ForEach(BackgroundStyle.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)

                // ── Presets ────────────────────────────────────────────────
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(BackgroundSettings.presets) { preset in
                            Button {
                                var s = preset.settings
                                s.paddingFraction = vm.backgroundSettings.paddingFraction
                                s.cornerRadius    = vm.backgroundSettings.cornerRadius
                                s.shadowOpacity   = vm.backgroundSettings.shadowOpacity
                                s.shadowRadius    = vm.backgroundSettings.shadowRadius
                                vm.backgroundSettings = s
                                syncColorState()
                            } label: {
                                presetSwatch(preset)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 2)
                }

                // ── Color pickers ──────────────────────────────────────────
                if vm.backgroundSettings.style == .gradient {
                    HStack {
                        ColorPicker("From", selection: $startColor)
                            .onChange(of: startColor) { _, c in
                                vm.backgroundSettings.gradientStart = c.toCodable()
                            }
                        ColorPicker("To", selection: $endColor)
                            .onChange(of: endColor) { _, c in
                                vm.backgroundSettings.gradientEnd = c.toCodable()
                            }
                    }
                } else if vm.backgroundSettings.style == .solid {
                    ColorPicker("Color", selection: $solidColor)
                        .onChange(of: solidColor) { _, c in
                            vm.backgroundSettings.solidColor = c.toCodable()
                        }
                }

                Divider()

                // ── Shape & shadow sliders ─────────────────────────────────
                LabeledSlider("Padding",   value: paddingPctBinding,                    in: 0...20,   format: "%.0f%%")
                LabeledSlider("Corners",   value: $vm.backgroundSettings.cornerRadius,  in: 0...40,   format: "%.0f pt")
                LabeledSlider("Shadow",    value: shadowPctBinding,                     in: 0...100,  format: "%.0f%%")
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
        .onAppear { syncColorState() }
        .onChange(of: vm.backgroundSettings.gradientStart) { _, _ in syncColorState() }
        .onChange(of: vm.backgroundSettings.gradientEnd)   { _, _ in syncColorState() }
        .onChange(of: vm.backgroundSettings.solidColor)    { _, _ in syncColorState() }
    }

    // MARK: - Helpers

    private func syncColorState() {
        startColor = vm.backgroundSettings.gradientStart.color
        endColor   = vm.backgroundSettings.gradientEnd.color
        solidColor = vm.backgroundSettings.solidColor.color
    }

    private var paddingPctBinding: Binding<CGFloat> {
        Binding(
            get: { vm.backgroundSettings.paddingFraction * 100 },
            set: { vm.backgroundSettings.paddingFraction = $0 / 100 }
        )
    }

    private var shadowPctBinding: Binding<CGFloat> {
        Binding(
            get: { CGFloat(vm.backgroundSettings.shadowOpacity) * 100 },
            set: { vm.backgroundSettings.shadowOpacity = Float($0 / 100) }
        )
    }

    @ViewBuilder
    private func presetSwatch(_ preset: BackgroundSettings.Preset) -> some View {
        let s = preset.settings
        let isSelected: Bool = {
            switch s.style {
            case .gradient:
                return vm.backgroundSettings.style == .gradient
                    && vm.backgroundSettings.gradientStart == s.gradientStart
                    && vm.backgroundSettings.gradientEnd   == s.gradientEnd
            case .solid:
                return vm.backgroundSettings.style == .solid
                    && vm.backgroundSettings.solidColor == s.solidColor
            case .transparent:
                return vm.backgroundSettings.style == .transparent
            }
        }()

        VStack(spacing: 4) {
            swatchGradient(preset.settings)
                .frame(width: 40, height: 26)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.white : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                )
            Text(preset.name)
                .font(.system(size: 9))
                .foregroundColor(isSelected ? .white : .secondary)
        }
    }

    @ViewBuilder
    private func swatchGradient(_ s: BackgroundSettings) -> some View {
        switch s.style {
        case .gradient:
            LinearGradient(
                colors: [s.gradientStart.color, s.gradientEnd.color],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        case .solid:
            s.solidColor.color
        case .transparent:
            Color(white: 0.3)
        }
    }
}
