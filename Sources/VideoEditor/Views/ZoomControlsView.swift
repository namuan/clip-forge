import SwiftUI

struct ZoomControlsView: View {
    @ObservedObject var vm: VideoEditorViewModel

    var body: some View {
        if let seg = vm.selectedSegment {
            selectedSegmentPanel(seg)
        } else {
            emptyStatePanel
        }
    }

    // MARK: - Selected segment editor

    private func selectedSegmentPanel(_ seg: ZoomSegment) -> some View {
        GroupBox(label:
            HStack {
                Label("Zoom", systemImage: "magnifyingglass")
                Spacer()
                Text(formatTime(seg.startTime) + " – " + formatTime(seg.endTime))
                    .font(.caption).monospacedDigit().foregroundColor(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {

                LabeledSlider("Scale", value: scaleBinding(seg),     in: 0.25...3.0, format: "%.2f×")
                LabeledSlider("Center X", value: centerXBinding(seg), in: 0...1,     format: "%.2f")
                LabeledSlider("Center Y", value: centerYBinding(seg), in: 0...1,     format: "%.2f")

                Divider()

                LabeledSlider("Ease In",  value: easeInBinding(seg),  in: 0...2,     format: "%.1fs")
                LabeledSlider("Ease Out", value: easeOutBinding(seg), in: 0...2,     format: "%.1fs")

                Divider()

                HStack(spacing: 10) {
                    Button {
                        vm.toggleSegmentEnabled(id: seg.id)
                    } label: {
                        Label(seg.isEnabled ? "Disable" : "Enable",
                              systemImage: seg.isEnabled ? "eye.slash" : "eye")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        vm.removeSegment(id: seg.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Deselect") {
                        vm.selectedSegmentID = nil
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.secondary)
                }
                .font(.subheadline)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    // MARK: - Empty state

    private var emptyStatePanel: some View {
        GroupBox(label: Label("Zoom", systemImage: "magnifyingglass")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Click on the **Zoom** row in the timeline to add a zoom, or use the button below.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    vm.addZoomSegment()
                } label: {
                    Label("Add Zoom at \(formatTime(vm.currentTime))", systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.player == nil)
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    // MARK: - Bindings into the segment array

    private func scaleBinding(_ seg: ZoomSegment) -> Binding<CGFloat> {
        Binding(get: { vm.selectedSegment?.scale ?? seg.scale },
                set: { vm.updateSegment(id: seg.id, scale: $0) })
    }

    private func centerXBinding(_ seg: ZoomSegment) -> Binding<CGFloat> {
        Binding(get: { vm.selectedSegment?.center.x ?? seg.center.x },
                set: { vm.updateSegment(id: seg.id, center: CGPoint(x: $0, y: vm.selectedSegment?.center.y ?? seg.center.y)) })
    }

    private func centerYBinding(_ seg: ZoomSegment) -> Binding<CGFloat> {
        Binding(get: { vm.selectedSegment?.center.y ?? seg.center.y },
                set: { vm.updateSegment(id: seg.id, center: CGPoint(x: vm.selectedSegment?.center.x ?? seg.center.x, y: $0)) })
    }

    private func easeInBinding(_ seg: ZoomSegment) -> Binding<Double> {
        Binding(get: { vm.selectedSegment?.easeIn ?? seg.easeIn },
                set: { vm.updateSegment(id: seg.id, easeIn: $0) })
    }

    private func easeOutBinding(_ seg: ZoomSegment) -> Binding<Double> {
        Binding(get: { vm.selectedSegment?.easeOut ?? seg.easeOut },
                set: { vm.updateSegment(id: seg.id, easeOut: $0) })
    }

    private func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Reusable labeled slider (generic over any BinaryFloatingPoint)

struct LabeledSlider<V: BinaryFloatingPoint>: View where V.Stride: BinaryFloatingPoint {
    let title: String
    @Binding var value: V
    let range: ClosedRange<V>
    let format: String

    init(_ title: String, value: Binding<V>, in range: ClosedRange<V>, format: String) {
        self.title = title; self._value = value; self.range = range; self.format = format
    }

    var body: some View {
        HStack {
            Text(title)
                .frame(width: 72, alignment: .leading)
                .font(.subheadline)
            Slider(value: $value, in: range)
            Text(String(format: format, Double(value)))
                .monospacedDigit()
                .font(.subheadline)
                .frame(width: 60, alignment: .trailing)
        }
    }
}
