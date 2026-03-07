import SwiftUI

struct ClipControlsView: View {
    @ObservedObject var vm: ClipForgeViewModel

    var body: some View {
        VStack(spacing: 12) {
            // ── Trim ────────────────────────────────────────────────────────
            GroupBox(label: Label("Trim", systemImage: "scissors")) {
                VStack(spacing: 10) {
                    LabeledSlider("In",  value: trimStartBinding,
                                  in: 0...max(0, vm.effectiveTrimEnd - 0.1), format: "%.2fs")
                    LabeledSlider("Out", value: trimEndBinding,
                                  in: min(vm.duration, vm.trimStart + 0.1)...vm.duration, format: "%.2fs")

                    HStack {
                        Text("Duration")
                            .font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Text(String(format: "%.2fs", vm.effectiveTrimEnd - vm.trimStart))
                            .monospacedDigit().font(.subheadline)
                    }

                    Button("Reset Trim") {
                        vm.trimStart = 0; vm.trimEnd = nil
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.trimStart == 0 && vm.trimEnd == nil)
                }
                .padding(.top, 4)
            }

            // ── Speed ────────────────────────────────────────────────────────
            GroupBox(label: Label("Speed", systemImage: "gauge.with.needle")) {
                VStack(spacing: 10) {
                    LabeledSlider("Speed", value: $vm.playbackSpeed,
                                  in: 0.25...4.0, format: "%.2f×")
                        .onChange(of: vm.playbackSpeed) { _, s in
                            if vm.isPlaying { vm.player?.rate = Float(s) }
                        }

                    HStack(spacing: 8) {
                        ForEach([0.5, 1.0, 1.5, 2.0, 4.0], id: \.self) { s in
                            Button(s == 1.0 ? "1×" : String(format: "%.1g×", s)) {
                                vm.setSpeed(s)
                            }
                            .buttonStyle(.bordered)
                            .tint(abs(vm.playbackSpeed - s) < 0.01 ? .accentColor : nil)
                        }
                    }
                    .font(.subheadline)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal)
    }

    // MARK: - Trim bindings

    private var trimStartBinding: Binding<Double> {
        Binding(
            get: { vm.trimStart },
            set: { vm.trimStart = min($0, vm.effectiveTrimEnd - 0.1) }
        )
    }

    private var trimEndBinding: Binding<Double> {
        Binding(
            get: { vm.effectiveTrimEnd },
            set: { new in
                vm.trimEnd = new >= vm.duration - 0.01 ? nil : max(new, vm.trimStart + 0.1)
            }
        )
    }
}
