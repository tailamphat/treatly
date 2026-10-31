import Foundation
import IOKit.ps

/// Reads the Mac's battery so the pet can get tired when it runs low. Needs no
/// permission. On a Mac without a battery `percent` stays nil.
@MainActor
final class BatteryMonitor {
    private(set) var percent: Int?
    private(set) var charging = false
    /// When the charger was last plugged in, so the pet can cheer about it.
    private(set) var pluggedInAt: Date?
    private var timer: Timer?

    init() {
        read(announce: false)
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.read(announce: true) }
        }
    }

    private func read(announce: Bool) {
        let wasCharging = charging
        percent = nil
        charging = false
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            percent = Int((Double(current) / Double(max) * 100).rounded())
            charging = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
        }
        if announce, charging, !wasCharging { pluggedInAt = Date() }
    }
}
