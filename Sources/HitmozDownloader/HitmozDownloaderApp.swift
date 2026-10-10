import SwiftUI
import AppKit

@main
struct HitmozDownloaderApp: App {
    init() {
        // Делает приложение обычным (не background) при запуске из терминала/SwiftPM
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Hitmoz Downloader") {
            ContentView()
                .frame(minWidth: 640, minHeight: 480)
        }
        .windowResizability(.contentSize)
    }
}