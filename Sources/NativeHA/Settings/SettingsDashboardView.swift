import NativeHACore
import SwiftUI

struct SettingsDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var stateStore: HAStateStore?
    var registryStore: HARegistryStore?
    var serverURL: URL?

    var body: some View {
        Group {
            if let stateStore = stateStore, let registryStore = registryStore {
                SettingsStoreReader(
                    stateStore: stateStore,
                    registryStore: registryStore,
                    serverURL: serverURL,
                    connectionState: appState.connectionState,
                    stores: appState.stores
                ) { model in
                    SettingsDashboardContent(model: model)
                }
            } else {
                SettingsDashboardContent(
                    model: SettingsDashboardModel(context: SettingsDashboardContext(
                        serverURL: serverURL,
                        connectionState: appState.connectionState,
                        stores: appState.stores
                    ))
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SettingsStoreReader<Content: View>: View {
    @ObservedObject var stateStore: HAStateStore
    @ObservedObject var registryStore: HARegistryStore

    var serverURL: URL?
    var connectionState: ConnectionState
    var stores: HomeAssistantStores
    let content: (SettingsDashboardModel) -> Content

    init(
        stateStore: HAStateStore,
        registryStore: HARegistryStore,
        serverURL: URL?,
        connectionState: ConnectionState,
        stores: HomeAssistantStores,
        @ViewBuilder content: @escaping (SettingsDashboardModel) -> Content
    ) {
        self.stateStore = stateStore
        self.registryStore = registryStore
        self.serverURL = serverURL
        self.connectionState = connectionState
        self.stores = stores
        self.content = content
    }

    var body: some View {
        content(SettingsDashboardModel(context: SettingsDashboardContext(
            serverURL: serverURL,
            connectionState: connectionState,
            stores: stores,
            config: stateStore.config,
            currentUser: stateStore.currentUser,
            states: stateStore.states,
            panels: stateStore.panels,
            registryEntries: registryStore.entities,
            entityRegistryEntries: registryStore.entityRegistry,
            devices: registryStore.devices,
            appsInfoDismissed: stateStore.userData["apps_info_dismissed"]?.boolValue ?? false
        )))
    }
}

private struct SettingsDashboardContent: View {
    var model: SettingsDashboardModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summary

                ForEach(model.sections) { section in
                    settingsSection(section)
                }
            }
            .padding()
            .frame(maxWidth: 680, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color.secondary.opacity(0.04))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Settings")
                .font(.title)
            Text(model.summary.title)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var summary: some View {
        CardChrome {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(model.summary.connectionStatus, systemImage: "network")
                        .font(.headline)
                    Spacer(minLength: 8)
                    Text(model.summary.version)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                summaryRow(label: "Server", value: model.summary.serverURL)
                summaryRow(label: "User", value: "\(model.summary.user) - \(model.summary.role)")
                summaryRow(label: "Stores", value: model.summary.storeCounts)
                summaryRow(label: "Frontend", value: model.summary.components)
            }
        }
    }

    private func settingsSection(_ section: SettingsSection) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(section.title)
                .font(.headline)
                .padding(.horizontal, 2)

            CardChrome(contentInsets: EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0)) {
                VStack(spacing: 0) {
                    ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 58)
                        }
                        SettingsNavigationRow(item: item)
                    }
                }
            }
        }
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
        }
        .font(.subheadline)
    }
}

private struct SettingsNavigationRow: View {
    var item: SettingsNavigationItem

    var body: some View {
        Group {
            if let url = item.fallbackURL {
                Link(destination: url) {
                    rowContent
                }
            } else {
                rowContent
            }
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 12) {
            Image(systemName: item.iconSystemName)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color(hex: item.colorHex) ?? Color.accentColor))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
    }
}

private extension HAJSONValue {
    var boolValue: Bool? {
        guard case let .bool(value) = self else {
            return nil
        }
        return value
    }
}

private extension Color {
    init?(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard trimmed.count == 6,
              let raw = Int(trimmed, radix: 16) else {
            return nil
        }
        self.init(
            red: Double((raw >> 16) & 0xff) / 255.0,
            green: Double((raw >> 8) & 0xff) / 255.0,
            blue: Double(raw & 0xff) / 255.0
        )
    }
}
