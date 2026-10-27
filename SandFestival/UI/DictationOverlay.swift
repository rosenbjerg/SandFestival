import AppKit
import SwiftUI

struct DictationOverlay: View {
    let controller: DictationController
    let returnFocus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                statusIcon
                Text(statusText)
                    .interfaceFont(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 12)
                actions
            }
            if !transcriptText.characters.isEmpty {
                Text(transcriptText)
                    .interfaceFont(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .pointerStyle(.default)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch controller.phase {
        case .listening:
            Image(systemName: "mic.fill")
                .foregroundStyle(.red)
                .symbolEffect(.pulse)
        case .preparing, .finishing, .refining:
            ProgressView()
                .controlSize(.small)
        case .held:
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .idle:
            EmptyView()
        }
    }

    private var statusText: String {
        switch controller.phase {
        case .idle:
            ""
        case .preparing(let progress?):
            String(format: String(localized: "dictation.status.downloading"), Int(progress * 100))
        case .preparing(nil):
            String(localized: "dictation.status.starting")
        case .listening:
            String(localized: "dictation.status.listening")
        case .finishing:
            String(localized: "dictation.status.finishing")
        case .refining:
            String(localized: "dictation.status.refining")
        case .held:
            String(localized: "dictation.status.held")
        case .failed(let message, _):
            message
        }
    }

    private var transcriptText: AttributedString {
        if case .held(let text) = controller.phase {
            return AttributedString(text)
        }
        var pending = AttributedString(controller.transcript.volatileSuffix)
        pending.foregroundColor = .secondary
        return AttributedString(controller.transcript.finalizedText) + pending
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: 8) {
            switch controller.phase {
            case .listening:
                discardButton
                button(String(localized: "dictation.action.done")) { controller.finish() }
            case .preparing:
                discardButton
            case .refining:
                discardButton
                button(String(localized: "dictation.action.skip_cleanup")) { controller.skipRefinement() }
            case .held(let text):
                discardButton
                button(String(localized: "dictation.action.copy")) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    controller.discard()
                }
                if controller.targetCanReceiveText {
                    button(String(localized: "dictation.action.paste_anyway")) { controller.pasteHeldText() }
                }
            case .failed(_, let offersPrivacySettings):
                if offersPrivacySettings {
                    button(String(localized: "dictation.action.open_privacy_settings")) {
                        NSWorkspace.shared.open(Self.microphonePrivacySettings)
                    }
                }
                button(String(localized: "dictation.action.dismiss")) { controller.discard() }
            case .idle, .finishing:
                EmptyView()
            }
        }
    }

    private var discardButton: some View {
        button(String(localized: "dictation.action.discard")) { controller.discard() }
    }

    private func button(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title) {
            action()
            returnFocus()
        }
        .controlSize(.small)
    }

    private static let microphonePrivacySettings = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
    )!
}
