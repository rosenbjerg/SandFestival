import AppKit
import SwiftTerm
import SwiftUI

struct TerminalPaneView: NSViewRepresentable {
    let executable: String
    let args: [String]
    let workingDirectory: URL
    let environmentOverrides: [String: String]

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator
        view.startProcess(
            executable: executable,
            args: args,
            environment: composedEnvironment(),
            execName: nil,
            currentDirectory: workingDirectory.path
        )
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    static func dismantleNSView(_ nsView: LocalProcessTerminalView, coordinator: Coordinator) {
        nsView.terminate()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    private func composedEnvironment() -> [String] {
        var entries = Terminal.getEnvironmentVariables()
        for (key, value) in environmentOverrides {
            entries.append("\(key)=\(value)")
        }
        return entries
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func processTerminated(source: TerminalView, exitCode: Int32?) {}
    }
}
