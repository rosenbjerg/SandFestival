import SwiftUI

struct HookInstallSheet: View {
    @Bindable var adapter: ClaudeCodeAdapter
    let onInstall: () -> Void
    let onSkip: () -> Void

    @State private var displayedPreview: SettingsDiffPreview?

    var body: some View {
        Group {
            if let preview = displayedPreview {
                preview_body(preview)
            } else {
                installBody
            }
        }
    }

    // MARK: - Install prompt

    private var installBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(String(localized: "hooks.install.title"))
                .font(.title2)
                .bold()

            Text(String(localized: "hooks.install.body"))
                .fixedSize(horizontal: false, vertical: true)

            if let error = adapter.lastInstallError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Button(String(localized: "hooks.install.view_changes")) {
                    displayedPreview = adapter.previewInstallation()
                }
                Spacer()
                Button(String(localized: "hooks.install.skip"), role: .cancel) {
                    onSkip()
                }
                Button(String(localized: "hooks.install.install")) {
                    adapter.installHooks()
                    if adapter.lastInstallError == nil {
                        onInstall()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    // MARK: - Preview page

    private func preview_body(_ preview: SettingsDiffPreview) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "hooks.preview.title"))
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "hooks.preview.before"))
                    .font(.headline)
                previewBox(text: preview.before, height: 180)

                Text(String(localized: "hooks.preview.after"))
                    .font(.headline)
                previewBox(text: preview.after, height: 240)
            }

            HStack {
                Spacer()
                Button(String(localized: "hooks.preview.close")) {
                    displayedPreview = nil
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 720, height: 560)
    }

    private func previewBox(text: String, height: CGFloat) -> some View {
        ScrollView {
            Text(text.isEmpty ? "{}" : text)
                .font(.system(.callout, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(height: height)
        .background(.quaternary.opacity(0.5))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))
    }
}
