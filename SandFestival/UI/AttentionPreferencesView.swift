import Intents
import SwiftUI
import UserNotifications

struct AttentionPreferencesView: View {
    @Bindable var preferences: AttentionPreferences
    let notifier: AttentionNotifier?

    @State private var focusAuthorization: INFocusStatusAuthorizationStatus = .notDetermined
    @State private var notificationAuthorization: UNAuthorizationStatus = .notDetermined

    var body: some View {
        Form {
            Section(String(localized: "preferences.section.events")) {
                ForEach(AttentionEvent.allCases) { event in
                    Toggle(
                        label(for: event),
                        isOn: binding(for: event)
                    )
                }

                Text(String(localized: "preferences.section.events.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section(String(localized: "preferences.section.dock")) {
                Picker(
                    String(localized: "preferences.dock.bounce_style"),
                    selection: $preferences.dockBounceStyle
                ) {
                    Text(String(localized: "preferences.dock.bounce.informational"))
                        .tag(DockBounceStyle.informational)
                    Text(String(localized: "preferences.dock.bounce.critical"))
                        .tag(DockBounceStyle.critical)
                }
                .pickerStyle(.radioGroup)

                Text(bounceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                focusAuthorizationRow
            }

            Section(String(localized: "preferences.section.notifications")) {
                Toggle(
                    String(localized: "preferences.notifications.enabled"),
                    isOn: $preferences.notificationsEnabled
                )
                .onChange(of: preferences.notificationsEnabled) { _, newValue in
                    guard newValue, let notifier else { return }
                    Task {
                        _ = await notifier.requestNotificationAuthorization()
                        notificationAuthorization = await notifier.notificationAuthorizationStatus()
                    }
                }

                Picker(
                    String(localized: "preferences.notifications.trigger"),
                    selection: $preferences.notificationTrigger
                ) {
                    Text(String(localized: "preferences.notifications.trigger.unfocused"))
                        .tag(NotificationTrigger.unfocusedOnly)
                    Text(String(localized: "preferences.notifications.trigger.always"))
                        .tag(NotificationTrigger.always)
                }
                .pickerStyle(.radioGroup)
                .disabled(!preferences.notificationsEnabled)

                if preferences.notificationsEnabled, notificationAuthorization == .denied {
                    Text(String(localized: "preferences.notifications.permission_denied"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section(String(localized: "preferences.section.sidebar")) {
                Toggle(
                    String(localized: "preferences.sidebar.auto_surface_active"),
                    isOn: $preferences.autoSurfaceActiveProject
                )

                Text(String(localized: "preferences.sidebar.auto_surface_active.description"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .task {
            focusAuthorization = notifier?.focusAuthorizationStatus ?? .notDetermined
            if let notifier {
                notificationAuthorization = await notifier.notificationAuthorizationStatus()
            }
        }
    }

    @ViewBuilder
    private var focusAuthorizationRow: some View {
        switch focusAuthorization {
        case .notDetermined:
            Button(String(localized: "preferences.dock.focus.grant")) {
                notifier?.requestFocusAuthorization()
                // The system prompt is async; re-read shortly after.
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    focusAuthorization = notifier?.focusAuthorizationStatus ?? .notDetermined
                }
            }
        case .denied, .restricted:
            Text(String(localized: "preferences.dock.focus.denied"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .authorized:
            Text(String(localized: "preferences.dock.focus.authorized"))
                .font(.caption)
                .foregroundStyle(.secondary)
        @unknown default:
            EmptyView()
        }
    }

    private func binding(for event: AttentionEvent) -> Binding<Bool> {
        Binding(
            get: { preferences.enabledEvents.contains(event) },
            set: { isOn in
                if isOn {
                    preferences.enabledEvents.insert(event)
                } else {
                    preferences.enabledEvents.remove(event)
                }
            }
        )
    }

    private func label(for event: AttentionEvent) -> String {
        switch event {
        case .permissionRequested:
            return String(localized: "preferences.events.permission_requested")
        case .inputRequested:
            return String(localized: "preferences.events.input_requested")
        case .blockedByAutoMode:
            return String(localized: "preferences.events.blocked_auto_mode")
        case .errored:
            return String(localized: "preferences.events.errored")
        case .finishedOutputting:
            return String(localized: "preferences.events.finished_outputting")
        }
    }

    private var bounceDescription: String {
        switch preferences.dockBounceStyle {
        case .informational:
            return String(localized: "preferences.dock.description.informational")
        case .critical:
            return String(localized: "preferences.dock.description.critical")
        }
    }
}

#Preview {
    AttentionPreferencesView(
        preferences: AttentionPreferences(defaults: UserDefaults(suiteName: "preview")!),
        notifier: nil
    )
}
