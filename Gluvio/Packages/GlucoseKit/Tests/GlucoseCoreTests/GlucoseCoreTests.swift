import XCTest
@testable import GlucoseCore

final class UnitTests: XCTestCase {
    func testConversionRoundTrips() {
        for mgdL in stride(from: 20.0, through: 600, by: 7) {
            XCTAssertEqual(GlucoseUnit.mmolL.mgdL(from: GlucoseUnit.mmolL.value(fromMgdL: mgdL)), mgdL, accuracy: 1e-9)
        }
    }

    func testFormatting() {
        XCTAssertEqual(GlucoseUnit.mgdL.format(142.4), "142")
        XCTAssertEqual(GlucoseUnit.mmolL.format(180), "10.0")
        XCTAssertEqual(GlucoseUnit.mmolL.format(70), "3.9")
        XCTAssertEqual(GlucoseUnit.mgdL.formatDelta(45.2), "+45")
        XCTAssertEqual(GlucoseUnit.mgdL.formatDelta(-12), "-12")
        XCTAssertEqual(GlucoseUnit.mgdL.formatWithUnit(99), "99 mg/dL")
    }
}

final class RangeTests: XCTestCase {
    let range = TargetRange.standard

    func testBandBoundaries() {
        XCTAssertEqual(range.band(for: 53.9), .urgentLow)
        XCTAssertEqual(range.band(for: 54), .low)
        XCTAssertEqual(range.band(for: 69.9), .low)
        XCTAssertEqual(range.band(for: 70), .inRange)
        XCTAssertEqual(range.band(for: 180), .inRange)
        XCTAssertEqual(range.band(for: 180.1), .high)
        XCTAssertEqual(range.band(for: 250), .high)
        XCTAssertEqual(range.band(for: 250.1), .urgentHigh)
    }

    func testValidity() {
        XCTAssertTrue(range.isValid)
        XCTAssertFalse(TargetRange(low: 180, high: 70).isValid)
        XCTAssertFalse(TargetRange(low: 70, high: 180, urgentLow: 80).isValid)
    }
}

final class StatsTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func cgm(_ values: [Double], every minutes: Double = 5) -> [GlucoseSample] {
        values.enumerated().map { i, v in
            GlucoseSample(date: start.addingTimeInterval(Double(i) * minutes * 60), mgdL: v, source: .cgm)
        }
    }

    func testBandFractionsAndMean() {
        let samples = cgm([60, 100, 120, 200, 260])
        let stats = GlucoseAnalytics.stats(for: samples, in: DateInterval(start: start, duration: 3600), targets: .standard)
        XCTAssertEqual(stats.readingCount, 5)
        XCTAssertEqual(stats.mean!, 148, accuracy: 1e-9)
        XCTAssertEqual(stats.inRangeFraction!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(stats.belowRangeFraction!, 0.2, accuracy: 1e-9)
        XCTAssertEqual(stats.aboveRangeFraction!, 0.4, accuracy: 1e-9)
        XCTAssertEqual(stats.bandFractions[.urgentHigh]!, 0.2, accuracy: 1e-9)
    }

    func testEmptyPeriod() {
        let stats = GlucoseAnalytics.stats(for: [], in: DateInterval(start: start, duration: 3600), targets: .standard)
        XCTAssertNil(stats.mean)
        XCTAssertNil(stats.inRangeFraction)
        XCTAssertEqual(stats.lowEpisodes, 0)
    }

    func testLowEpisodesGroupConsecutiveReadings() {
        // Two separate dips below 70, the first lasting three readings.
        let samples = cgm([100, 65, 62, 66, 90, 110, 68, 95])
        let stats = GlucoseAnalytics.stats(for: samples, in: DateInterval(start: start, duration: 3600), targets: .standard)
        XCTAssertEqual(stats.lowEpisodes, 2)
        XCTAssertEqual(stats.highEpisodes, 0)
    }

    func testFingerstickLowsCountSeparatelyWhenFarApart() {
        let samples = [0.0, 6, 12].map {
            GlucoseSample(date: start.addingTimeInterval($0 * 3600), mgdL: 65, source: .meter)
        }
        XCTAssertEqual(GlucoseAnalytics.episodes(in: samples) { $0 < 70 }, 3)
    }

    func testCoverageForFiveAndFifteenMinuteSensors() {
        let day = DateInterval(start: start, duration: 86_400)
        let fiveMin = cgm(Array(repeating: 120, count: 288), every: 5)
        let fifteenMin = cgm(Array(repeating: 120, count: 96), every: 15)
        XCTAssertEqual(GlucoseAnalytics.cgmCoverage(fiveMin, in: day), 1, accuracy: 1e-9)
        XCTAssertEqual(GlucoseAnalytics.cgmCoverage(fifteenMin, in: day), 1, accuracy: 1e-9)
        XCTAssertEqual(GlucoseAnalytics.cgmCoverage(Array(fiveMin.prefix(144)), in: day), 0.5, accuracy: 1e-9)
    }

    func testFingerstickDataIsNotLabelledTimeInRange() {
        let meter = (0..<4).map { GlucoseSample(date: start.addingTimeInterval(Double($0) * 4 * 3600), mgdL: 120, source: .meter) }
        let stats = GlucoseAnalytics.stats(for: meter, in: DateInterval(start: start, duration: 86_400), targets: .standard)
        XCTAssertFalse(stats.isContinuous)
        XCTAssertEqual(stats.inRangeLabel, "Readings in range")
    }
}

