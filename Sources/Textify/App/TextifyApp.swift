import SwiftUI

@main
struct TextifyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Textify", systemImage: "text.bubble") {
            MenuBarRoot()
        }
    }
}
