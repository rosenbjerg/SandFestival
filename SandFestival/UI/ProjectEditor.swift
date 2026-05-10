import AppKit
import SwiftUI

enum ProjectEditorTarget: Identifiable {
    case add
    case edit(Project)

    var id: String {
        switch self {
        case .add: return "add"
        case .edit(let project): return project.id.uuidString
        }
    }
}

struct ProjectEditorView: View {
    let target: ProjectEditorTarget
    let onSave: (Project) -> Void
    let onCancel: () -> Void

    @State private var draft: ProjectDraft

    init(target: ProjectEditorTarget, onSave: @escaping (Project) -> Void, onCancel: @escaping () -> Void) {
        self.target = target
        self.onSave = onSave
        self.onCancel = onCancel
        switch target {
        case .add:
            _draft = State(initialValue: ProjectDraft())
        case .edit(let project):
            _draft = State(initialValue: ProjectDraft(project: project))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(String(localized: "editor.field.name"), text: $draft.name)

                    HStack {
                        TextField(String(localized: "editor.field.path"), text: $draft.pathString)
                            .truncationMode(.head)
                        Button(String(localized: "editor.field.path.choose")) {
                            choosePath()
                        }
                    }
                }

                Section(String(localized: "editor.section.command")) {
                    TextField(String(localized: "editor.field.command"), text: $draft.command)
                    argsEditor
                }

                Section(String(localized: "editor.section.environment")) {
                    envEditor
                }

                Section {
                    Toggle(String(localized: "editor.field.auto_start"), isOn: $draft.autoStart)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Spacer()
                Button(String(localized: "editor.action.cancel"), role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "editor.action.save")) {
                    onSave(draft.materialize(originalID: target.originalID))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!draft.isValid)
            }
            .padding()
        }
        .frame(minWidth: 540, minHeight: 480)
        .navigationTitle(target.title)
    }

    @ViewBuilder
    private var argsEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            argsBlock(
                title: String(localized: "editor.field.args.wrapper"),
                text: $draft.wrapperArgsText
            )
            argsBlock(
                title: String(localized: "editor.field.args.agent"),
                text: $draft.agentArgsText
            )
            Text(String(localized: "editor.field.args.help"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func argsBlock(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.callout)
            TextEditor(text: text)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 80)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))
        }
    }

    @ViewBuilder
    private var envEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach($draft.envEntries) { $entry in
                HStack {
                    TextField(String(localized: "editor.field.env.key"), text: $entry.key)
                        .frame(maxWidth: 180)
                    TextField(String(localized: "editor.field.env.value"), text: $entry.value)
                    Button {
                        draft.envEntries.removeAll { $0.id == entry.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help(String(localized: "editor.field.env.remove"))
                }
            }
            Button {
                draft.envEntries.append(EnvEntry())
            } label: {
                Label(String(localized: "editor.field.env.add"), systemImage: "plus")
            }
            .buttonStyle(.borderless)
        }
    }

    private func choosePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            draft.pathString = url.path
            if draft.name.isEmpty {
                draft.name = url.lastPathComponent
            }
        }
    }
}

// MARK: - Draft model

private struct ProjectDraft {
    var name: String
    var pathString: String
    var command: String
    var wrapperArgsText: String
    var agentArgsText: String
    var envEntries: [EnvEntry]
    var autoStart: Bool

    init() {
        self.name = ""
        self.pathString = ""
        self.command = Project.defaultCommand
        let split = ArgsSplitter.split(Project.defaultArgs)
        self.wrapperArgsText = split.wrapper.joined(separator: "\n")
        self.agentArgsText = split.agent.joined(separator: "\n")
        self.envEntries = []
        self.autoStart = false
    }

    init(project: Project) {
        self.name = project.name
        self.pathString = project.path.path
        self.command = project.command
        let split = ArgsSplitter.split(project.args)
        self.wrapperArgsText = split.wrapper.joined(separator: "\n")
        self.agentArgsText = split.agent.joined(separator: "\n")
        self.envEntries = project.env
            .sorted(by: { $0.key < $1.key })
            .map { EnvEntry(key: $0.key, value: $0.value) }
        self.autoStart = project.autoStart
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        !pathString.trimmingCharacters(in: .whitespaces).isEmpty &&
        !command.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private static func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func materialize(originalID: UUID?) -> Project {
        let wrapper = ProjectDraft.tokens(wrapperArgsText)
        let agent = ProjectDraft.tokens(agentArgsText)
        let args = ArgsSplitter.join(wrapper: wrapper, agent: agent)
        var env: [String: String] = [:]
        for entry in envEntries where !entry.key.isEmpty {
            env[entry.key] = entry.value
        }
        return Project(
            id: originalID ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            path: URL(fileURLWithPath: pathString),
            command: command.trimmingCharacters(in: .whitespaces),
            args: args,
            env: env,
            autoStart: autoStart
        )
    }
}

private struct EnvEntry: Identifiable {
    let id = UUID()
    var key: String = ""
    var value: String = ""
}

private extension ProjectEditorTarget {
    var originalID: UUID? {
        switch self {
        case .add: return nil
        case .edit(let project): return project.id
        }
    }

    var title: String {
        switch self {
        case .add: return String(localized: "editor.add.title")
        case .edit: return String(localized: "editor.edit.title")
        }
    }
}
