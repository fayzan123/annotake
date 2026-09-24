import Synchronization

/// A value shared between threads, guarded by a lock.
final class Locked<Value: Sendable>: Sendable {
    private let mutex: Mutex<Value>

    init(_ value: Value) {
        mutex = Mutex(value)
    }

    var value: Value {
        get { mutex.withLock { $0 } }
        set { mutex.withLock { $0 = newValue } }
    }
}
