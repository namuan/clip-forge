import SwiftUI

struct StartScreenView: View {
    @ObservedObject var vm: ClipForgeViewModel
    var onOpenVideo: () -> Void
    var onOpenProject: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Divider().background(Color(white: 0.22))
            rightPanel
        }
        .padding(.top, 28)      // clear the transparent title-bar / traffic-light zone
        .background(Color(white: 0.1))
    }

    // MARK: - Left panel (branding + actions)

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            // Icon + name
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "film.stack")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.85))
                Text("ClipForge")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(.white)
                Text("Video Editor")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.5))
            }

            Spacer().frame(height: 36)

            // Action buttons
            VStack(alignment: .leading, spacing: 6) {
                StartActionButton(icon: "plus.rectangle.on.folder",
                                  label: "New Video",
                                  action: onOpenVideo)
                StartActionButton(icon: "folder",
                                  label: "Open Project",
                                  action: onOpenProject)
            }

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(width: 220)
        .background(Color(white: 0.1))
    }

    // MARK: - Right panel (recents)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Recent Projects")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.45))
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Divider().background(Color(white: 0.18))

            if vm.recentProjects.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color(white: 0.3))
                    Text("No recent projects")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.35))
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.recentProjects) { recent in
                            RecentProjectRow(recent: recent) {
                                openRecent(recent)
                            } onRemove: {
                                vm.removeFromRecents(id: recent.id)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.13))
    }

    private func openRecent(_ recent: RecentProject) {
        do { try vm.loadProject(from: recent.projectFileURL) }
        catch { vm.showError(error.localizedDescription) }
    }
}

// MARK: - Action button

private struct StartActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isHovered ? .white : Color(white: 0.7))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isHovered ? .white : Color(white: 0.8))
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isHovered ? Color(white: 0.22) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recent project row

private struct RecentProjectRow: View {
    let recent: RecentProject
    let onOpen: () -> Void
    let onRemove: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.accentColor.opacity(0.75))
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(white: 0.88))
                        .lineLimit(1)
                    Text(shortPath(recent.projectFileURL))
                        .font(.system(size: 10))
                        .foregroundStyle(Color(white: 0.38))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()

                Text(relativeDate(recent.lastOpened))
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.32))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                isHovered ? Color(white: 0.19) : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Remove from Recents", role: .destructive) { onRemove() }
        }
    }

    private func shortPath(_ url: URL) -> String {
        url.deletingLastPathComponent().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        let days = cal.dateComponents([.day], from: date, to: Date()).day ?? 0
        if days < 7 { return "\(days)d ago" }
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d"
        return fmt.string(from: date)
    }
}
