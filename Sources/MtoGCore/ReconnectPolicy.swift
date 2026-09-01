public struct ReconnectPolicy: Equatable, Sendable {
    public let maxAttempts: Int
    public let baseDelaySeconds: Int
    public let maximumDelaySeconds: Int

    public init(maxAttempts: Int, baseDelaySeconds: Int, maximumDelaySeconds: Int) {
        precondition(maxAttempts > 0 && baseDelaySeconds > 0 && maximumDelaySeconds >= baseDelaySeconds)
        self.maxAttempts = maxAttempts
        self.baseDelaySeconds = baseDelaySeconds
        self.maximumDelaySeconds = maximumDelaySeconds
    }

    public func delaySeconds(forAttempt attempt: Int) -> Int? {
        guard attempt > 0, attempt <= maxAttempts else { return nil }
        var delay = baseDelaySeconds
        for _ in 1..<attempt {
            if delay >= maximumDelaySeconds { return maximumDelaySeconds }
            delay = min(delay * 2, maximumDelaySeconds)
        }
        return delay
    }
}
