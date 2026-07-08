import NativeHACore
import SwiftUI

private struct NativeHAEnvironmentKey: EnvironmentKey {
    static let defaultValue = AppEnvironment.development()
}

private extension EnvironmentValues {
    var nativeHAEnvironment: AppEnvironment {
        get { self[NativeHAEnvironmentKey.self] }
        set { self[NativeHAEnvironmentKey.self] = newValue }
    }
}

@main
struct NativeHAApp: App {
    @StateObject private var appState: AppState
    private let environment: AppEnvironment

    init() {
        let environment = AppEnvironment.development()
        self.environment = environment
        _appState = StateObject(wrappedValue: AppState(environment: environment))
    }

    var body: some Scene {
        WindowGroup {
            RootShellView()
                .environmentObject(appState)
                .environment(\.nativeHAEnvironment, environment)
        }
    }
}

private struct RootShellView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.nativeHAEnvironment) private var environment
    @State private var didStartConnection = false

    var body: some View {
        NavigationView {
            List(selection: routeBinding) {
                NavigationLink(tag: AppRoute.dashboardList, selection: routeBinding) {
                    dashboardPanel(
                        dashboardPath: appState.selectedDashboardPath ?? "/lovelace",
                        viewPath: nil,
                        viewIndex: nil
                    )
                } label: {
                    Text("Dashboards")
                }

                NavigationLink(tag: AppRoute.settings, selection: routeBinding) {
                    RoutePlaceholderView(title: "Settings")
                } label: {
                    Text("Settings")
                }
            }
            .listStyle(.sidebar)

            routeDetail
        }
        .frame(minWidth: 720, minHeight: 480)
        .sheet(item: moreInfoBinding) { route in
            RoutePlaceholderView(title: route.title)
                .frame(minWidth: 320, minHeight: 220)
        }
        .onAppear {
            environment.logger.info("NativeHA app shell appeared")
            startConnectionIfNeeded()
        }
    }

    @ViewBuilder
    private var routeDetail: some View {
        switch appState.route {
        case .dashboardList:
            dashboardPanel(
                dashboardPath: appState.selectedDashboardPath ?? "/lovelace",
                viewPath: nil,
                viewIndex: nil
            )
        case let .dashboard(urlPath):
            dashboardPanel(dashboardPath: urlPath, viewPath: nil, viewIndex: nil)
        case let .lovelaceView(dashboardPath, viewPath, viewIndex):
            dashboardPanel(dashboardPath: dashboardPath, viewPath: viewPath, viewIndex: viewIndex)
        case let .moreInfo(entityID):
            RoutePlaceholderView(title: AppRoute.moreInfo(entityID: entityID).title)
        case .settings:
            RoutePlaceholderView(title: "Settings")
        }
    }

    private func dashboardPanel(
        dashboardPath: String,
        viewPath: String?,
        viewIndex: Int?
    ) -> some View {
        LovelacePanelView(
            environment: environment,
            dashboardPath: dashboardPath,
            viewPath: viewPath,
            viewIndex: viewIndex
        )
    }

    private var routeBinding: Binding<AppRoute?> {
        Binding(
            get: { appState.route },
            set: { route in
                if let route = route {
                    appState.navigate(to: route)
                }
            }
        )
    }

    private var moreInfoBinding: Binding<AppRoute?> {
        Binding(
            get: { appState.presentation.moreInfoRoute },
            set: { route in
                if let route = route {
                    appState.presentMoreInfo(entityID: route.entityIDForMoreInfo ?? "")
                } else {
                    appState.dismissMoreInfo()
                }
            }
        )
    }

    private func startConnectionIfNeeded() {
        guard !didStartConnection else {
            return
        }
        didStartConnection = true

        Task {
            await MainActor.run {
                appState.setConnectionState(.connecting)
            }

            do {
                try await environment.client.connect()
                await MainActor.run {
                    appState.setConnectionState(.connected)
                    if let connection = environment.client as? HAConnection {
                        appState.updateStores(connection.storeSummary)
                    }
                }
            } catch {
                await MainActor.run {
                    appState.setConnectionState(.failed(message: String(describing: error)))
                }
            }
        }
    }
}

private struct RoutePlaceholderView: View {
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.title)
            Text("Native Home Assistant shell")
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
