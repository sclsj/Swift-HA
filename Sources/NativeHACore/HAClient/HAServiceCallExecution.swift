import Foundation

public enum HAServiceCallExecutionResult: Equatable {
    case skipped
    case succeeded
    case failed
}

public enum HAServiceCallExecution {
    public static func execute(
        _ call: HAServiceCall?,
        executor: (HAServiceCall) async throws -> Void
    ) async -> HAServiceCallExecutionResult {
        guard let call = call else {
            return .skipped
        }

        do {
            try await executor(call)
            return .succeeded
        } catch {
            return .failed
        }
    }
}
