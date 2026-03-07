import SwiftUI

struct KeyframeListView: View {
    @ObservedObject var vm: ClipForgeViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {

            if !vm.segments.isEmpty {
                GroupBox(label: Label("Zoom Segments (\(vm.segments.count))",
                                     systemImage: "magnifyingglass")) {
                    List {
                        ForEach(vm.segments) { seg in
                            Button {
                                vm.selectedSegmentID = seg.id
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: seg.isEnabled ? "circle.fill" : "circle")
                                        .foregroundColor(seg.id == vm.selectedSegmentID ? .white : .purple)
                                        .font(.system(size: 8))
                                    Text(formatTime(seg.startTime))
                                        .monospacedDigit()
                                    Text("→")
                                        .foregroundColor(.secondary)
                                    Text(formatTime(seg.endTime))
                                        .monospacedDigit()
                                    Spacer()
                                    Text(String(format: "%.2f×", seg.scale))
                                        .foregroundColor(.purple)
                                    if !seg.isEnabled {
                                        Text("off")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(
                                seg.id == vm.selectedSegmentID
                                    ? Color.purple.opacity(0.2)
                                    : Color.clear
                            )
                        }
                        .onDelete { vm.removeSegment(at: $0) }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 140)
                }
                .padding(.horizontal)
            }

            if !vm.annotations.isEmpty {
                GroupBox(label: Label("Annotations (\(vm.annotations.count))",
                                     systemImage: "text.alignleft")) {
                    List {
                        ForEach(vm.annotations) { ann in
                            HStack(alignment: .top) {
                                Image(systemName: ann.kind.systemImage)
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ann.kind == .text ? ann.text : ann.kind.rawValue)
                                        .lineLimit(1)
                                    Text("\(formatTime(ann.startTime)) · \(String(format: "%.1f", ann.duration))s")
                                        .font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .font(.subheadline)
                        }
                        .onDelete { vm.deleteAnnotations(at: $0) }
                    }
                    .listStyle(.plain)
                    .frame(maxHeight: 140)
                }
                .padding(.horizontal)
            }
        }
    }

    private func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return String(format: "%d:%02d.%01d", m, s,
                      Int(t.truncatingRemainder(dividingBy: 1) * 10))
    }
}
