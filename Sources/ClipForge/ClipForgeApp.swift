import SwiftUI

@main
struct ClipForgeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 800, height: 900)
        #endif
    }
}
