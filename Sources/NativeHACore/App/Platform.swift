import Foundation

public enum PlatformOperatingSystem: String, Equatable {
    case macOS
    case iOS
    case unknown
}

public enum PlatformUserInterfaceIdiom: String, Equatable {
    case desktop
    case phone
    case pad
    case unknown
}

public struct PlatformTraits: Equatable {
    public var operatingSystem: PlatformOperatingSystem
    public var idiom: PlatformUserInterfaceIdiom
    public var isMac: Bool
    public var isMobile: Bool
    public var localeIdentifier: String
    public var timeZoneIdentifier: String

    public init(
        operatingSystem: PlatformOperatingSystem,
        idiom: PlatformUserInterfaceIdiom,
        isMac: Bool,
        isMobile: Bool,
        localeIdentifier: String,
        timeZoneIdentifier: String
    ) {
        self.operatingSystem = operatingSystem
        self.idiom = idiom
        self.isMac = isMac
        self.isMobile = isMobile
        self.localeIdentifier = localeIdentifier
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static var current: PlatformTraits {
        #if os(macOS)
        let operatingSystem: PlatformOperatingSystem = .macOS
        let idiom: PlatformUserInterfaceIdiom = .desktop
        let isMac = true
        let isMobile = false
        #elseif os(iOS)
        let operatingSystem: PlatformOperatingSystem = .iOS
        let idiom: PlatformUserInterfaceIdiom = .phone
        let isMac = false
        let isMobile = true
        #else
        let operatingSystem: PlatformOperatingSystem = .unknown
        let idiom: PlatformUserInterfaceIdiom = .unknown
        let isMac = false
        let isMobile = false
        #endif

        return PlatformTraits(
            operatingSystem: operatingSystem,
            idiom: idiom,
            isMac: isMac,
            isMobile: isMobile,
            localeIdentifier: Locale.current.identifier,
            timeZoneIdentifier: TimeZone.current.identifier
        )
    }
}
