import Foundation

public struct SettingsDashboardContext: Equatable {
    public var serverURL: URL?
    public var connectionState: ConnectionState
    public var stores: HomeAssistantStores
    public var config: HAConfig?
    public var currentUser: HAUser?
    public var states: [EntityID: HassEntity]
    public var panels: HAPanels
    public var registryEntries: [EntityID: HAEntityRegistryDisplayEntry]
    public var entityRegistryEntries: [EntityID: HAEntityRegistryEntry]
    public var devices: [String: HADeviceRegistryEntry]
    public var appsInfoDismissed: Bool
    public var hasExternalSettings: Bool
    public var hasBluetoothConfigEntries: Bool?

    public init(
        serverURL: URL? = nil,
        connectionState: ConnectionState = .disconnected,
        stores: HomeAssistantStores = HomeAssistantStores(),
        config: HAConfig? = nil,
        currentUser: HAUser? = nil,
        states: [EntityID: HassEntity] = [:],
        panels: HAPanels = [:],
        registryEntries: [EntityID: HAEntityRegistryDisplayEntry] = [:],
        entityRegistryEntries: [EntityID: HAEntityRegistryEntry] = [:],
        devices: [String: HADeviceRegistryEntry] = [:],
        appsInfoDismissed: Bool = false,
        hasExternalSettings: Bool = false,
        hasBluetoothConfigEntries: Bool? = nil
    ) {
        self.serverURL = serverURL
        self.connectionState = connectionState
        self.stores = stores
        self.config = config
        self.currentUser = currentUser
        self.states = states
        self.panels = panels
        self.registryEntries = registryEntries
        self.entityRegistryEntries = entityRegistryEntries
        self.devices = devices
        self.appsInfoDismissed = appsInfoDismissed
        self.hasExternalSettings = hasExternalSettings
        self.hasBluetoothConfigEntries = hasBluetoothConfigEntries
    }
}

public struct SettingsDashboardModel: Equatable {
    public var summary: SettingsConnectionSummary
    public var sections: [SettingsSection]

    public init(context: SettingsDashboardContext) {
        let router = SettingsRouter(baseURL: context.serverURL)
        summary = SettingsConnectionSummary(context: context)
        sections = SettingsPageCatalog.dashboardSections(context: context, router: router)
    }
}

public struct SettingsConnectionSummary: Equatable {
    public var title: String
    public var connectionStatus: String
    public var serverURL: String
    public var version: String
    public var user: String
    public var role: String
    public var storeCounts: String
    public var components: String

    public init(context: SettingsDashboardContext) {
        title = context.config?.locationName.nilIfEmpty ?? "Home Assistant"
        connectionStatus = Self.connectionStatus(context.connectionState)
        serverURL = context.serverURL?.absoluteString
            ?? context.config?.externalURL?.nilIfEmpty
            ?? context.config?.internalURL?.nilIfEmpty
            ?? "Not configured"
        version = context.config?.version.nilIfEmpty ?? "Unknown"
        user = context.currentUser?.name.nilIfEmpty ?? "Unknown user"
        role = Self.role(for: context.currentUser)
        storeCounts = [
            "\(context.stores.statesCount) states",
            "\(context.stores.entitiesCount) entities",
            "\(context.stores.devicesCount) devices",
            "\(context.stores.areasCount) areas"
        ].joined(separator: ", ")
        components = "\(context.config?.components.count ?? 0) components"
    }

    private static func connectionStatus(_ state: ConnectionState) -> String {
        switch state {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case let .failed(message):
            return message.isEmpty ? "Failed" : "Failed: \(message)"
        }
    }

    private static func role(for user: HAUser?) -> String {
        guard let user = user else {
            return "Unknown"
        }
        if user.isOwner {
            return "Owner"
        }
        if user.isAdmin {
            return "Administrator"
        }
        return "User"
    }
}

public struct SettingsSection: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var items: [SettingsNavigationItem]

    public init(id: String, title: String, items: [SettingsNavigationItem]) {
        self.id = id
        self.title = title
        self.items = items
    }
}

public struct SettingsNavigationItem: Equatable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String
    public var path: String
    public var iconSystemName: String
    public var colorHex: String
    public var fallbackURL: URL?

    public init(
        id: String,
        title: String,
        subtitle: String,
        path: String,
        iconSystemName: String,
        colorHex: String,
        fallbackURL: URL?
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.iconSystemName = iconSystemName
        self.colorHex = colorHex
        self.fallbackURL = fallbackURL
    }
}

