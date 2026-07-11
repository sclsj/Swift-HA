import Foundation

public actor TaskDebouncer {
    private let durationNanoseconds: UInt64
    private var task: Task<Void, Never>?

    public init(durationNanoseconds: UInt64) {
        self.durationNanoseconds = durationNanoseconds
    }

    public func debounce(action: @escaping () async -> Void) {
        task?.cancel()
        task = Task {
            do {
                try await Task.sleep(nanoseconds: durationNanoseconds)
                guard !Task.isCancelled else { return }
                await action()
            } catch {
                // Cancelled
            }
        }
    }
}
