import AppKit
import SwiftUI

struct DetailPaneView: View {
    @Bindable var manager: SessionManager
    let dictation: DictationController
    @Binding var editorTarget: ProjectEditorTarget?
    @Binding var duplicateTarget: Project?

    var body: some View {
        ZStack {
            ForEach(manager.projects) { project in
                if let session = manager.session(for: project.id) {
                    sessionPane(
                        session: session,
                        isVisible: manager.selectedProjectID == project.id
                    )
                }
            }

            if manager.selectedProjectID == nil || manager.projects.isEmpty {
                emptyState
            }
        }
        .toolbar {
            if let session = manager.selectedSession() {
                toolbarButtons(for: session)

                ToolbarSpacer(.fixed)
            }

            ToolbarItem {
                attentionMenu
            }
        }
    }

    private var attentionMenu: some View {
        let sessions = manager.attentionSessions
        return Menu {
            if sessions.isEmpty {
                Text(String(localized: "detail.toolbar.attention.empty"))
            } else {
                ForEach(sessions, id: \.id) { session in
                    Button(String(
                        format: String(localized: "detail.toolbar.attention.item"),
                        session.project.name,
                        session.state.displayLabel
                    )) {
                        manager.focus(projectID: session.id)
                    }
                }
            }
        } label: {
            Label {
                if !sessions.isEmpty {
                    Text(sessions.count, format: .number)
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: sessions.isEmpty ? "bell" : "bell.fill")
            }
            .labelStyle(.titleAndIcon)
        }
        .help(String(localized: "detail.toolbar.attention"))
        .accessibilityLabel(String(localized: "detail.toolbar.attention"))
    }

    @ViewBuilder
    private func sessionPane(session: Session, isVisible: Bool) -> some View {
        TerminalPaneView(terminalView: session.terminalView, isVisible: isVisible)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.leading, 4)
            .overlay(alignment: .bottom) {
                if isVisible, session.state.isRunning, session.hasOutputBelowViewport,
                   dictation.targetID != session.id {
                    newOutputPill(session: session)
                }
            }
            .animation(.easeOut(duration: 0.15), value: session.hasOutputBelowViewport)
            .overlay {
                if isVisible, !session.state.isRunning {
                    notRunningOverlay(session: session)
                }
            }
            .overlay(alignment: .bottom) {
                if isVisible, dictation.targetID == session.id {
                    DictationOverlay(controller: dictation) {
                        manager.focusSelectedTerminal()
                    }
                }
            }
            .animation(.easeOut(duration: 0.15), value: dictation.targetID == session.id)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
    }

    private func notRunningOverlay(session: Session) -> some View {
        VStack(spacing: 12) {
            Text(String(localized: session.lastError == nil ? "detail.not_running.title" : "detail.not_running.failed_title"))
                .interfaceFont(.headline)
            if let reason = session.lastError {
                ScrollView {
                    Text(reason)
                        .interfaceFont(.callout, design: .monospaced)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: 520, maxHeight: 220)
                .padding(.horizontal, 24)
            }
            HStack(spacing: 12) {
                Button(String(localized: "detail.not_running.start")) {
                    session.start()
                }
                if session.canContinue {
                    Button(String(localized: "detail.not_running.continue")) {
                        session.startContinuing()
                    }
                }
            }
            .controlSize(.large)
            .pointerStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
        // Without this SwiftTerm's cursor rect wins and the overlay shows an I-beam.
        .pointerStyle(.default)
    }

    private func newOutputPill(session: Session) -> some View {
        Button {
            session.scrollToBottom()
            // The click leaves focus on the pill; hand it back to the terminal.
            manager.focusSelectedTerminal()
        } label: {
            Label(String(localized: "detail.new_output"), systemImage: "arrow.down")
                .interfaceFont(.callout)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.separator))
        .help(String(localized: "detail.new_output.help"))
        .padding(.bottom, 16)
        .pointerStyle(.default)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.dashed")
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)
            Text(String(localized: "detail.empty.title"))
                .interfaceFont(.title3)
                .foregroundStyle(.secondary)
            if manager.projects.isEmpty {
                Button(String(localized: "detail.empty.add_project")) {
                    editorTarget = .add(seedFolder: nil)
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private func toolbarButtons(for session: Session) -> some ToolbarContent {
        ToolbarItemGroup {
            lifecycleButton(for: session)

            if session.state.isRunning {
                Button {
                    session.restart()
                } label: {
                    Label(String(localized: "detail.toolbar.restart"), systemImage: "arrow.clockwise")
                }
                .help(String(localized: "detail.toolbar.restart"))
            }

            if !session.state.isRunning, session.canContinue {
                Button {
                    session.startContinuing()
                } label: {
                    Label(String(localized: "detail.toolbar.continue"), systemImage: "clock.arrow.circlepath")
                }
                .help(String(localized: "detail.toolbar.continue.help"))
            }
        }

        ToolbarSpacer(.fixed)

        ToolbarItemGroup {
            dictationButton(for: session)

            Button {
                NSWorkspace.shared.open(session.project.path)
            } label: {
                Label(String(localized: "detail.toolbar.open_in_finder"), systemImage: "folder")
            }
            .help(KeyboardShortcut.openInFinder.tooltip(String(localized: "detail.toolbar.open_in_finder")))

            Button {
                OpenInTerminal.open(session.project.path)
            } label: {
                Label(String(localized: "detail.toolbar.open_in_terminal"), systemImage: "terminal")
            }
            .help(KeyboardShortcut.openInTerminal.tooltip(String(localized: "detail.toolbar.open_in_terminal")))

            if session.project.parentProjectID == nil {
                Button {
                    duplicateTarget = session.project
                } label: {
                    Label(
                        String(localized: "detail.toolbar.duplicate"),
                        systemImage: "plus.square.on.square"
                    )
                }
                .help(KeyboardShortcut.duplicateProject.tooltip(String(localized: "detail.toolbar.duplicate")))
            }

            Button {
                editorTarget = .edit(session.project)
            } label: {
                Label(String(localized: "detail.toolbar.edit"), systemImage: "pencil")
            }
            .help(KeyboardShortcut.editProject.tooltip(String(localized: "detail.toolbar.edit")))
        }
    }

    private func dictationButton(for session: Session) -> some View {
        let isActive = dictation.isActive(for: session.id)
        let title = String(localized: isActive ? "detail.toolbar.dictate.stop" : "detail.toolbar.dictate")
        return Button {
            dictation.toggle(for: session)
        } label: {
            Label(title, systemImage: isActive ? "mic.fill" : "mic")
        }
        .tint(isActive ? .red : nil)
        .disabled(!session.state.isRunning || !dictation.canToggle(for: session.id))
        .help(dictation.isHoldingText ? String(localized: "detail.toolbar.dictate.held") : KeyboardShortcut.dictate.tooltip(title))
    }

    @ViewBuilder
    private func lifecycleButton(for session: Session) -> some View {
        if !session.state.isRunning {
            Button {
                session.start()
            } label: {
                Label(String(localized: "detail.toolbar.start"), systemImage: "play.fill")
            }
            .help(String(localized: "detail.toolbar.start"))
        } else if session.softStopRequested {
            Button {
                session.forceStop()
            } label: {
                Label(String(localized: "detail.toolbar.force_stop"), systemImage: "xmark.octagon.fill")
            }
            .tint(.red)
            .help(String(localized: "detail.toolbar.force_stop"))
        } else {
            Button {
                session.stop()
            } label: {
                Label(String(localized: "detail.toolbar.stop"), systemImage: "stop.fill")
            }
            .help(String(localized: "detail.toolbar.stop"))
        }
    }
}
