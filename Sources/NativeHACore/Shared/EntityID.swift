import Foundation

public enum EntityIDParser {
    public static func domain(from entityID: EntityID) -> String {
        guard let separator = entityID.firstIndex(of: ".") else {
            return entityID
        }
        return String(entityID[..<separator])
    }

    public static func objectID(from entityID: EntityID) -> String {
        guard let separator = entityID.firstIndex(of: ".") else {
            return entityID
        }
        return String(entityID[entityID.index(after: separator)...])
    }

    public static func isValid(_ entityID: EntityID) -> Bool {
        let parts = entityID.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else {
            return false
        }

        return parts.allSatisfy { part in
            part.unicodeScalars.allSatisfy { scalar in
                scalar.value == 95
                    || (48...57).contains(scalar.value)
                    || (65...90).contains(scalar.value)
                    || (97...122).contains(scalar.value)
            }
        }
    }

    public static func displayObjectID(from entityID: EntityID) -> String {
        objectID(from: entityID).replacingOccurrences(of: "_", with: " ")
    }
}

public extension HassEntity {
    var objectID: String {
        EntityIDParser.objectID(from: entityID)
    }

    var computedDomain: String {
        EntityIDParser.domain(from: entityID)
    }
}
