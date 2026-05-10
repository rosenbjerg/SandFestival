import SwiftUI

struct ContentView: View {
    var body: some View {
        TerminalPaneView(
            executable: SpikeConfig.executable,
            args: SpikeConfig.args,
            workingDirectory: SpikeConfig.workingDirectory,
            environmentOverrides: SpikeConfig.environmentOverrides
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private enum SpikeConfig {
    static let executable = "/opt/homebrew/bin/nono"
    static let args = ["claude"]
    static var workingDirectory: URL { FileManager.default.homeDirectoryForCurrentUser }
    static var environmentOverrides: [String: String] {
        let home = NSHomeDirectory()
        return [
            "PATH": "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        ]
    }
}

#Preview {
    ContentView()
}
