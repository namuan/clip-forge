import SwiftUI

@main
struct ClipForgeApp: App {
    @StateObject private var vm = ClipForgeViewModel()

    init() {
        CFLogInfo("ClipForge application starting")
        Logger.shared.cleanupOldLogs(keepDays: 7)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(vm: vm)
                .onAppear {
                    CFLogInfo("Main ContentView appeared")
                }
        }
        .commands {
            CommandMenu("Playback") {
                Button("Jump to Start") {
                    vm.seekToStart()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(vm.player == nil)

                Button(vm.jumpBackTitle) {
                    vm.jumpBack()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.option, .shift])
                .disabled(vm.player == nil)

                Button("Step Back 1 Frame") {
                    vm.stepBack()
                }
                .keyboardShortcut(.leftArrow, modifiers: [.option])
                .disabled(vm.player == nil)

                Divider()

                Button(vm.playPauseTitle) {
                    vm.togglePlayPause()
                }
                .keyboardShortcut(" ", modifiers: [])
                .disabled(vm.player == nil)

                Divider()

                Button("Step Forward 1 Frame") {
                    vm.stepForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.option])
                .disabled(vm.player == nil)

                Button(vm.jumpForwardTitle) {
                    vm.jumpForward()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.option, .shift])
                .disabled(vm.player == nil)

                Button("Jump to End") {
                    vm.seekToEnd()
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(vm.player == nil)
            }
        }
        #if os(macOS)
        .defaultSize(width: 660, height: 440)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        #endif
    }
}
