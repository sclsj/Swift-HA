import Foundation

public protocol HAReconnectSubscription {
    func cancel()
}

public protocol HAReconnectEventSource {
    func subscribeReconnects(onReconnect: @escaping () -> Void) -> HAReconnectSubscription
}

public struct PlaceholderHAReconnectEventSource: HAReconnectEventSource {
    public init() {}

    public func subscribeReconnects(onReconnect: @escaping () -> Void) -> HAReconnectSubscription {
        HAReconnectObservation {}
    }
}

public final class HAReconnectObservation: HAReconnectSubscription {
    private let lock = NSLock()
    private var cancellationHandler: (() -> Void)?

    init(cancellationHandler: @escaping () -> Void) {
        self.cancellationHandler = cancellationHandler
    }

    public func cancel() {
        lock.lock()
        let handler = cancellationHandler
        cancellationHandler = nil
        lock.unlock()
        handler?()
    }

    deinit {
        cancel()
    }
}

public final class HAConnection: HAClientProtocol, HAReconnectEventSource {
    public let stateStore: HAStateStore
    public let registryStore: HARegistryStore

    public private(set) var client: HAWebSocketClientProtocol?
    public private(set) var serviceClient: HAServiceClient?

    private let credentialProvider: CredentialProvider?
    private let logger: Logger?
    private var subscriptions: [HASubscription] = []
    private let reconnectObserversLock = NSLock()
    private var reconnectObservers: [UUID: () -> Void] = [:]

    public init(
        credentialProvider: CredentialProvider,
        stateStore: HAStateStore = HAStateStore(),
        registryStore: HARegistryStore = HARegistryStore(),
        logger: Logger? = nil
    ) {
        self.credentialProvider = credentialProvider
        self.stateStore = stateStore
        self.registryStore = registryStore
        self.logger = logger
    }

    public init(
        client: HAWebSocketClientProtocol,
        stateStore: HAStateStore = HAStateStore(),
        registryStore: HARegistryStore = HARegistryStore(),
        logger: Logger? = nil
    ) {
        self.credentialProvider = nil
        self.client = client
        self.serviceClient = HAServiceClient(client: client)
        self.stateStore = stateStore
        self.registryStore = registryStore
        self.logger = logger
    }

    public func connect() async throws {
        let client = try resolvedClient()
        installReconnectRefresh(on: client)
        try await client.connect()
        try await subscribeToUpdates()
        try await refreshStores()
    }

    public func disconnect() async {
        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions.removeAll()
        (client as? HAWebSocketReconnectNotifying)?.onReconnect = nil
        await client?.disconnect()
    }

    public func refreshStores() async throws {
        guard let client = client else {
            throw HAWebSocketClientError.disconnected
        }

        async let stateRefresh: Void = stateStore.refresh(using: client)
        async let registryRefresh: Void = registryStore.refresh(using: client)
        _ = try await (stateRefresh, registryRefresh)
    }

    public func subscribeReconnects(onReconnect: @escaping () -> Void) -> HAReconnectSubscription {
        let id = UUID()
        reconnectObserversLock.lock()
        reconnectObservers[id] = onReconnect
        reconnectObserversLock.unlock()
        return HAReconnectObservation { [weak self] in
            self?.removeReconnectObserver(id: id)
        }
    }

    @MainActor
    public var storeSummary: HomeAssistantStores {
        HomeAssistantStores(
            statesCount: stateStore.states.count,
            entitiesCount: registryStore.entities.count,
            devicesCount: registryStore.devices.count,
            areasCount: registryStore.areas.count,
            floorsCount: registryStore.floors.count,
            servicesCount: stateStore.services.count,
            panelsCount: stateStore.panels.count
        )
    }

