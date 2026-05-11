import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var manager: SessionManager

    var body: some View {
        let attentionSessions = manager.attentionSessions

        if attentionSessions.isEmpty {
            Text(String(localized: "menubar.no_attention"))
        } else {
            Section(String(localized: "menubar.section.attention")) {
                ForEach(attentionSessions) { session in
                    Button {
                        manager.focus(projectID: session.project.id)
                    } label: {
                        Text("\(session.project.name) — \(session.state.displayLabel)")
                    }
                }
            }
            Divider()
        }

        Button(String(localized: "menubar.action.show")) {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        Divider()

        Button(String(localized: "menubar.action.quit")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