private enum SettingsPageCatalog {
    static func dashboardSections(
        context: SettingsDashboardContext,
        router: SettingsRouter
    ) -> [SettingsSection] {
        [
            SettingsSection(
                id: "primary",
                title: "Home Assistant",
                items: visible([
                    companionAppPage,
                    cloudPage,
                    devicesPage,
                    automationsPage,
                    areasPage,
                    appsPage,
                    dashboardsPage,
                    voiceAssistantsPage
                ], context: context, router: router)
            ),
            SettingsSection(
                id: "integrations",
                title: "Integrations",
                items: visible([
                    matterPage,
                    zhaPage,
                    zwavePage,
                    knxPage,
                    threadPage,
                    bluetoothPage,
                    infraredPage,
                    radioFrequencyPage,
                    insteonPage,
                    tagsPage
                ], context: context, router: router)
            ),
            SettingsSection(
                id: "system",
                title: "System",
                items: visible([
                    peoplePage,
                    systemPage,
                    toolsPage,
                    aboutPage
                ], context: context, router: router)
            )
        ].filter { !$0.items.isEmpty }
    }

    private static func visible(
        _ pages: [SettingsPageDefinition],
        context: SettingsDashboardContext,
        router: SettingsRouter
    ) -> [SettingsNavigationItem] {
        pages.compactMap { page -> SettingsNavigationItem? in
            guard canShow(page, context: context) else {
                return nil
            }
            return page.item(router: router)
        }
    }

    private static func canShow(_ page: SettingsPageDefinition, context: SettingsDashboardContext) -> Bool {
        if page.externalOnly && !context.hasExternalSettings {
            return false
        }
        if page.adminOnly && context.currentUser?.isAdmin != true {
            return false
        }
        if page.id == "apps",
           context.appsInfoDismissed,
           !isComponentLoaded("hassio", context: context) {
            return false
        }
        if page.id == "bluetooth" {
            return context.hasBluetoothConfigEntries ?? false
        }

        let componentVisible = page.core
            || page.components.isEmpty
            || page.components.contains { isComponentLoaded($0, context: context) }
        guard componentVisible else {
            return false
        }
        return page.filter?(context) ?? true
    }

    private static func isComponentLoaded(_ component: String, context: SettingsDashboardContext) -> Bool {
        context.config?.components.contains(component) == true
    }

    private static func hasDomain(_ domain: String, context: SettingsDashboardContext) -> Bool {
        let prefix = "\(domain)."
        return context.states.keys.contains { $0.hasPrefix(prefix) }
            || context.registryEntries.keys.contains { $0.hasPrefix(prefix) }
            || context.entityRegistryEntries.keys.contains { $0.hasPrefix(prefix) }
    }


    private static let companionAppPage = SettingsPageDefinition(
        id: "companion_app",
        title: "Companion App",
        subtitle: "App settings and configuration",
        path: "#external-app-configuration",
        iconSystemName: "iphone",
        colorHex: "#8E24AA",
        core: true,
        adminOnly: false,
        externalOnly: true
    )

    private static let cloudPage = SettingsPageDefinition(
        id: "cloud",
        title: "Home Assistant Cloud",
        subtitle: "Remote access and cloud services",
        path: "/config/cloud",
        iconSystemName: "lock.icloud",
        colorHex: "#3B808E",
        components: ["cloud"],
        adminOnly: false
    )

    private static let devicesPage = SettingsPageDefinition(
        id: "devices",
        title: "Devices & services",
        subtitle: "Integrations, devices, entities, and helpers",
        path: "/config/integrations",
        iconSystemName: "sensor.tag.radiowaves.forward",
        colorHex: "#0D47A1",
        core: true
    )

    private static let automationsPage = SettingsPageDefinition(
        id: "automations",
        title: "Automations & scenes",
        subtitle: "Automations, scenes, scripts, and blueprints",
        path: "/config/automation",
        iconSystemName: "gearshape.2",
        colorHex: "#518C43"
    )

    private static let areasPage = SettingsPageDefinition(
        id: "areas",
        title: "Areas, labels & zones",
        subtitle: "Organize rooms, areas, labels, and zones",
        path: "/config/areas",
        iconSystemName: "sofa",
        colorHex: "#E48629",
        components: ["zone"]
    )

    private static let appsPage = SettingsPageDefinition(
        id: "apps",
        title: "Apps",
        subtitle: "Mobile and companion apps",
        path: "/config/apps",
        iconSystemName: "app.connected.to.app.below.fill",
        colorHex: "#F1C447",
        core: true
    )

    private static let dashboardsPage = SettingsPageDefinition(
        id: "dashboards",
        title: "Dashboards",
        subtitle: "Lovelace dashboards and resources",
        path: "/config/lovelace/dashboards",
        iconSystemName: "rectangle.grid.2x2",
        colorHex: "#B1345C",
        components: ["lovelace"]
    )

    private static let voiceAssistantsPage = SettingsPageDefinition(
        id: "voice-assistants",
        title: "Voice Assistants",
        subtitle: "Assist pipelines and voice settings",
        path: "/config/voice-assistants",
        iconSystemName: "mic",
        colorHex: "#3263C3"
    )

    private static let matterPage = SettingsPageDefinition(
        id: "matter",
        title: "Matter",
        subtitle: "Matter devices and fabric settings",
        path: "/config/matter",
        iconSystemName: "hexagon",
        colorHex: "#2458B3",
        components: ["matter"]
    )

