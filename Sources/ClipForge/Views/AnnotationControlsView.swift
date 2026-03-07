import SwiftUI

struct AnnotationControlsView: View {
    @ObservedObject var vm: ClipForgeViewModel

    private enum Field: Hashable { case editText, addText }
    @FocusState private var focusedField: Field?

    var body: some View {
        VStack(spacing: 12) {
            // Editor only when something is selected
            if let ann = vm.selectedAnnotation {
                selectedAnnotationPanel(ann)
            }

            // Add panel is always visible
            addPanel
        }
        .focusedValue(\.anyTextFieldFocused, focusedField != nil)
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
                        .focused($focusedField, equals: .editText)
                }

                LabeledSlider("Duration", value: durationBinding(ann), in: 0.3...30, format: "%.1fs")

                if ann.kind == .text {
                    LabeledSlider("Position X", value: posXBinding(ann), in: 0...1, format: "%.2f")
                    LabeledSlider("Position Y", value: posYBinding(ann), in: 0...1, format: "%.2f")
                    Text("Tap video preview to reposition")
                        .font(.caption).foregroundColor(.secondary)

                    Divider()

                    // ── Text styling ───────────────────────────────────────
                    Picker("", selection: fontWeightBinding(ann)) {
                        ForEach(TextFontWeight.allCases, id: \.self) { w in
                            Text(w.rawValue).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledSlider("Size", value: fontSizePctBinding(ann), in: 1...8, format: "%.1f%%")

                    ColorPicker("Text Color", selection: textColorBinding(ann))

                    Divider()

                    // ── Background box ─────────────────────────────────────
                    Toggle("Background Box", isOn: showBgBinding(ann))

                    let showBg = vm.selectedAnnotation?.showBackground ?? ann.showBackground
                    if showBg {
                        ColorPicker("BG Color", selection: bgColorBinding(ann))
                        LabeledSlider("Opacity", value: bgOpacityPctBinding(ann), in: 0...100, format: "%.0f%%")
                        LabeledSlider("Corners", value: bgCornerBinding(ann),     in: 0...30,  format: "%.0f pt")
                    }
                } else {
                    LabeledSlider("Start X", value: startXBinding(ann),      in: 0...1,  format: "%.2f")
                    LabeledSlider("Start Y", value: startYBinding(ann),      in: 0...1,  format: "%.2f")
                    LabeledSlider("End X",   value: endXBinding(ann),        in: 0...1,  format: "%.2f")
                    LabeledSlider("End Y",   value: endYBinding(ann),        in: 0...1,  format: "%.2f")
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
                        .focused($focusedField, equals: .addText)

                    Divider()

                    // ── Text styling ───────────────────────────────────────
                    Picker("", selection: $vm.pendingFontWeight) {
                        ForEach(TextFontWeight.allCases, id: \.self) { w in
                            Text(w.rawValue).tag(w)
                        }
                    }
                    .pickerStyle(.segmented)

                    LabeledSlider("Size", value: pendingFontSizePctBinding, in: 1...8, format: "%.1f%%")

                    ColorPicker("Text Color", selection: pendingTextColorBinding)

                    Divider()

                    Toggle("Background Box", isOn: $vm.pendingShowBackground)

                    if vm.pendingShowBackground {
                        ColorPicker("BG Color", selection: pendingBgColorBinding)
                        LabeledSlider("Opacity", value: pendingBgOpacityPctBinding, in: 0...100, format: "%.0f%%")
                        LabeledSlider("Corners", value: $vm.pendingBackgroundCornerRadius,        in: 0...30,  format: "%.0f pt")
                    }
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

    // MARK: - Bindings — selected annotation text styling

    private func fontWeightBinding(_ ann: Annotation) -> Binding<TextFontWeight> {
        Binding(get: { vm.selectedAnnotation?.fontWeight ?? ann.fontWeight },
                set: { vm.updateAnnotation(id: ann.id, fontWeight: $0) })
    }

    private func fontSizePctBinding(_ ann: Annotation) -> Binding<CGFloat> {
        Binding(get: { (vm.selectedAnnotation?.fontSize ?? ann.fontSize) * 100 },
                set: { vm.updateAnnotation(id: ann.id, fontSize: $0 / 100) })
    }

    private func textColorBinding(_ ann: Annotation) -> Binding<Color> {
        Binding(get: { (vm.selectedAnnotation?.textColor ?? ann.textColor).color },
                set: { vm.updateAnnotation(id: ann.id, textColor: $0.toCodable()) })
    }

    private func showBgBinding(_ ann: Annotation) -> Binding<Bool> {
        Binding(get: { vm.selectedAnnotation?.showBackground ?? ann.showBackground },
                set: { vm.updateAnnotation(id: ann.id, showBackground: $0) })
    }

    private func bgColorBinding(_ ann: Annotation) -> Binding<Color> {
        Binding(get: { (vm.selectedAnnotation?.backgroundColor ?? ann.backgroundColor).color },
                set: { vm.updateAnnotation(id: ann.id, backgroundColor: $0.toCodable()) })
    }

    private func bgOpacityPctBinding(_ ann: Annotation) -> Binding<Double> {
        Binding(get: { (vm.selectedAnnotation?.backgroundOpacity ?? ann.backgroundOpacity) * 100 },
                set: { vm.updateAnnotation(id: ann.id, backgroundOpacity: $0 / 100) })
    }

    private func bgCornerBinding(_ ann: Annotation) -> Binding<CGFloat> {
        Binding(get: { vm.selectedAnnotation?.backgroundCornerRadius ?? ann.backgroundCornerRadius },
                set: { vm.updateAnnotation(id: ann.id, backgroundCornerRadius: $0) })
    }

    // MARK: - Bindings — pending text styling

    private var pendingTextColorBinding: Binding<Color> {
        Binding(get: { vm.pendingTextColor.color },
                set: { vm.pendingTextColor = $0.toCodable() })
    }

    private var pendingBgColorBinding: Binding<Color> {
        Binding(get: { vm.pendingBackgroundColor.color },
                set: { vm.pendingBackgroundColor = $0.toCodable() })
    }

    private var pendingFontSizePctBinding: Binding<CGFloat> {
        Binding(get: { vm.pendingFontSize * 100 },
                set: { vm.pendingFontSize = $0 / 100 })
    }

    private var pendingBgOpacityPctBinding: Binding<Double> {
        Binding(get: { vm.pendingBackgroundOpacity * 100 },
                set: { vm.pendingBackgroundOpacity = $0 / 100 })
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
