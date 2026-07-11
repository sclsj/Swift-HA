import NativeHACore
import SwiftUI

struct LovelacePanelView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var store: LovelaceStore

    private let dashboardPath: String
    private let viewPath: String?
    private let viewIndex: Int?
    private let stateStore: HAStateStore?
    private let registryStore: HARegistryStore?
    private let environment: AppEnvironment

    init(
        environment: AppEnvironment,
        dashboardPath: String,
        viewPath: String? = nil,
        viewIndex: Int? = nil
    ) {
        _store = StateObject(wrappedValue: LovelaceStore(environment: environment))
        self.environment = environment
        self.dashboardPath = AppRoute.dashboardPath(dashboardPath)
        self.viewPath = viewPath
        self.viewIndex = viewIndex
        self.stateStore = (environment.client as? HAConnection)?.stateStore
        self.registryStore = (environment.client as? HAConnection)?.registryStore
    }

    var body: some View {
        Group {
            if let stateStore = stateStore, let registryStore = registryStore {
                StoreReader(stateStore: stateStore, registryStore: registryStore) { displayContext, userName, userID in
                    rootView(displayContext: displayContext, userName: userName, userID: userID)
                }
            } else {
                rootView(displayContext: .empty, userName: "Home Assistant", userID: nil)
            }
        }
        .task(id: loadID) {
            guard appState.connectionState == .connected else {
                return
            }
            await store.load(
                dashboardPath: dashboardPath,
                viewPath: viewPath,
                viewIndex: viewIndex,
                userID: stateStore?.currentUser?.id
            )
        }
        .onChange(of: viewPath ?? "") { newValue in
            store.selectView(path: newValue.isEmpty ? nil : newValue)
        }
        .onChange(of: viewIndex ?? -1) { newValue in
            store.selectView(index: newValue >= 0 ? newValue : nil)
        }
    }

    private var loadID: String {
        "\(dashboardPath):\(connectionStateKey)"
    }

    private var connectionStateKey: String {
        switch appState.connectionState {
        case .disconnected:
            return "disconnected"
        case .connecting:
            return "connecting"
        case .connected:
            return "connected"
        case let .failed(message):
            return "failed:\(message)"
        }
    }

    private func rootView(displayContext: EntityDisplayContext, userName: String, userID: String?) -> some View {
        LovelaceRootView(
            store: store,
            selectedDashboardPath: dashboardPath,
            displayContext: displayContext,
            templateSubscriber: markdownTemplateSubscriber,
            userName: userName,
            userID: userID,
            onSelectDashboard: { dashboard in
                appState.navigate(to: .dashboard(urlPath: dashboard.path))
            },
            onSelectView: { route in
                appState.navigate(to: .lovelaceView(
                    dashboardPath: route.dashboardPath,
                    viewPath: route.selectedViewPath,
                    viewIndex: route.selectedViewPath == nil ? route.selectedViewIndex : nil
                ))
            },
            onRetry: {
                Task {
                    await store.refetch()
                }
            },
            onMoreInfo: { entityID in
                appState.presentMoreInfo(entityID: entityID)
            },
            onServiceCall: executeServiceCall
        )
        .environment(\.historyGraphDataProvider, historyGraphDataProvider)
        .environment(\.statisticsGraphDataProvider, statisticsGraphDataProvider)
    }

    private var markdownTemplateSubscriber: MarkdownTemplateSubscribing? {
        guard let client = (environment.client as? HAConnection)?.client else {
            return nil
        }
        return MarkdownTemplateClient(client: client)
    }

    private var historyGraphDataProvider: HistoryGraphDataProviding? {
        guard let client = (environment.client as? HAConnection)?.client else {
            return nil
        }
        return HomeAssistantHistoryGraphDataProvider(client: client)
    }

    private var statisticsGraphDataProvider: StatisticsGraphDataProviding? {
        guard let client = (environment.client as? HAConnection)?.client else {
            return nil
        }
        return HomeAssistantStatisticsGraphDataProvider(client: client)
    }

    private func executeServiceCall(_ call: HAServiceCall) {
        guard let serviceClient = (environment.client as? HAConnection)?.serviceClient else {
            return
        }

        Task {
            do {
                _ = try await serviceClient.callService(call)
            } catch {
                environment.logger.warning(
                    "Failed to execute Lovelace service call",
                    metadata: [
                        "domain": call.domain,
                        "service": call.service,
                        "error": String(describing: error)
                    ]
                )
            }
        }
    }
}

private struct StoreReader<Content: View>: View {
    @ObservedObject var stateStore: HAStateStore
    @ObservedObject var registryStore: HARegistryStore
    let content: (EntityDisplayContext, String, String?) -> Content

    init(
        stateStore: HAStateStore,
        registryStore: HARegistryStore,
        @ViewBuilder content: @escaping (EntityDisplayContext, String, String?) -> Content
    ) {
        self.stateStore = stateStore
        self.registryStore = registryStore
        self.content = content
    }

    var body: some View {
        content(
            EntityDisplayContext(
                states: stateStore.states,
                config: stateStore.config,
                registryEntries: registryStore.entities
            ),
            userName,
            stateStore.currentUser?.id
        )
    }

    private var userName: String {
        stateStore.currentUser?.name
            ?? stateStore.userData["user"]?.objectValue?["name"]?.stringValue
            ?? stateStore.userData["name"]?.stringValue
            ?? "Home Assistant"
    }
}
