import SwiftUI

struct UpdateClaudeCodeSheet: View {
    @Bindable var manager: SessionManager
    let onClose: () -> Void

    private enum Phase {
        case prompt
        case running
        case done
    }

    @State private var phase: Phase = .prompt
    @State private var restartAfterUpdate = true
    @State private var output = ""
    @State private var succeeded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(.title2)
                .bold()

            switch phase {
            case .prompt: promptBody
            case .running: runningBody
            case .done: doneBody
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: String {
        switch phase {
        case .prompt, .running:
            return String(localized: "menu.update_claude_code")
        case .done:
            return succeeded
                ? String(localized: "update.done.title.success")
                : String(localized: "update.done.title.failure")
        }
    }

    // MARK: - Phases

    private var promptBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "update.prompt.body"))
                .fixedSize(horizontal: false, vertical: true)

            Toggle(String(localized: "update.prompt.restart_toggle"), isOn: $restartAfterUpdate)

            HStack {
                Spacer()
                Button(String(localized: "update.prompt.cancel"), role: .cancel) {
                    onClose()
                }
                Button(String(localized: "update.prompt.confirm")) {
                    runUpdate()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var runningBody: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(String(localized: "update.running.status"))
                .foregroundStyle(.secondary)
        }
    }

    private var doneBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !output.isEmpty {
                outputBox(output)
            }

            if succeeded && restartAfterUpdate {
                Label(String(localized: "update.done.restart_note"), systemImage: "arrow.clockwise")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()
                Button(String(localized: "update.done.close")) {
                    onClose()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func outputBox(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: 200)
        .background(.quaternary.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))
    }

    // MARK: - Actions

    private func runUpdate() {
        phase = .running
        Task {
            // Detached: runUpdate blocks on waitUntilExit.
            let result = await Task.detached { ClaudeCodeUpdater.runUpdate() }.value
            output = result.output
            succeeded = result.succeeded
            // Only after success, or the relaunch picks up the old binary.
            if result.succeeded && restartAfterUpdate {
                manager.restartAllRunningContinuing()
            }
            phase = .done
        }
    }
}
