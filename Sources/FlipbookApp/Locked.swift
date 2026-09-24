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

import Foundation

extension Timer {
    /// A timer on the main run loop in the common modes, so it keeps firing while a menu is open.
    @discardableResult
    static func onMainRunLoop(interval: TimeInterval, repeats: Bool,
                              _ block: @escaping @Sendable (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}
