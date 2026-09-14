import HealthKit

enum Health {
  private static let store = HKHealthStore()

  static func requestAuthorization() async {
    guard HKHealthStore.isHealthDataAvailable(), let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return }
    let reads: Set<HKObjectType> = [sleep,
      HKQuantityType(.heartRateVariabilitySDNN),
      HKQuantityType(.restingHeartRate),
      HKQuantityType(.heartRate)]
    try? await store.requestAuthorization(toShare: [HKObjectType.workoutType()], read: reads)
  }

  static func lastNightSleepHours() async -> Double? {
    guard HKHealthStore.isHealthDataAvailable(),
          let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
    let cal = Calendar.current
    guard let yesterday = cal.date(byAdding: .day, value: -1, to: .now),
          let start = cal.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday),
          let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: .now) else { return nil }
    let predicate = HKQuery.predicateForSamples(withStart: start, end: min(noon, .now))
    let asleep: Set<HKCategoryValueSleepAnalysis> = [.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM]
    return await withCheckedContinuation { cont in
      let query = HKSampleQuery(sampleType: sleep, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
        let hours = (samples as? [HKCategorySample] ?? []).reduce(0.0) { total, s in
          guard let v = HKCategoryValueSleepAnalysis(rawValue: s.value), asleep.contains(v) else { return total }
          return total + s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        cont.resume(returning: hours > 0 ? hours : nil)
      }
      store.execute(query)
    }
  }

  static func averageSleepHours(nights: Int = 7) async -> Double? {
    guard HKHealthStore.isHealthDataAvailable(),
          let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return nil }
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)
    guard let firstDay = cal.date(byAdding: .day, value: -(nights - 1), to: today),
          let end = cal.date(byAdding: .day, value: 1, to: today) else { return nil }
    let predicate = HKQuery.predicateForSamples(withStart: firstDay, end: end)
    let asleep: Set<HKCategoryValueSleepAnalysis> = [.asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM]
    return await withCheckedContinuation { cont in
      let query = HKSampleQuery(sampleType: sleep, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
        var perNight: [Date: Double] = [:]
        for s in (samples as? [HKCategorySample] ?? []) {
          guard let v = HKCategoryValueSleepAnalysis(rawValue: s.value), asleep.contains(v) else { continue }
          perNight[cal.startOfDay(for: s.endDate), default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        let withData = perNight.values.filter { $0 > 0 }
        cont.resume(returning: withData.isEmpty ? nil : withData.reduce(0, +) / Double(withData.count))
      }
      store.execute(query)
    }
  }

  static func nightlyAverage(_ id: HKQuantityTypeIdentifier, unit: HKUnit, nights: Int) async -> [Double] {
    guard HKHealthStore.isHealthDataAvailable() else { return [] }
    let cal = Calendar.current
    let today = cal.startOfDay(for: .now)
    guard let start = cal.date(byAdding: .day, value: -(nights - 1), to: today) else { return [] }
    let predicate = HKQuery.predicateForSamples(withStart: start, end: .now)
    return await withCheckedContinuation { cont in
      let query = HKSampleQuery(sampleType: HKQuantityType(id), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
        var perDay: [Date: [Double]] = [:]
        for s in (samples as? [HKQuantitySample]) ?? [] {
          perDay[cal.startOfDay(for: s.endDate), default: []].append(s.quantity.doubleValue(for: unit))
        }
        cont.resume(returning: perDay.sorted { $0.key < $1.key }.map { $0.value.reduce(0, +) / Double($0.value.count) })
      }
      store.execute(query)
    }
  }

  static func cardioSignals() async -> (hrv: Double?, hrvBaseline: Double?, rhr: Double?, rhrBaseline: Double?) {
    func lastAndBaseline(_ days: [Double]) -> (Double?, Double?) {
      guard let last = days.last else { return (nil, nil) }
      let prev = days.dropLast().suffix(7)
      return (last, prev.isEmpty ? nil : prev.reduce(0, +) / Double(prev.count))
    }
    let hrv = await nightlyAverage(.heartRateVariabilitySDNN, unit: .secondUnit(with: .milli), nights: 8)
    let rhr = await nightlyAverage(.restingHeartRate, unit: HKUnit.count().unitDivided(by: .minute()), nights: 8)
    return (hrv: lastAndBaseline(hrv).0, hrvBaseline: lastAndBaseline(hrv).1, rhr: lastAndBaseline(rhr).0, rhrBaseline: lastAndBaseline(rhr).1)
  }

  static func saveWorkout(start: Date, end: Date) async {
    guard HKHealthStore.isHealthDataAvailable() else { return }
    let config = HKWorkoutConfiguration()
    config.activityType = .traditionalStrengthTraining
    let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())
    do {
      try await builder.beginCollection(at: start)
      try await builder.endCollection(at: end)
      _ = try await builder.finishWorkout()
    } catch {}
  }
}
