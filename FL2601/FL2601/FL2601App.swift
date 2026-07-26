import SwiftUI

@main
struct FL2601App: App {
    var body: some Scene {
        // A single window rather than a WindowGroup: this is a one-off utility,
        // and multiple windows would each hold their own password in memory.
        Window("FL2601 Cipher Tool", id: "main") {
            ContentView()
        }
        .defaultSize(width: 900, height: 940)
        .windowResizability(.contentMinSize)
        .commands {
            // Nothing here is document-backed, so drop the menus that would
            // only ever be greyed out.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .printItem) {}
        }
    }
}