final class A1CTests: XCTestCase {
    func testPublishedFormulas() {
        // GMI for a mean of 154 mg/dL is 7.0% (Bergenstal et al. 2018).
        XCTAssertEqual(GlucoseAnalytics.gmi(meanMgdL: 154), 6.99, accuracy: 0.01)
        // ADAG: an A1C of 7% corresponds to an average of 154 mg/dL.
        XCTAssertEqual(GlucoseAnalytics.adagA1C(meanMgdL: 154), 7.0, accuracy: 0.01)
    }

    func testUsesGMIWithFourteenDaysOfCGM() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = stride(from: 0.0, to: 14 * 86_400, by: 300).map {
            GlucoseSample(date: now.addingTimeInterval(-$0), mgdL: 154, source: .cgm)
        }
        guard case .gmi(let percent, 14) = GlucoseAnalytics.estimateA1C(from: samples, now: now) else {
            return XCTFail("expected GMI")
        }
        XCTAssertEqual(percent, 6.99, accuracy: 0.01)
    }

    func testRefusesWithTooFewReadings() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<10).map { GlucoseSample(date: now.addingTimeInterval(Double(-$0) * 86_400), mgdL: 140, source: .meter) }
        guard case .notEnoughData = GlucoseAnalytics.estimateA1C(from: samples, now: now) else {
            return XCTFail("expected notEnoughData")
        }
    }

    func testFingerstickEstimateNeedsSpreadOverDays() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<56).map { i in
            GlucoseSample(date: now.addingTimeInterval(Double(-i / 2) * 86_400 - Double(i % 2) * 6 * 3600), mgdL: 154, source: .meter)
        }
        guard case .estimated(let percent, 56) = GlucoseAnalytics.estimateA1C(from: samples, now: now) else {
            return XCTFail("expected ADAG estimate")
        }
        XCTAssertEqual(percent, 7.0, accuracy: 0.01)
    }
}

