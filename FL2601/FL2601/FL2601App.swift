import SwiftUI

@main
struct FL2601App: App {
    var body: some Scene {
        // A single window rather than a WindowGroup: this is a one-off utility,
        // and multiple windows would each hold their own password in memory.
        Window("FL2601 Cipher Tool", id: "main") {
            ContentView()
        }
        // Tall enough that the strength meter, the always-present output panel
        // and the footer all fit without scrolling on first launch.
        .defaultSize(width: 900, height: 1020)
        .windowResizability(.contentMinSize)
        // The app draws its own header, so the system title bar is redundant
        // chrome. Hiding it hands the whole surface to the tool; the window
        // still drags by its top edge, and ContentView insets its content so
        // the heading clears the traffic lights.
        .windowStyle(.hiddenTitleBar)
        .commands {
            // Nothing here is document-backed, so drop the menus that would
            // only ever be greyed out.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
        }
    }
}
