import SwiftUI

struct TimelineView: View {
    @ObservedObject var vm: ClipForgeViewModel

    var body: some View {
        VStack(spacing: 6) {
            Slider(
                value: Binding(
                    get: { vm.currentTime },
                    set: { t in
                        vm.currentTime = t
                        vm.seek(to: t)
                    }
                ),
                in: 0...max(vm.duration, 0.01)
            )

            HStack {
                Text(formatTime(vm.currentTime))
                    .monospacedDigit()
                    .font(.caption)
                Spacer()
                Text(formatTime(vm.duration))
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 24) {
                Spacer()

                TransportButton(systemImage: "backward.end.fill", size: 18) {
                    vm.seek(to: 0)
                    vm.currentTime = 0
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])

                TransportButton(systemImage: "backward.frame.fill", size: 20) {
                    vm.stepBack()
                }
                .keyboardShortcut(.leftArrow, modifiers: [])

                TransportButton(
                    systemImage: vm.isPlaying ? "pause.fill" : "play.fill",
                    size: 28
                ) {
                    vm.togglePlayPause()
                }
                .keyboardShortcut(" ", modifiers: [])

                TransportButton(systemImage: "forward.frame.fill", size: 20) {
                    vm.stepForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [])

                TransportButton(systemImage: "forward.end.fill", size: 18) {
                    vm.seek(to: vm.duration)
                    vm.currentTime = vm.duration
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])

                Spacer()
            }
            .disabled(vm.player == nil)
        }
        .padding(.horizontal)
    }

    private func formatTime(_ t: Double) -> String {
        let t = max(0, t)
        let m = Int(t) / 60
        let s = Int(t) % 60
        let ms = Int((t - Double(Int(t))) * 10)
        return String(format: "%d:%02d.%d", m, s, ms)
    }
}

// MARK: - Reusable transport button

private struct TransportButton: View {
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 12, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }
}
