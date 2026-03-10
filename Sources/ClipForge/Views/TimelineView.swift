import SwiftUI

// MARK: - Reusable transport button

struct TransportButton: View {
    let title: String
    let shortcutHint: String?
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    private var helpText: String {
        guard let shortcutHint else { return title }
        return "\(title) (\(shortcutHint))"
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .frame(width: size + 12, height: size + 12)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(helpText)
        .accessibilityLabel(Text(title))
    }
}
