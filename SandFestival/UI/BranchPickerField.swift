import SwiftUI

/// Branch picker for the duplicate sheet. A flat `Menu` is unusable on a repo
/// with dozens of branches, so this opens a popover with a live text filter
/// and a scrollable list. It backs both branch fields:
///
/// - the existing-branch picker, where nothing is selected until the user
///   picks a branch and branches checked out in another worktree are shown
///   disabled with an "(in use)" suffix — `git worktree add` refuses them;
/// - the base-branch picker, where `nil` is a valid choice (the "Current
///   HEAD" sentinel) and every branch is selectable — `git worktree add -b`
///   happily branches off a branch that's live in another worktree.
///
/// Internal (not `fileprivate`) so the filter logic can be unit-tested
/// without standing up the view.
struct BranchPickerField: View {
    /// How the picker presents a `nil` selection.
    enum EmptySelection {
        /// `nil` is a real, pickable choice — the base-branch picker's
        /// "Current HEAD". A row with this label sits atop the list and the
        /// button shows it whenever no branch is selected.
        case sentinel(label: String)
        /// `nil` means "nothing picked yet". The button shows `text`, or
        /// `loading` until the async branch list lands.
        case placeholder(text: String, loading: String)
    }

    /// The `LabeledContent` label for the field.
    let label: String
    let branches: [String]
    /// Branches checked out in another worktree, shown disabled. Empty for
    /// pickers where an in-use branch is still a valid choice (a base branch).
    var inUse: Set<String> = []
    let empty: EmptySelection
    /// `nil` means no branch is selected — a valid state for a `.sentinel`
    /// picker, the not-yet-picked state for a `.placeholder` one. The
    /// binding's setter is free to re-derive dependent fields, so picking a
    /// branch flows through exactly like typing one.
    @Binding var selection: String?

    @State private var isExpanded = false
    @State private var filter = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        LabeledContent(label) {
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
            // Nothing to pick until the async branch list lands — unless a
            // sentinel is present, which is always a valid choice on its own.
            .disabled(branches.isEmpty && sentinelLabel == nil)
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                popover
            }
        }
    }

    /// The sentinel's row label, or `nil` for a `.placeholder` picker.
    private var sentinelLabel: String? {
        if case .sentinel(let label) = empty { return label }
        return nil
    }

    private var hasSelection: Bool {
        // A sentinel is itself a real choice, so a `nil` selection still
        // reads as "selected" when one is configured.
        if sentinelLabel != nil { return true }
        return !(selection ?? "").trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var buttonLabel: String {
        let trimmed = (selection ?? "").trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        switch empty {
        case .sentinel(let label):
            return label
        case .placeholder(let text, let loading):
            return branches.isEmpty ? loading : text
        }
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

            // A sentinel is always pickable, so the empty state only stands
            // in when there's genuinely nothing to show.
            if filtered.isEmpty && sentinelLabel == nil {
                Text(String(localized: "duplicate.field.existing_branch.no_matches"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let sentinelLabel {
                            sentinelRow(sentinelLabel)
                        }
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

    /// The "no specific branch" row — always at the top, never filtered out,
    /// so the default choice stays reachable however the user has searched.
    @ViewBuilder
    private func sentinelRow(_ label: String) -> some View {
        Button {
            pick(nil)
        } label: {
            row(label, isChecked: selection == nil)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func branchRow(_ branch: String) -> some View {
        let busy = inUse.contains(branch)
        Button {
            pick(branch)
        } label: {
            if busy {
                row(
                    String(format: String(localized: "duplicate.field.existing_branch.in_use"), branch),
                    isChecked: branch == selection
                )
            } else {
                row(branch, isChecked: branch == selection)
            }
        }
        .buttonStyle(.plain)
        .disabled(busy)
    }

    @ViewBuilder
    private func row(_ text: String, isChecked: Bool) -> some View {
        HStack {
            Text(text)
            Spacer()
            if isChecked {
                Image(systemName: "checkmark")
                    .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func pick(_ branch: String?) {
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
            label: "Branch",
            branches: ["main", "develop", "feature/login", "feature/signup", "hotfix/crash"],
            inUse: ["main"],
            empty: .placeholder(text: "Select branch…", loading: "Loading branches…"),
            selection: .constant("feature/login")
        )
        BranchPickerField(
            label: "Base branch",
            branches: ["main", "develop", "feature/login"],
            empty: .sentinel(label: "Current HEAD"),
            selection: .constant(String?.none)
        )
    }
    .formStyle(.grouped)
    .frame(width: 360)
}
