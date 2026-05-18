import SwiftUI

/// Existing-branch picker for the duplicate sheet. A flat `Menu` is unusable
/// on a repo with dozens of branches, so this opens a popover with a live
/// text filter and a scrollable list. Branches already checked out in
/// another worktree are shown disabled with an "(in use)" suffix —
/// `git worktree add` refuses them. Internal (not `fileprivate`) so the
/// filter logic can be unit-tested without standing up the view.
struct BranchPickerField: View {
    let branches: [String]
    let inUse: Set<String>
    /// Bound to the draft's branch name; the binding's setter re-derives the
    /// dependent name/path fields, so picking a branch flows through exactly
    /// like typing one.
    @Binding var selection: String

    @State private var isExpanded = false
    @State private var filter = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        LabeledContent(String(localized: "duplicate.field.existing_branch")) {
            Button {
                isExpanded = true
            } label: {
                HStack {
                    Text(buttonLabel)
                        .foregroundStyle(hasSelection ? .primary : .secondary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.bordered)
            // Nothing to pick until the async branch list lands.
            .disabled(branches.isEmpty)
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                popover
            }
        }
    }

    private var hasSelection: Bool {
        !selection.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var buttonLabel: String {
        let trimmed = selection.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return branches.isEmpty
            ? String(localized: "duplicate.field.existing_branch.loading")
            : String(localized: "duplicate.field.existing_branch.placeholder")
    }

    private var filtered: [String] {
        Self.matching(branches, filter: filter)
    }

    @ViewBuilder
    private var popover: some View {
        VStack(spacing: 0) {
            TextField(
                String(localized: "duplicate.field.existing_branch.search"),
                text: $filter
            )
            .textFieldStyle(.roundedBorder)
            .focused($searchFocused)
            .onSubmit(pickFirstMatch)
            .padding(8)

            Divider()

            if filtered.isEmpty {
                Text(String(localized: "duplicate.field.existing_branch.no_matches"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(filtered, id: \.self) { branch in
                            branchRow(branch)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 280, height: 320)
        .onAppear { searchFocused = true }
    }

    @ViewBuilder
    private func branchRow(_ branch: String) -> some View {
        let busy = inUse.contains(branch)
        Button {
            pick(branch)
        } label: {
            HStack {
                if busy {
                    Text(String(format: String(localized: "duplicate.field.existing_branch.in_use"), branch))
                } else {
                    Text(branch)
                }
                Spacer()
                if branch == selection {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    private func pick(_ branch: String) {
        selection = branch
        filter = ""
        isExpanded = false
    }

    /// Enter in the search field commits the first selectable match — the
    /// fast path for "I know the branch, just let me type it".
    private func pickFirstMatch() {
        guard let match = filtered.first(where: { !inUse.contains($0) }) else { return }
        pick(match)
    }

    /// Case-insensitive substring filter. Pure, so the filtering behavior is
    /// unit-testable without instantiating the view.
    static func matching(_ branches: [String], filter: String) -> [String] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return branches }
        return branches.filter { $0.range(of: query, options: .caseInsensitive) != nil }
    }
}

#Preview {
    Form {
        BranchPickerField(
            branches: ["main", "develop", "feature/login", "feature/signup", "hotfix/crash"],
            inUse: ["main"],
            selection: .constant("feature/login")
        )
    }
    .formStyle(.grouped)
    .frame(width: 360)
}
