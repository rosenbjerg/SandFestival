import SwiftUI

struct BranchPickerField: View {
    enum EmptySelection {
        case sentinel(label: String)
        case placeholder(text: String, loading: String)
    }

    let label: String
    let refs: [GitRef]
    var inUse: Set<String> = []
    let empty: EmptySelection
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
            .disabled(refs.isEmpty && sentinelLabel == nil)
            .popover(isPresented: $isExpanded, arrowEdge: .bottom) {
                popover
            }
        }
    }

    private var sentinelLabel: String? {
        if case .sentinel(let label) = empty { return label }
        return nil
    }

    private var hasSelection: Bool {
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
            return refs.isEmpty ? loading : text
        }
    }

    private var filtered: [GitRef] {
        Self.matching(refs, filter: filter)
    }

    private var showsSectionHeaders: Bool {
        refs.contains { $0.kind == .remote }
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
                        section(
                            String(localized: "duplicate.field.branch.section.local"),
                            refs: filtered.filter { $0.kind == .local }
                        )
                        section(
                            String(localized: "duplicate.field.branch.section.remote"),
                            refs: filtered.filter { $0.kind == .remote }
                        )
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(width: 280, height: 320)
        .onAppear { searchFocused = true }
    }

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
    private func section(_ title: String, refs: [GitRef]) -> some View {
        if !refs.isEmpty {
            if showsSectionHeaders {
                Text(title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            ForEach(refs, id: \.name) { ref in
                branchRow(ref.name)
            }
        }
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

    private func pickFirstMatch() {
        guard let match = filtered.first(where: { !inUse.contains($0.name) }) else { return }
        pick(match.name)
    }

    static func matching(_ refs: [GitRef], filter: String) -> [GitRef] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return refs }
        return refs.filter { $0.name.range(of: query, options: .caseInsensitive) != nil }
    }
}

#Preview {
    Form {
        BranchPickerField(
            label: "Branch",
            refs: ["main", "develop", "feature/login", "feature/signup", "hotfix/crash"]
                .map { GitRef(name: $0, kind: .local) },
            inUse: ["main"],
            empty: .placeholder(text: "Select branch…", loading: "Loading branches…"),
            selection: .constant("feature/login")
        )
        BranchPickerField(
            label: "Base branch",
            refs: ["main", "develop"].map { GitRef(name: $0, kind: .local) }
                + ["origin/main", "origin/develop"].map { GitRef(name: $0, kind: .remote) },
            empty: .sentinel(label: "Current HEAD"),
            selection: .constant(String?.none)
        )
    }
    .formStyle(.grouped)
    .frame(width: 360)
}
