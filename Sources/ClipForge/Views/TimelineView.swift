import SwiftUI

// MARK: - Reusable transport button

struct TransportButton: View {
    let title: String
    let shortcutDisplay: String?
    let shortcutHint: String?
    let systemImage: String
    let size: CGFloat
    let action: () -> Void

    private var helpText: String {
        guard let shortcutHint else { return title }
        return "\(title) (\(shortcutHint))"
    }

    var body: some View {
        VStack(spacing: 2) {
            Button(action: action) {
                Image(systemName: systemImage)
                    .font(.system(size: size, weight: .semibold))
                    .frame(width: size + 12, height: size + 12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if let shortcutDisplay {
                Text(shortcutDisplay)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .help(helpText)
        .accessibilityLabel(Text(title))
    }
}
