import SwiftUI

struct ContentView: View {
    var body: some View {
        Text(LocalizationKey.emptyTitle)
            .font(.title2)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ContentView()
}

private enum LocalizationKey {
    static let emptyTitle = String(localized: "empty.title")
}
