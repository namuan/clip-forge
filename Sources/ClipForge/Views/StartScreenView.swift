import SwiftUI

struct StartScreenView: View {
    @ObservedObject var vm: ClipForgeViewModel
    var onOpenVideo: () -> Void
    var onOpenProject: () -> Void
    @State private var pendingDeleteRecent: RecentProject?

    var body: some View {
        HStack(spacing: 0) {
            leftPanel
            Divider().background(Color(white: 0.86))
            rightPanel
        }
        .background(Color(white: 0.97))
        .confirmationDialog(
            deleteConfirmationTitle,
            isPresented: deleteDialogPresented,
            titleVisibility: .visible
        ) {
            Button("Delete Project", role: .destructive) {
                confirmDeleteProject()
            }
            Button("Cancel", role: .cancel) {
                pendingDeleteRecent = nil
            }
        } message: {
            Text("This permanently deletes the project from disk, including its copied source video.")
        }
    }

    // MARK: - Left panel (branding + actions)

    private var leftPanel: some View {
        VStack(spacing: 0) {
            Spacer()

            // Icon + name
            VStack(spacing: 6) {
                Image(systemName: "film.stack")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(Color.accentColor.opacity(0.9))
                Text("ClipForge")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Color(white: 0.14))
                Text("Video Editor")
                    .font(.system(size: 12))
                    .foregroundStyle(Color(white: 0.45))
            }

            Spacer().frame(height: 36)

            // Action buttons
            VStack(spacing: 6) {
                StartActionButton(icon: "plus.rectangle.on.folder",
                                  label: "New Video",
                                  action: onOpenVideo)
                StartActionButton(icon: "folder",
                                  label: "Open Project",
                                  action: onOpenProject)
            }
            .frame(width: 150)

            Spacer()
        }
        .padding(.horizontal, 28)
        .frame(width: 220)
        .background(Color(white: 0.95))
    }

    // MARK: - Right panel (recents)

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            Text("Recent Projects")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(white: 0.48))
                .textCase(.uppercase)
                .tracking(0.6)
                .padding(.horizontal, 16)
                .padding(.top, 20)
                .padding(.bottom, 10)

            Divider().background(Color(white: 0.86))

            if vm.recentProjects.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(Color(white: 0.55))
                    Text("No recent projects")
                        .font(.system(size: 12))
                        .foregroundStyle(Color(white: 0.5))
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
                            } onDeleteProject: {
                                pendingDeleteRecent = recent
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(white: 0.99))
    }

    private func openRecent(_ recent: RecentProject) {
        do { try vm.loadProject(from: recent.projectFileURL) }
        catch { vm.showError(error.localizedDescription) }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteRecent != nil },
            set: { isPresented in
                if !isPresented { pendingDeleteRecent = nil }
            })
    }

    private var deleteConfirmationTitle: String {
        guard let pendingDeleteRecent else { return "Delete Project?" }
        return "Delete \"\(pendingDeleteRecent.name)\"?"
    }

    private func confirmDeleteProject() {
        guard let recent = pendingDeleteRecent else { return }
        pendingDeleteRecent = nil
        do {
            try vm.deleteProject(recent)
        } catch {
            vm.showError(error.localizedDescription)
        }
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
                    .foregroundStyle(isHovered ? Color(white: 0.14) : Color(white: 0.4))
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isHovered ? Color(white: 0.14) : Color(white: 0.2))
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                isHovered ? Color(white: 0.9) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Recent project row

private struct RecentProjectRow: View {
    let recent: RecentProject
    let onOpen: () -> Void
    let onRemove: () -> Void
    let onDeleteProject: () -> Void

    @State private var isHovered = false

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: onOpen) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recent.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(white: 0.18))
                            .lineLimit(1)
                        Text(shortPath(recent.projectFileURL))
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.5))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    Text(relativeDate(recent.lastOpened))
                        .font(.system(size: 11))
                        .foregroundStyle(Color(white: 0.52))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.trailing, isHovered ? 34 : 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(white: 0.93).opacity(isHovered ? 1 : 0.001)))
            }
            .buttonStyle(.plain)
            .focusable(false)

            if isHovered {
                Button(role: .destructive, action: onDeleteProject) {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.red.opacity(0.9))
                        .frame(width: 22, height: 22)
                        .background(
                            Circle().fill(Color.white.opacity(0.92)))
                }
                .buttonStyle(.plain)
                .focusable(false)
                .padding(.trailing, 14)
                .transition(.opacity)
                .help("Delete Project")
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .onHover { hovered in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = hovered
            }
        }
        .contextMenu {
            Button("Open") { onOpen() }
            Divider()
            Button("Remove from Recents", role: .destructive) { onRemove() }
            Button("Delete Project...", role: .destructive) { onDeleteProject() }
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
