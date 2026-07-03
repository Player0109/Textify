import AppKit
import SwiftUI

struct MenuBarRoot: View {
    var body: some View {
        Button("Quit Textify") {
            NSApplication.shared.terminate(nil)
        }
    }
}
