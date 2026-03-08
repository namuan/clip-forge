import SwiftUI

@main
struct ClipForgeApp: App {
    init() {
        CFLogInfo("ClipForge application starting")
        Logger.shared.cleanupOldLogs(keepDays: 7)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    CFLogInfo("Main ContentView appeared")
                }
        }
        #if os(macOS)
        .defaultSize(width: 660, height: 440)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        #endif
    }
}
