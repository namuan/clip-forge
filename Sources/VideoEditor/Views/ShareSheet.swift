import SwiftUI

#if canImport(UIKit)
import UIKit

struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#elseif canImport(AppKit)
import AppKit

/// On macOS we open a save panel instead of a share sheet.
struct ShareSheet: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("Export Complete")
                .font(.title2.bold())
            Text(url.lastPathComponent)
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 12) {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    dismiss()
                }
                .buttonStyle(.borderedProminent)

                Button("Save As…") {
                    savePanelExport()
                }
                .buttonStyle(.bordered)

                Button("Dismiss") { dismiss() }
                    .buttonStyle(.bordered)
            }
        }
        .padding(32)
        .frame(minWidth: 320)
    }

    private func savePanelExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "ExportedVideo.mp4"
        panel.allowedContentTypes = [.mpeg4Movie]
        if panel.runModal() == .OK, let dest = panel.url {
            try? FileManager.default.copyItem(at: url, to: dest)
        }
        dismiss()
    }
}
#endif
