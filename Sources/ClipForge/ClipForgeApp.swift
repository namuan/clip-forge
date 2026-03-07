import SwiftUI

@main
struct ClipForgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 660, height: 440)
        .defaultPosition(.center)
        .windowResizability(.contentSize)
        #endif
    }
}