    private static let zhaPage = SettingsPageDefinition(
        id: "zha",
        title: "ZHA",
        subtitle: "Zigbee Home Automation",
        path: "/config/zha",
        iconSystemName: "dot.radiowaves.left.and.right",
        colorHex: "#E74011",
        components: ["zha"]
    )

    private static let zwavePage = SettingsPageDefinition(
        id: "zwave_js",
        title: "Z-Wave",
        subtitle: "Z-Wave JS configuration",
        path: "/config/zwave_js",
        iconSystemName: "wave.3.right",
        colorHex: "#153163",
        components: ["zwave_js"]
    )

    private static let knxPage = SettingsPageDefinition(
        id: "knx",
        title: "KNX",
        subtitle: "KNX integration settings",
        path: "/knx",
        iconSystemName: "network",
        colorHex: "#4EAA66",
        components: ["knx"]
    )

    private static let threadPage = SettingsPageDefinition(
        id: "thread",
        title: "Thread",
        subtitle: "Thread network settings",
        path: "/config/thread",
        iconSystemName: "point.3.connected.trianglepath.dotted",
        colorHex: "#ED7744",
        components: ["thread"]
    )

    private static let bluetoothPage = SettingsPageDefinition(
        id: "bluetooth",
        title: "Bluetooth",
        subtitle: "Bluetooth adapters and discovery",
        path: "/config/bluetooth",
        iconSystemName: "antenna.radiowaves.left.and.right",
        colorHex: "#0082FC",
        components: ["bluetooth"]
    )

    private static let infraredPage = SettingsPageDefinition(
        id: "infrared",
        title: "Infrared",
        subtitle: "Infrared devices",
        path: "/config/infrared",
        iconSystemName: "sensor",
        colorHex: "#9C27B0",
        filter: { hasDomain("infrared", context: $0) }
    )

    private static let radioFrequencyPage = SettingsPageDefinition(
        id: "radio_frequency",
        title: "Radio-frequency",
        subtitle: "Radio-frequency devices",
        path: "/config/radio-frequency",
        iconSystemName: "radio",
        colorHex: "#E74011",
        components: ["radio_frequency"],
        filter: { hasDomain("radio_frequency", context: $0) }
    )

    private static let insteonPage = SettingsPageDefinition(
        id: "insteon",
        title: "Insteon",
        subtitle: "Insteon integration settings",
        path: "/insteon",
        iconSystemName: "sparkles",
        colorHex: "#E4002C",
        components: ["insteon"]
    )

    private static let tagsPage = SettingsPageDefinition(
        id: "tags",
        title: "Tags",
        subtitle: "NFC tags",
        path: "/config/tags",
        iconSystemName: "tag",
        colorHex: "#616161",
        components: ["tag"]
    )

    private static let peoplePage = SettingsPageDefinition(
        id: "people",
        title: "People",
        subtitle: "People and users",
        path: "/config/person",
        iconSystemName: "person.crop.circle",
        colorHex: "#5A87FA",
        components: ["person", "users"]
    )

    private static let systemPage = SettingsPageDefinition(
        id: "system",
        title: "System",
        subtitle: "Core, updates, repairs, logs, and hardware",
        path: "/config/system",
        iconSystemName: "gearshape",
        colorHex: "#301ABE",
        core: true
    )

    private static let toolsPage = SettingsPageDefinition(
        id: "tools",
        title: "Tools",
        subtitle: "Developer tools and diagnostics",
        path: "/config/tools",
        iconSystemName: "hammer",
        colorHex: "#7A5AA6",
        core: true
    )

    private static let aboutPage = SettingsPageDefinition(
        id: "about",
        title: "About",
        subtitle: "Home Assistant information",
        path: "/config/info",
        iconSystemName: "info.circle",
        colorHex: "#4A5963",
        core: true
    )
}

private struct SettingsPageDefinition {
    var id: String
    var title: String
    var subtitle: String
    var path: String
    var iconSystemName: String
    var colorHex: String
    var components: [String]
    var core: Bool
    var adminOnly: Bool
    var externalOnly: Bool
    var filter: ((SettingsDashboardContext) -> Bool)?

    init(
        id: String,
        title: String,
        subtitle: String,
        path: String,
        iconSystemName: String,
        colorHex: String,
        components: [String] = [],
        core: Bool = false,
        adminOnly: Bool = true,
        externalOnly: Bool = false,
        filter: ((SettingsDashboardContext) -> Bool)? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.path = path
        self.iconSystemName = iconSystemName
        self.colorHex = colorHex
        self.components = components
        self.core = core
        self.adminOnly = adminOnly
        self.externalOnly = externalOnly
        self.filter = filter
    }

    func item(router: SettingsRouter) -> SettingsNavigationItem {
        SettingsNavigationItem(
            id: id,
            title: title,
            subtitle: subtitle,
            path: path,
            iconSystemName: iconSystemName,
            colorHex: colorHex,
            fallbackURL: router.fallbackURL(for: path)
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
