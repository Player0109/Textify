import Dispatch

public struct SystemRuntimeClock: RuntimeClock {
    public init() {}

    public func nowMilliseconds() -> Int {
        Int(DispatchTime.now().uptimeNanoseconds / 1_000_000)
    }

    public func sleep(milliseconds: Int) async {
        guard milliseconds > 0 else {
            return
        }

        let (nanoseconds, overflow) = UInt64(milliseconds).multipliedReportingOverflow(by: 1_000_000)
        try? await Task.sleep(nanoseconds: overflow ? UInt64.max : nanoseconds)
    }
}
