import SwiftUI

struct HookInstallSheet: View {
    @Bindable var adapter: ClaudeCodeAdapter
    let onInstall: () -> Void
    let onSkip: () -> Void

    @State private var preview: SettingsDiffPreview?
    @State private var showingPreview = false

    var body: some View {
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
                    preview = adapter.previewInstallation()
                    showingPreview = preview != nil
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
        .sheet(isPresented: $showingPreview) {
            if let preview {
                SettingsPreviewSheet(preview: preview, onClose: { showingPreview = false })
            }
        }
    }
}

struct SettingsPreviewSheet: View {
    let preview: SettingsDiffPreview
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "hooks.preview.title"))
                .font(.title3)
                .bold()

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "hooks.preview.before"))
                    .font(.headline)
                ScrollView {
                    Text(preview.before)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 180)
                .background(.quaternary.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))

                Text(String(localized: "hooks.preview.after"))
                    .font(.headline)
                ScrollView {
                    Text(preview.after)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 240)
                .background(.quaternary.opacity(0.5))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.tertiary))
            }

            HStack {
                Spacer()
                Button(String(localized: "hooks.preview.close"), action: onClose)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 720, height: 560)
    }
}