final class TrendTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func trace(ratePerMinute: Double) -> [GlucoseSample] {
        (0...4).map { i in
            GlucoseSample(date: now.addingTimeInterval(Double(i - 4) * 300), mgdL: 120 + ratePerMinute * Double(i) * 5, source: .cgm)
        }
    }

    func testArrowsMatchStandardRates() {
        XCTAssertEqual(GlucoseAnalytics.trend(from: trace(ratePerMinute: 0.2)), .flat)
        XCTAssertEqual(GlucoseAnalytics.trend(from: trace(ratePerMinute: 1.5)), .risingSlightly)
        XCTAssertEqual(GlucoseAnalytics.trend(from: trace(ratePerMinute: 2.5)), .rising)
        XCTAssertEqual(GlucoseAnalytics.trend(from: trace(ratePerMinute: 3.5)), .risingQuickly)
        XCTAssertEqual(GlucoseAnalytics.trend(from: trace(ratePerMinute: -1.5)), .fallingSlightly)
        XCTAssertEqual(GlucoseAnalytics.trend(from: trace(ratePerMinute: -2.5)), .falling)
        XCTAssertEqual(GlucoseAnalytics.trend(from: trace(ratePerMinute: -4)), .fallingQuickly)
    }

    func testNoArrowForFingersticksOrSparseData() {
        let meter = trace(ratePerMinute: 2).map { GlucoseSample(date: $0.date, mgdL: $0.mgdL, source: .meter) }
        XCTAssertNil(GlucoseAnalytics.trend(from: meter))
        XCTAssertNil(GlucoseAnalytics.trend(from: Array(trace(ratePerMinute: 2).suffix(2))))
    }

    func testStaleness() {
        let reading = GlucoseSample(date: now.addingTimeInterval(-25 * 60), mgdL: 120, source: .cgm)
        XCTAssertTrue(GlucoseAnalytics.isStale(reading, now: now))
        XCTAssertFalse(GlucoseAnalytics.isStale(reading, now: now.addingTimeInterval(-10 * 60)))
        XCTAssertEqual(GlucoseAnalytics.ageDescription(of: reading.date, now: now), "25 min ago")
        XCTAssertEqual(GlucoseAnalytics.ageDescription(of: now.addingTimeInterval(-125 * 60), now: now), "2 h 5 min ago")
    }
}

final class MealTests: XCTestCase {
    let meal = MealEvent(date: Date(timeIntervalSince1970: 1_800_000_000), kind: .lunch, carbsGrams: 60)

    func curve(rise: Double) -> [GlucoseSample] {
        stride(from: -30.0, through: 180, by: 5).map { minute in
            let bump = minute > 0 ? rise * (minute / 50) * exp(1 - minute / 50) : 0
            return GlucoseSample(date: meal.date.addingTimeInterval(minute * 60), mgdL: 110 + bump, source: .cgm)
        }
    }

    func testResponseFindsBaselineAndPeak() throws {
        let response = try XCTUnwrap(GlucoseAnalytics.mealResponse(for: meal, samples: curve(rise: 80), activities: [],
                                                                    now: meal.date.addingTimeInterval(4 * 3600)))
        XCTAssertEqual(response.baseline, 110, accuracy: 1e-9)
        XCTAssertEqual(response.rise, 80, accuracy: 0.5)
        XCTAssertEqual(response.minutesToPeak, 50)
        XCTAssertTrue(response.isHighConfidence)
        XCTAssertTrue(response.isComplete)
        XCTAssertFalse(response.walkedAfter)
    }

    func testWalkDetectionAndInsight() {
        let walk = ActivityEvent(start: meal.date.addingTimeInterval(15 * 60), end: meal.date.addingTimeInterval(35 * 60), kind: .walk)
        let later = meal.date.addingTimeInterval(4 * 3600)
        let walked = GlucoseAnalytics.mealResponse(for: meal, samples: curve(rise: 50), activities: [walk], now: later)!
        let notWalked = GlucoseAnalytics.mealResponse(for: meal, samples: curve(rise: 80), activities: [], now: later)!
        XCTAssertTrue(walked.walkedAfter)
        let insight = GlucoseAnalytics.walkInsight(from: Array(repeating: walked, count: 3) + Array(repeating: notWalked, count: 3))
        XCTAssertEqual(insight?.difference ?? 0, 30, accuracy: 0.5)
        XCTAssertNil(GlucoseAnalytics.walkInsight(from: [walked, notWalked]))
    }

    func testNoResponseWithoutReadings() {
        XCTAssertNil(GlucoseAnalytics.mealResponse(for: meal, samples: [], activities: []))
    }
}