    private func resolvedClient() throws -> HAWebSocketClientProtocol {
        if let client = client {
            return client
        }
        guard let credentialProvider = credentialProvider else {
            throw HAWebSocketClientError.disconnected
        }

        let auth = try HAAuth(credentialProvider: credentialProvider)
        let client = HAWebSocketClient(auth: auth, logger: logger)
        self.client = client
        self.serviceClient = HAServiceClient(client: client)
        return client
    }

    private func subscribeToUpdates() async throws {
        guard let client = client else {
            throw HAWebSocketClientError.disconnected
        }

        for subscription in subscriptions {
            subscription.cancel()
        }
        subscriptions.removeAll()

        let stateSubscription: HASubscription = try await client.subscribe(
            HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string("state_changed")])
        ) { [weak self] (event: HAEvent<HAStateChangedEventData>) in
            guard let stateStore = self?.stateStore else {
                return
            }
            Task { @MainActor in
                stateStore.apply(stateChanged: event)
            }
        }
        subscriptions.append(stateSubscription)

        try await subscribeRegistryRefresh(
            client: client,
            eventType: "entity_registry_updated"
        ) { [weak self] in
            guard let self = self, let client = self.client else {
                return
            }
            try await self.registryStore.refreshEntityDisplay(using: client)
            try await self.registryStore.refreshEntityRegistry(using: client)
        }

        try await subscribeRegistryRefresh(
            client: client,
            eventType: "device_registry_updated"
        ) { [weak self] in
            guard let self = self, let client = self.client else {
                return
            }
            try await self.registryStore.refreshDevices(using: client)
        }

        try await subscribeRegistryRefresh(
            client: client,
            eventType: "area_registry_updated"
        ) { [weak self] in
            guard let self = self, let client = self.client else {
                return
            }
            try await self.registryStore.refreshAreas(using: client)
        }

        try await subscribeRegistryRefresh(
            client: client,
            eventType: "floor_registry_updated"
        ) { [weak self] in
            guard let self = self, let client = self.client else {
                return
            }
            try await self.registryStore.refreshFloors(using: client)
        }

        try await subscribeRegistryRefresh(
            client: client,
            eventType: "panels_updated"
        ) { [weak self] in
            guard let self = self, let client = self.client else {
                return
            }
            let panels: HAPanels = try await client.callWS(HAWebSocketRequest(type: "get_panels"))
            await self.stateStore.apply(panels: panels)
        }
    }

    private func installReconnectRefresh(on client: HAWebSocketClientProtocol) {
        (client as? HAWebSocketReconnectNotifying)?.onReconnect = { [weak self] in
            self?.notifyReconnectObservers()
            Task { [weak self] in
                guard let self = self else {
                    return
                }
                do {
                    try await self.subscribeToUpdates()
                    try await self.refreshStores()
                } catch {
                    self.logger?.warning(
                        "Failed to refresh Home Assistant stores after reconnect",
                        metadata: ["error": String(describing: error)]
                    )
                }
            }
        }
    }

    private func notifyReconnectObservers() {
        reconnectObserversLock.lock()
        let observers = Array(reconnectObservers.values)
        reconnectObserversLock.unlock()
        observers.forEach { $0() }
    }

    private func removeReconnectObserver(id: UUID) {
        reconnectObserversLock.lock()
        reconnectObservers.removeValue(forKey: id)
        reconnectObserversLock.unlock()
    }

    private func subscribeRegistryRefresh(
        client: HAWebSocketClientProtocol,
        eventType: String,
        refresh: @escaping () async throws -> Void
    ) async throws {
        let subscription: HASubscription = try await client.subscribe(
            HAWebSocketRequest(type: "subscribe_events", payload: ["event_type": .string(eventType)])
        ) { [weak self] (_: HAEvent<[String: HAJSONValue]>) in
            let logger = self?.logger
            Task {
                do {
                    try await refresh()
                } catch {
                    logger?.warning(
                        "Failed to refresh Home Assistant store after registry event",
                        metadata: ["event_type": eventType, "error": String(describing: error)]
                    )
                }
            }
        }
        subscriptions.append(subscription)
    }
}
