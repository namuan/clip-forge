import SwiftUI

struct AnnotationControlsView: View {
    @ObservedObject var vm: VideoEditorViewModel

    var body: some View {
        VStack(spacing: 12) {
            // Editor only when something is selected
            if let ann = vm.selectedAnnotation {
                selectedAnnotationPanel(ann)
            }

            // Add panel is always visible
            addPanel
        }
    }

    // MARK: - Selected annotation editor

    private func selectedAnnotationPanel(_ ann: Annotation) -> some View {
        GroupBox(label:
            HStack {
                Label(ann.kind.rawValue, systemImage: ann.kind.systemImage)
                Spacer()
                Text(formatTime(ann.startTime) + " – " + formatTime(ann.startTime + ann.duration))
                    .font(.caption).monospacedDigit().foregroundColor(.secondary)
            }
        ) {
            VStack(alignment: .leading, spacing: 10) {

                if ann.kind == .text {
                    TextField("Text", text: textBinding(ann))
                        .textFieldStyle(.roundedBorder)
                }

                LabeledSlider("Duration", value: durationBinding(ann), in: 0.3...30, format: "%.1fs")

                if ann.kind == .text {
                    LabeledSlider("Position X", value: posXBinding(ann), in: 0...1, format: "%.2f")
                    LabeledSlider("Position Y", value: posYBinding(ann), in: 0...1, format: "%.2f")
                    Text("Tap video preview to reposition")
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    LabeledSlider("Start X", value: startXBinding(ann),   in: 0...1, format: "%.2f")
                    LabeledSlider("Start Y", value: startYBinding(ann),   in: 0...1, format: "%.2f")
                    LabeledSlider("End X",   value: endXBinding(ann),     in: 0...1, format: "%.2f")
                    LabeledSlider("End Y",   value: endYBinding(ann),     in: 0...1, format: "%.2f")
                    LabeledSlider("Width",   value: strokeWidthBinding(ann), in: 1...20, format: "%.0f pt")
                    ColorPicker("Color", selection: strokeColorBinding(ann))
                    Text("Drag on the video preview to redraw")
                        .font(.caption).foregroundColor(.secondary)
                }

                Divider()

                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        vm.removeAnnotation(id: ann.id)
                    } label: {
                        Label("Remove", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Deselect") {
                        vm.selectedAnnotationID = nil
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

    // MARK: - Add panel (always visible)

    private var addPanel: some View {
        GroupBox(label: Label("Add Annotation", systemImage: "plus.circle")) {
            VStack(alignment: .leading, spacing: 10) {

                Picker("", selection: $vm.pendingAnnotationKind) {
                    ForEach(AnnotationKind.allCases, id: \.self) { kind in
                        Label(kind.rawValue, systemImage: kind.systemImage).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                if vm.pendingAnnotationKind == .text {
                    TextField("Annotation text…", text: $vm.pendingAnnotationText)
                        .textFieldStyle(.roundedBorder)
                } else {
                    LabeledSlider("Width", value: $vm.pendingAnnotationStrokeWidth, in: 1...20, format: "%.0f pt")
                    ColorPicker("Color", selection: pendingStrokeColorBinding)
                    Text("Drag on the video preview to draw")
                        .font(.caption).foregroundColor(.secondary)
                }

                HStack {
                    Text("Duration")
                        .frame(width: 72, alignment: .leading)
                        .font(.subheadline)
                    Slider(value: $vm.pendingAnnotationDuration, in: 0.5...30)
                    Text(String(format: "%.1fs", vm.pendingAnnotationDuration))
                        .monospacedDigit().font(.subheadline)
                        .frame(width: 52, alignment: .trailing)
                }

                Button {
                    vm.addAnnotation()
                } label: {
                    let kindLabel = vm.pendingAnnotationKind == .text
                        ? "Text" : vm.pendingAnnotationKind.rawValue
                    Label("Add \(kindLabel) at \(formatTime(vm.currentTime))",
                          systemImage: "plus.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(vm.player == nil
                    || (vm.pendingAnnotationKind == .text
                        && vm.pendingAnnotationText.trimmingCharacters(in: .whitespaces).isEmpty))
            }
            .padding(.top, 4)
        }
        .padding(.horizontal)
    }

    // MARK: - Bindings — selected annotation

    private func textBinding(_ ann: Annotation) -> Binding<String> {
        Binding(get: { vm.selectedAnnotation?.text ?? ann.text },
                set: { vm.updateAnnotation(id: ann.id, text: $0) })
    }

    private func durationBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { vm.selectedAnnotation?.duration ?? ann.duration },
                set: { vm.updateAnnotation(id: ann.id, duration: $0) })
    }

    private func posXBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { Double(vm.selectedAnnotation?.position.x ?? ann.position.x) },
                set: {
                    let y = vm.selectedAnnotation?.position.y ?? ann.position.y
                    vm.updateAnnotation(id: ann.id, position: CGPoint(x: $0, y: y))
                })
    }

    private func posYBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { Double(vm.selectedAnnotation?.position.y ?? ann.position.y) },
                set: {
                    let x = vm.selectedAnnotation?.position.x ?? ann.position.x
                    vm.updateAnnotation(id: ann.id, position: CGPoint(x: x, y: $0))
                })
    }

    private func startXBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { Double(vm.selectedAnnotation?.position.x ?? ann.position.x) },
                set: {
                    let y = vm.selectedAnnotation?.position.y ?? ann.position.y
                    vm.updateAnnotation(id: ann.id, position: CGPoint(x: $0, y: y))
                })
    }

    private func startYBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { Double(vm.selectedAnnotation?.position.y ?? ann.position.y) },
                set: {
                    let x = vm.selectedAnnotation?.position.x ?? ann.position.x
                    vm.updateAnnotation(id: ann.id, position: CGPoint(x: x, y: $0))
                })
    }

    private func endXBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { Double(vm.selectedAnnotation?.endPosition.x ?? ann.endPosition.x) },
                set: {
                    let y = vm.selectedAnnotation?.endPosition.y ?? ann.endPosition.y
                    vm.updateAnnotation(id: ann.id, endPosition: CGPoint(x: $0, y: y))
                })
    }

    private func endYBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { Double(vm.selectedAnnotation?.endPosition.y ?? ann.endPosition.y) },
                set: {
                    let x = vm.selectedAnnotation?.endPosition.x ?? ann.endPosition.x
                    vm.updateAnnotation(id: ann.id, endPosition: CGPoint(x: x, y: $0))
                })
    }

    private func strokeWidthBinding(_ ann: Annotation) -> Binding<CGFloat> {
        Binding(get: { vm.selectedAnnotation?.strokeWidth ?? ann.strokeWidth },
                set: { vm.updateAnnotation(id: ann.id, strokeWidth: $0) })
    }

    private func strokeColorBinding(_ ann: Annotation) -> Binding<Color> {
        Binding(get: { (vm.selectedAnnotation?.strokeColor ?? ann.strokeColor).color },
                set: { vm.updateAnnotation(id: ann.id, strokeColor: $0.toCodable()) })
    }

    // MARK: - Binding — pending stroke color

    private var pendingStrokeColorBinding: Binding<Color> {
        Binding(get: { vm.pendingAnnotationStrokeColor.color },
                set: { vm.pendingAnnotationStrokeColor = $0.toCodable() })
    }

    // MARK: - Helpers

    private func formatTime(_ t: Double) -> String {
        let m = Int(t) / 60; let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }
}
