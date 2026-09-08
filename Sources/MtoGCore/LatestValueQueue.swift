public struct LatestValueQueue<Element> {
    public let capacity: Int
    public private(set) var values: [Element] = []

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    @discardableResult
    public mutating func append(_ value: Element) -> Element? {
        var dropped: Element?
        if values.count == capacity {
            dropped = values.removeFirst()
        }
        values.append(value)
        return dropped
    }

    public mutating func removeFirst() -> Element? {
        values.isEmpty ? nil : values.removeFirst()
    }
}
