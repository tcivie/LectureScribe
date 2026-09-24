import Foundation

struct StorageConfig: Sendable {
    static var standard: StorageConfig { StorageConfig(customRoot: UserDefaults.standard.string(forKey: Defaults.transcriptsFolder)) }
    var customRoot: String?
    var folderName = "LectureTranscripts"
    var slugLimit = 40
    var fallbackSlug = "lecture"
}

struct PolishConfig: Sendable {
    static let standard = PolishConfig()
    var batchLimit = 4
    var lowPowerBatchLimit = 8
    var spanSeconds = 20.0
    var idleFlushSeconds = 8.0
    var budgetSeconds = 30.0
}

struct EngineConfig: Sendable {
    static let standard = EngineConfig()
    var tickSeconds = 0.1
    var tickToleranceSeconds = 0.05
    var statusEveryTicks = 50
    var levelDecay = 0.8
    var levelEpsilon = 0.01
    var levelSteps = 100.0
    var maxRecoveries = 3
    var noAudioSeconds = 30.0
    var finalizeSeconds = 3.0
    var partialLimit = 220
    var keptLines = 500
    var keptSnippets = 150
    var logEveryFinals = 20
}

struct MeterConfig: Sendable {
    static let standard = MeterConfig()
    var floorDecibels: Float = -50
    var silenceRMS: Float = 1e-7
    var retrySeconds = 60.0
}

struct MergeConfig: Sendable {
    static let standard = MergeConfig()
    var gapSeconds = 1.5
}

enum Clock {
    static let secondsPerMinute = 60.0
    static let centisecondsPerSecond = 100.0
}
