import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct TimelineView: View {
    @ObservedObject var vm: ClipForgeViewModel

    #if canImport(AppKit)
    @State private var keyMonitor: Any?
    #endif

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
                // bare ← handled by NSEvent monitor below (skips when text field focused)

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
                // bare → handled by NSEvent monitor below (skips when text field focused)

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
        #if canImport(AppKit)
        .onAppear  { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
        #endif
    }

    #if canImport(AppKit)
    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Only handle bare left / right (no modifiers)
            guard event.modifierFlags
                    .intersection(.deviceIndependentFlagsMask)
                    .isEmpty
            else { return event }

            // Pass through when any text view has first responder
            if NSApp.keyWindow?.firstResponder is NSTextView { return event }

            switch event.keyCode {
            case 123: vm.stepBack();    return nil   // ←
            case 124: vm.stepForward(); return nil   // →
            default:  return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let m = keyMonitor { NSEvent.removeMonitor(m) }
        keyMonitor = nil
    }
    #endif

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
