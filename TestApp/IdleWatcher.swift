import CoreGraphics
import Foundation

/// Polls the system idle time and calls `onIdle` once per idle period.
/// Resets automatically when the user becomes active again.
final class IdleWatcher {

    private var timer: Timer?
    private var threshold: TimeInterval = 0
    private var didFire = false
    let onIdle: () -> Void

    init(onIdle: @escaping () -> Void) {
        self.onIdle = onIdle
    }

    // MARK: - Public

    func start(threshold: TimeInterval) {
        stop()
        guard threshold > 0 else { return }
        self.threshold = threshold
        self.didFire   = false
        let t = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.check() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer   = nil
        didFire = false
    }

    func resetIdleState() {
        didFire = false
    }

    // MARK: - Private

    private func check() {
        // kCGAnyInputEventType == ~UInt32(0); gives seconds since any input.
        let anyInput = CGEventType(rawValue: ~UInt32(0))!   // kCGAnyInputEventType
        let idle = CGEventSource.secondsSinceLastEventType(
            .combinedSessionState,
            eventType: anyInput
        )

        if idle >= threshold && !didFire {
            didFire = true
            onIdle()
        } else if idle < threshold && didFire {
            didFire = false
        }
    }
}
