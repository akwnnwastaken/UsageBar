import XCTest
@testable import UsageBarCore

final class WeeklyHistoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testRecordingKeepsRollingWeekAcrossSeveralWeeks() {
        var samples: [UsageHistorySample] = []
        for hour in 0...(21 * 24) {
            samples = UsageHistoryModel.adding(remainingPercent: hour % 101,
                at: now.addingTimeInterval(Double(hour * 3600)), to: samples, weekly: true)
        }
        XCTAssertEqual(samples.count, 7 * 24 + 1)
        XCTAssertEqual(samples.first?.recordedAt, now.addingTimeInterval(14 * 24 * 3600))
        XCTAssertEqual(samples.last?.recordedAt, now.addingTimeInterval(21 * 24 * 3600))
    }

    func testRetentionBoundaryAndMiniHistoryRemainIndependent() {
        let input = ["Codex|weekly": [
            UsageHistorySample(recordedAt: now.addingTimeInterval(-7 * 86400 - 1), remainingPercent: 80),
            UsageHistorySample(recordedAt: now.addingTimeInterval(-7 * 86400), remainingPercent: 70),
            UsageHistorySample(recordedAt: now.addingTimeInterval(-2 * 86400), remainingPercent: 60),
            UsageHistorySample(recordedAt: now, remainingPercent: 50)
        ]]
        XCTAssertEqual(UsageHistoryModel.sanitized(input, now: now, weekly: true)["Codex|weekly"]?.map(\.remainingPercent), [70, 60, 50])
        XCTAssertEqual(UsageHistoryModel.sanitized(input, now: now)["Codex|weekly"]?.map(\.remainingPercent), [50])
        XCTAssertTrue(UsageHistoryModel.sanitized(input, now: now.addingTimeInterval(8 * 86400), weekly: true).isEmpty)
    }

    func testWeeklyRecordingUsesOnlyAcceptedRawOrdinaryWeeklyMeasurements() {
        let kinds: [UsageWindowKind] = [.fiveHour, .weekly, .weeklyScoped(scope: "opus"), .duration(minutes: 120), .unknown(position: 0)]
        let windows = kinds.map { UsageWindow(kind: $0, usedPercent: 67, resetsAt: nil, durationMinutes: nil) }
        let input = ["Codex": ProviderUsage(name: "Codex", windows: windows, error: nil),
                     "Claude Code": ProviderUsage.unavailable("Claude Code", .claudeUsageUnreadable)]
        let recorded = UsageHistoryRecorder.recording([:], measurements: input, at: now, weekly: true)
        XCTAssertEqual(Array(recorded.keys), ["Codex|weekly"])
        XCTAssertEqual(UsageHistoryRecorder.recording([:], measurements: input, at: now).count, kinds.count)
        let noWeekly = ["Codex": ProviderUsage(name: "Codex", windows: windows.filter { $0.kind != .weekly }, error: nil)]
        XCTAssertTrue(UsageHistoryRecorder.recording([:], measurements: noWeekly, at: now, weekly: true).isEmpty)
        XCTAssertTrue(recorded.values.allSatisfy { $0.map(\.remainingPercent) == [33] })
        XCTAssertEqual(UsageHistoryRecorder.recording(recorded, measurements: [:], at: now.addingTimeInterval(120), weekly: true), recorded)
        let replaced = UsageHistoryRecorder.recording(recorded, measurements: input, at: now.addingTimeInterval(30), weekly: true)
        XCTAssertTrue(replaced.values.allSatisfy { $0.count == 1 && $0.last?.recordedAt == now.addingTimeInterval(30) })
    }

    func testWeeklyChartIncludesEveryResetWhileMiniChartKeepsLatestPeriod() {
        let samples = [33, 34, 33, 20, 100, 60, 10, 95, 80].enumerated().map {
            UsageHistorySample(recordedAt: now.addingTimeInterval(Double($0.offset * 3600)), remainingPercent: $0.element)
        }
        let full = UsageHistoryChartModel(samples: samples, startsAtLatestReset: false)
        XCTAssertEqual(full.samples, samples)
        XCTAssertEqual(full.displaySamples.map(\.remainingPercent), [33, 33, 33, 20, 100, 60, 10, 95, 80])
        XCTAssertEqual(full.lowerBound, 0)
        XCTAssertEqual(full.upperBound, 100)
        XCTAssertEqual(full.recordedDuration, 8 * 3600)
        XCTAssertEqual(full.nearestDisplaySample(toNormalizedX: 0.5)?.remainingPercent, 100)
        XCTAssertEqual(UsageHistoryChartModel(samples: samples).displaySamples.map(\.remainingPercent), [95, 80])
        XCTAssertTrue(UsageHistoryChartModel(samples: [], startsAtLatestReset: false).displaySamples.isEmpty)
    }

    func testFullCapacityWeeklyHistorySurvivesEncodingAndReload() throws {
        let samples = (0..<UsageHistoryModel.weeklyMaximumSamplesPerSeries).map {
            UsageHistorySample(recordedAt: now.addingTimeInterval(Double(-$0 * 60)), remainingPercent: $0 % 101)
        }.reversed()
        let input = Dictionary(uniqueKeysWithValues: (0..<UsageHistoryModel.maximumSeries).map { ("Codex|unknown-\($0)", Array(samples)) })
        let retained = UsageHistoryModel.sanitized(input, now: now, weekly: true)
        let encoded = try XCTUnwrap(UsageHistoryModel.encode(retained))
        XCTAssertLessThanOrEqual(encoded.count, UsageHistoryModel.weeklyMaximumEncodedBytes)
        XCTAssertGreaterThan(encoded.count, UsageHistoryModel.maximumEncodedBytes)
        XCTAssertEqual(UsageHistoryModel.decode(encoded, weekly: true), retained)
        XCTAssertTrue(UsageHistoryModel.decode(encoded).isEmpty)
        XCTAssertTrue(UsageHistoryModel.decode(Data("invalid".utf8), weekly: true).isEmpty)
    }
}
