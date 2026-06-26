import Foundation

/// Fixed-capacity ring buffer for time-series samples.
///
/// Backs the live RSSI/Noise/SNR/TxRate/MCS/CCA charts (spec §4.2). Memory is bounded
/// by `capacity` regardless of session length, which keeps multi-hour logging stable
/// (spec §5 performance). O(1) append, O(n) ordered read.
public struct RingBuffer<Element> {
    private var storage: [Element] = []
    private var head = 0
    public let capacity: Int

    public init(capacity: Int) {
        precondition(capacity > 0, "capacity must be positive")
        self.capacity = capacity
        storage.reserveCapacity(capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }
    public var isFull: Bool { storage.count == capacity }

    public mutating func append(_ element: Element) {
        if storage.count < capacity {
            storage.append(element)
        } else {
            storage[head] = element
            head = (head + 1) % capacity
        }
    }

    /// Elements in insertion order (oldest first).
    public var elements: [Element] {
        guard isFull else { return storage }
        return Array(storage[head...] + storage[..<head])
    }

    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }
}
