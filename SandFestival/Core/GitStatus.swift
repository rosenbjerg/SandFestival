import Foundation

struct GitStatus: Equatable {
    var branch: String?
    var ahead: Int = 0
    var behind: Int = 0
    var changedFiles: Int = 0
    var comparisonRef: String?

    var isClean: Bool { changedFiles == 0 }
}

enum GitStatusResult: Equatable {
    case unavailable
    case status(GitStatus)
}

extension GitStatus {
    static func parse(porcelainV2 output: String) -> GitStatus {
        var status = GitStatus()
        for line in output.split(whereSeparator: \.isNewline) {
            if let value = line.dropPrefix("# branch.head ") {
                status.branch = value == "(detached)" ? nil : String(value)
            } else if let value = line.dropPrefix("# branch.upstream ") {
                status.comparisonRef = String(value)
            } else if let value = line.dropPrefix("# branch.ab ") {
                for field in value.split(separator: " ") {
                    if field.hasPrefix("+") {
                        status.ahead = Int(field.dropFirst()) ?? 0
                    } else if field.hasPrefix("-") {
                        status.behind = Int(field.dropFirst()) ?? 0
                    }
                }
            } else if line.isChangedEntry {
                status.changedFiles += 1
            }
        }
        return status
    }
}

private extension Substring {
    func dropPrefix(_ prefix: String) -> Substring? {
        hasPrefix(prefix) ? dropFirst(prefix.count) : nil
    }

    var isChangedEntry: Bool {
        guard let kind = first, "12u?".contains(kind) else { return false }
        return dropFirst().hasPrefix(" ")
    }
}
