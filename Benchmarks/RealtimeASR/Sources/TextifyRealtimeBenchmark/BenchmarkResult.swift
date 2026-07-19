import Darwin
import Foundation

struct BenchmarkResult: Codable {
    let schemaVersion: Int
    let engine: BenchmarkEngine
    let engineVersion: String
    let model: String
    let modelLicense: String
    let computeBackend: String
    let feedMode: FeedMode
    let host: HostSnapshot
    let audio: AudioSnapshot
    let timing: TimingSnapshot
    let accuracy: AccuracySnapshot?
    let resources: ResourceSnapshot
    let targets: TargetSnapshot
}

struct HostSnapshot: Codable {
    let chip: String
    let operatingSystem: String
    let architecture: String

    static func current() -> HostSnapshot {
        HostSnapshot(
            chip: sysctlString("machdep.cpu.brand_string") ?? "unknown",
            operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            architecture: architectureName
        )
    }
}

private let architectureName: String = {
    #if arch(arm64)
    return "arm64"
    #else
    return "unknown"
    #endif
}()

struct AudioSnapshot: Codable {
    let durationMs: Int
    let sampleRate: Int
    let sampleCount: Int
}

struct TimingSnapshot: Codable {
    let modelLoadMs: Int
    let warmupMs: Int
    let firstPartialMs: Int?
    let partialUpdateIntervalsMs: [Int]
    let partialUpdateMedianMs: Int?
    let releaseToFinalMs: Int
    let inferenceWorkMs: Int
    let realTimeFactor: Double
    let maximumFeedLagMs: Int
}

struct AccuracySnapshot: Codable {
    let referenceText: String
    let hypothesisText: String
    let referenceWordCount: Int
    let hypothesisWordCount: Int
    let substitutions: Int
    let insertions: Int
    let deletions: Int
    let wordErrors: Int
    let wordErrorRate: Double
    let referenceCharacterCount: Int
    let hypothesisCharacterCount: Int
    let characterErrors: Int
    let characterErrorRate: Double
}

struct ResourceSnapshot: Codable {
    let userCpuMs: Int
    let systemCpuMs: Int
    let peakResidentBytes: Int64
}

struct TargetSnapshot: Codable {
    let firstPartialUnder500Ms: Bool?
    let partialMedianBetween200And400Ms: Bool?
    let releaseToFinalUnder700Ms: Bool
    let fullyOffline: Bool
}

struct ResourceUsage {
    let userSeconds: Double
    let systemSeconds: Double
    let peakResidentBytes: Int64

    static func current() -> ResourceUsage {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return ResourceUsage(
            userSeconds: seconds(usage.ru_utime),
            systemSeconds: seconds(usage.ru_stime),
            peakResidentBytes: Int64(usage.ru_maxrss)
        )
    }

    func delta(from earlier: ResourceUsage) -> ResourceSnapshot {
        ResourceSnapshot(
            userCpuMs: milliseconds(userSeconds - earlier.userSeconds),
            systemCpuMs: milliseconds(systemSeconds - earlier.systemSeconds),
            peakResidentBytes: peakResidentBytes
        )
    }

    private static func seconds(_ value: timeval) -> Double {
        Double(value.tv_sec) + Double(value.tv_usec) / 1_000_000
    }

    private func milliseconds(_ seconds: Double) -> Int {
        max(0, Int((seconds * 1_000).rounded()))
    }
}

func uptimeNanoseconds() -> UInt64 {
    DispatchTime.now().uptimeNanoseconds
}

func elapsedMilliseconds(from start: UInt64, to end: UInt64 = uptimeNanoseconds()) -> Int {
    guard end >= start else { return 0 }
    return Int((end - start + 999_999) / 1_000_000)
}

private func sysctlString(_ name: String) -> String? {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
        return nil
    }
    var value = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
        return nil
    }
    let bytes = value.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}
