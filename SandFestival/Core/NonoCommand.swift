import Foundation

enum NonoCommand {
    static func matches(_ command: String) -> Bool {
        (command.trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent == "nono"
    }
}
