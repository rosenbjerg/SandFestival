import AppKit
import SwiftUI

struct MenuBarContentView: View {
    @Bindable var manager: SessionManager

    var body: some View {
        let attentionSessions = self.attentionSessions

        if attentionSessions.isEmpty {
            Text(String(localized: "menubar.no_attention"))
        } else {
            Section(String(localized: "menubar.section.attention")) {
                ForEach(attentionSessions) { session in
                    Button {
                        focus(on: session.project.id)
                    } label: {
                        Text("\(session.project.name) — \(stateLabel(for: session.state))")
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

    private var attentionSessions: [Session] {
        manager.projects.compactMap { manager.session(for: $0.id) }
            .filter { $0.state.needsAttention }
    }

    private func focus(on projectID: Project.ID) {
        manager.selectedProjectID = projectID
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    private func stateLabel(for state: SessionState) -> String {
        switch state {
        case .starting: return String(localized: "status.starting")
        case .idle: return String(localized: "status.idle")
        case .working: return String(localized: "status.working")
        case .waitingForPermission: return String(localized: "status.waiting_permission")
        case .waitingForIdle: return String(localized: "status.waiting_idle")
        case .blockedByAutoMode: return String(localized: "status.blocked_auto_mode")
        case .errored: return String(localized: "status.errored")
        case .stopped: return String(localized: "status.stopped")
        }
    }
}