final class SafetyTests: XCTestCase {
    func testUrgentAlertsOnlyBeyondUrgentThresholds() {
        let date = Date()
        XCTAssertEqual(SafetyGuidance.alert(for: GlucoseSample(date: date, mgdL: 50, source: .manual), targets: .standard)?.kind, .low)
        XCTAssertEqual(SafetyGuidance.alert(for: GlucoseSample(date: date, mgdL: 320, source: .manual), targets: .standard)?.kind, .high)
        XCTAssertNil(SafetyGuidance.alert(for: GlucoseSample(date: date, mgdL: 65, source: .manual), targets: .standard))
        XCTAssertNil(SafetyGuidance.alert(for: GlucoseSample(date: date, mgdL: 220, source: .manual), targets: .standard))
    }

    /// The app must never give insulin or medication dosing advice.
    func testNoDosingLanguageInUserFacingCopy() {
        let alertCopy = [UrgentAlert.Kind.low, .high].flatMap {
            UrgentAlert(readingID: UUID(), kind: $0, mgdL: 100, readingDate: Date()).steps
        }
        let copy = SafetyCopy.disclaimerPoints + alertCopy + [SafetyCopy.shortDisclaimer, GuideContent.plateTip, GuideContent.exerciseCaution]
            + GuideContent.swaps.flatMap { [$0.instead, $0.tryThis, $0.why] }
            + GuideContent.exercise.map(\.detail)
        let forbidden = ["dose", "dosage", "units of insulin", "bolus", "inject", "take more", "take less", "skip your"]
        for text in copy {
            for word in forbidden {
                XCTAssertFalse(text.lowercased().contains(word), "“\(word)” found in: \(text)")
            }
        }
    }

    func testConfirmationForUnusualValues() {
        XCTAssertTrue(SafetyGuidance.needsConfirmation(45))
        XCTAssertTrue(SafetyGuidance.needsConfirmation(350))
        XCTAssertFalse(SafetyGuidance.needsConfirmation(120))
        XCTAssertFalse(SafetyGuidance.plausibleRange.contains(700))
    }
}

final class ProfileAndSampleTests: XCTestCase {
    func testProfileDecodesOlderDataWithDefaults() throws {
        let json = #"{"unit":"mmolL","stepGoal":5000}"#.data(using: .utf8)!
        let profile = try JSONDecoder().decode(UserProfile.self, from: json)
        XCTAssertEqual(profile.unit, .mmolL)
        XCTAssertEqual(profile.stepGoal, 5000)
        XCTAssertEqual(profile.targets, .standard)
        XCTAssertFalse(profile.hasAcceptedCurrentDisclaimer)
    }

    func testSampleDataIsDeterministicAndPlausible() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let a = SampleData.make(days: 14, now: now)
        let b = SampleData.make(days: 14, now: now)
        XCTAssertEqual(a.samples.map(\.mgdL), b.samples.map(\.mgdL))
        XCTAssertFalse(a.samples.isEmpty)
        XCTAssertTrue(a.samples.allSatisfy { (40...400).contains($0.mgdL) })
        XCTAssertTrue(a.samples.allSatisfy { $0.date <= now })
        let stats = GlucoseAnalytics.stats(for: a.samples, in: DateInterval(start: now.addingTimeInterval(-14 * 86_400), end: now), targets: .standard)
        XCTAssertGreaterThan(stats.inRangeFraction ?? 0, 0.5)
        XCTAssertGreaterThan(stats.lowEpisodes, 0)
    }

    func testSnapshotMarksStaleCGM() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [GlucoseSample(date: now.addingTimeInterval(-30 * 60), mgdL: 130, source: .cgm)]
        let snapshot = WidgetSnapshot.make(from: samples, profile: UserProfile(), now: now)
        XCTAssertEqual(snapshot.latestMgdL, 130)
        XCTAssertTrue(snapshot.isStale(at: now))
        XCTAssertEqual(snapshot.latestBand, .inRange)
    }
}
