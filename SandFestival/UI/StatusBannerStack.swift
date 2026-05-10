import SwiftUI

struct StatusBannerStack: View {
    let banners: [Banner]

    var body: some View {
        if !banners.isEmpty {
            VStack(spacing: 0) {
                ForEach(banners) { banner in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: banner.severity.iconName)
                            .foregroundStyle(banner.severity.tint)
                        Text(banner.message)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button {
                            banner.dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                        .help(String(localized: "banner.dismiss"))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(banner.severity.tint.opacity(0.18))
                }
                Divider()
            }
        }
    }

    struct Banner: Identifiable {
        let id = UUID()
        let message: String
        let severity: Severity
        let dismiss: () -> Void
    }

    enum Severity {
        case warning, error

        var iconName: String {
            switch self {
            case .warning: return "exclamationmark.triangle.fill"
            case .error: return "exclamationmark.octagon.fill"
            }
        }

        var tint: Color {
            switch self {
            case .warning: return .orange
            case .error: return .red
            }
        }
    }
}
