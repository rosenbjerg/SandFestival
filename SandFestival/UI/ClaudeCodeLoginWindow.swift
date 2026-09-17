import AppKit
import Observation
import SwiftTerm
import SwiftUI

@Observable
@MainActor
final class ClaudeCodeLoginController {
    enum Phase: Equatable {
        case idle
        case running
        case finished(exitCode: Int32?)
    }

    private(set) var phase: Phase = .idle
    private(set) var startupError: String?

    @ObservationIgnored let terminalView: SessionTerminalView
    @ObservationIgnored private let bridge = LoginProcessBridge()
    @ObservationIgnored private var scratchDirectory: URL?

    var succeeded: Bool { phase == .finished(exitCode: 0) }

    init(font: NSFont? = nil, scrollback: Int? = nil) {
        let view = SessionTerminalView(frame: .zero)
        terminalView = view
        view.processDelegate = bridge
        if let font { view.font = font }
        if let scrollback { view.getTerminal().changeScrollback(scrollback) }
        bridge.onProcessTerminated = { [weak self] exitCode in
            Task { @MainActor in
                self?.phase = .finished(exitCode: exitCode)
            }
        }
    }

    func start() {
        guard phase == .idle else { return }
        guard let executable = CommandResolver.resolve(ClaudeCodeLogin.command) else {
            startupError = String(localized: "login.error.command_not_found")
            phase = .finished(exitCode: nil)
            return
        }
        let scratch: URL
        do {
            scratch = try ClaudeCodeLogin.makeScratchDirectory()
        } catch {
            startupError = error.localizedDescription
            phase = .finished(exitCode: nil)
            return
        }
        scratchDirectory = scratch
        phase = .running
        terminalView.startProcess(
            executable: executable,
            args: ClaudeCodeLogin.args,
            environment: Session.inheritedEnvironment(),
            execName: nil,
            currentDirectory: scratch.path
        )
    }

    func cancel() {
        if case .running = phase {
            let pid = terminalView.process.shellPid
            if pid != 0 { kill(pid, SIGINT) }
        }
        discardScratchDirectory()
    }

    private func discardScratchDirectory() {
        guard let scratch = scratchDirectory else { return }
        scratchDirectory = nil
        try? FileManager.default.removeItem(at: scratch)
    }
}

private final class LoginProcessBridge: NSObject, LocalProcessTerminalViewDelegate {
    var onProcessTerminated: ((Int32?) -> Void)?

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func processTerminated(source: TerminalView, exitCode: Int32?) {
        onProcessTerminated?(exitCode)
    }
}

struct ClaudeCodeLoginWindow: View {
    static let windowID = "claude-code-login"

    @Bindable var manager: SessionManager
    @Environment(\.dismiss) private var dismiss

    @State private var controller: ClaudeCodeLoginController?
    @State private var didRestartSessions = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "login.intro"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            Divider()

            if let controller {
                TerminalPaneView(terminalView: controller.terminalView, isVisible: true)
            } else {
                Color.clear
            }

            Divider()

            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .frame(minWidth: 640, minHeight: 420)
        .task {
            guard controller == nil else { return }
            let controller = ClaudeCodeLoginController(
                font: manager.currentTerminalFont(),
                scrollback: manager.terminalScrollback
            )
            self.controller = controller
            controller.start()
        }
        .onDisappear {
            controller?.cancel()
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            statusLabel

            Spacer()

            if controller?.succeeded == true && !didRestartSessions {
                Button(String(localized: "login.restart_sessions")) {
                    manager.restartAllRunningContinuing()
                    didRestartSessions = true
                }
                .help(String(localized: "login.restart_sessions.help"))
            }

            Button(String(localized: "login.close")) {
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        if let controller {
            if let error = controller.startupError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if didRestartSessions {
                Label(String(localized: "login.restart_note"), systemImage: "arrow.clockwise")
                    .foregroundStyle(.secondary)
            } else {
                switch controller.phase {
                case .idle:
                    EmptyView()
                case .running:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "login.status.running"))
                            .foregroundStyle(.secondary)
                    }
                case .finished(let exitCode):
                    if exitCode == 0 {
                        Label(String(localized: "login.status.success"), systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                    } else {
                        Label(String(localized: "login.status.failure"), systemImage: "xmark.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }
}
