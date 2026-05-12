import AppKit
import SwiftUI

struct DetailPaneView: View {
    @Bindable var manager: SessionManager
    @Binding var editorTarget: ProjectEditorTarget?

    var body: some View {
        ZStack {
            // Hosting all sessions in a ZStack keeps every terminal view in the
            // view hierarchy regardless of selection, preserving scrollback.
            ForEach(manager.projects) { project in
                if let session = manager.session(for: project.id) {
                    sessionPane(session: session)
                        .opacity(manager.selectedProjectID == project.id ? 1 : 0)
                        .allowsHitTesting(manager.selectedProjectID == project.id)
                }
            }

            if manager.selectedProjectID == nil || manager.projects.isEmpty {
                emptyState
            }
        }
        .toolbar {
            if let session = manager.selectedSession() {
                toolbarButtons(for: session)
            }
        }
    }

    @ViewBuilder
    private func sessionPane(session: Session) -> some View {
        ZStack {
            TerminalPaneView(terminalView: session.terminalView)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.leading, 4)

            if !session.state.isRunning {
                notRunningOverlay(session: session)
            }
        }
    }

    private func notRunningOverlay(session: Session) -> some View {
        VStack(spacing: 12) {
            Text(String(localized: session.lastError == nil ? "detail.not_running.title" : "detail.not_running.failed_title"))
                .font(.headline)
            if let reason = session.lastError {
                ScrollView {
                    Text(reason)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 520, maxHeight: 220)
                .padding(.horizontal, 24)
            }
            Button(String(localized: "detail.not_running.start")) {
                session.start()
            }
            .controlSize(.large)
            .pointerStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        // Without an explicit pointer style, SwiftTerm's cursor rect from the
        // underlying NSView wins and the mouse stays an I-beam over the
        // overlay. .default forces an arrow on this layer's content rect.
        .pointerStyle(.default)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(String(localized: "detail.empty.title"))
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private func toolbarButtons(for session: Session) -> some ToolbarContent {
        ToolbarItemGroup {
            Button {
                session.restart()
            } label: {
                Label(String(localized: "detail.toolbar.restart"), systemImage: "arrow.clockwise")
            }
            .help(String(localized: "detail.toolbar.restart"))

            Button {
                if session.state.isRunning {
                    if session.softStopRequested {
                        session.forceStop()
                    } else {
                        session.stop()
                    }
                } else {
                    session.start()
                }
            } label: {
                if session.state.isRunning {
                    if session.softStopRequested {
                        Label(String(localized: "detail.toolbar.force_stop"), systemImage: "xmark.octagon.fill")
                    } else {
                        Label(String(localized: "detail.toolbar.stop"), systemImage: "stop.fill")
                    }
                } else {
                    Label(String(localized: "detail.toolbar.start"), systemImage: "play.fill")
                }
            }

            Button {
                NSWorkspace.shared.open(session.project.path)
            } label: {
                Label(String(localized: "detail.toolbar.open_in_finder"), systemImage: "folder")
            }
            .help(String(localized: "detail.toolbar.open_in_finder"))

            Button {
                editorTarget = .edit(session.project)
            } label: {
                Label(String(localized: "detail.toolbar.edit"), systemImage: "pencil")
            }
            .help(String(localized: "detail.toolbar.edit"))
        }
    }
}
