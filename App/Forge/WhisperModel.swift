import Foundation
import Network
import Observation
import WhisperKit

/// The Whisper sizes the app offers. Nothing is bundled: the App Store download stays the
/// size it is today and a lifter who never turns offline voice on never pays for a model.
enum WhisperVariant: String, CaseIterable, Identifiable, Sendable {
  case tiny, base, small

  var id: String { rawValue }

  /// The folder name inside `argmaxinc/whisperkit-coreml`.
  var modelName: String {
    switch self {
    case .tiny: return "openai_whisper-tiny"
    case .base: return "openai_whisper-base"
    case .small: return "openai_whisper-small"
    }
  }

  var name: String {
    switch self {
    case .tiny: return String(localized: "Tiny", bundle: L10n.bundle)
    case .base: return String(localized: "Base", bundle: L10n.bundle)
    case .small: return String(localized: "Small", bundle: L10n.bundle)
    }
  }

  /// Rounded download size, stated so the choice is informed rather than a surprise.
  var approximateMB: Int {
    switch self {
    case .tiny: return 80
    case .base: return 150
    case .small: return 480
    }
  }

  /// The honest default per language. English gym commands are a small vocabulary that
  /// `base` handles; Vietnamese is the reason this feature exists and needs `small`.
  static func suggested(for languageCode: String) -> WhisperVariant {
    languageCode.hasPrefix("vi") ? .small : .base
  }
}

/// Owns the on-device Whisper model: where it lives, whether it is there, and the one
/// download path that puts it there. Kept apart from the pipeline so a missing model is a
/// settings problem, never a failure in the middle of a set.
@MainActor
@Observable
final class WhisperModelStore {
  static let shared = WhisperModelStore()

  enum State: Equatable {
    case absent
    case downloading(Double)
    case ready(URL)
    case failed(String)

    var isReady: Bool { if case .ready = self { return true } else { return false } }
    var isBusy: Bool { if case .downloading = self { return true } else { return false } }
  }

  static let enabledKey = "voiceOfflineEngine"
  static let variantKey = "voiceWhisperVariant"

  private(set) var state: State = .absent
  private var task: Task<Void, Never>?

  var variant: WhisperVariant {
    get {
      WhisperVariant(rawValue: UserDefaults.standard.string(forKey: Self.variantKey) ?? "")
        ?? WhisperVariant.suggested(for: L10n.languageCode)
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: Self.variantKey)
      refresh()
    }
  }

  /// Set when the model was unloaded under memory pressure. The lifter's setting is left
  /// alone — the next arm simply uses the OS recognizer, so voice keeps working for the rest
  /// of the workout instead of dying until relaunch.
  private(set) var suppressedThisSession = false

  func suppressForThisSession() {
    suppressedThisSession = true
  }

  /// True only when the lifter asked for offline voice, the model is actually present, and
  /// this session has not already had to drop it. All three matter: an enabled toggle with
  /// no model must never silence voice control.
  var isActive: Bool {
    UserDefaults.standard.bool(forKey: Self.enabledKey) && state.isReady && !suppressedThisSession
  }

  var readyFolder: URL? { if case .ready(let url) = state { return url } else { return nil } }

  private init() {
    refresh()
  }

  /// Application Support, not Documents: a model is a cache the app can re-download, and it
  /// is excluded from backup so it never bloats iCloud.
  static func baseFolder() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("WhisperModels", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var mutable = root
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try? mutable.setResourceValues(values)
    return root
  }

  func folder(for variant: WhisperVariant) -> URL {
    Self.baseFolder()
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml", isDirectory: true)
      .appendingPathComponent(variant.modelName, isDirectory: true)
  }

  /// The three CoreML bundles a Whisper model needs. A half-finished download leaves one or
  /// two behind, and calling that ready is how the first command of a workout fails.
  private static let requiredBundles = ["MelSpectrogram", "AudioEncoder", "TextDecoder"]

  func refresh() {
    if state.isBusy { return }
    let url = folder(for: variant)
    let contents = Set((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? [])
    let complete = Self.requiredBundles.allSatisfy { name in
      contents.contains { $0.hasPrefix(name) && $0.hasSuffix(".mlmodelc") }
    }
    state = complete ? .ready(url) : .absent
  }

  func download() {
    guard !state.isBusy else { return }
    let variant = self.variant
    state = .downloading(0)
    task = Task { [weak self] in
      if await Self.isExpensive() {
        self?.state = .failed(String(localized: "Connect to Wi-Fi to download the voice model.", bundle: L10n.bundle))
        return
      }
      do {
        let folder = try await WhisperKit.download(
          variant: variant.modelName,
          downloadBase: Self.baseFolder(),
          useBackgroundSession: false
        ) { progress in
          Task { @MainActor [weak self] in
            guard let self, self.state.isBusy else { return }
            self.state = .downloading(progress.fractionCompleted)
          }
        }
        await MainActor.run { self?.state = .ready(folder) }
      } catch {
        await MainActor.run {
          self?.state = .failed(String(localized: "The voice model didn't download. Try again.", bundle: L10n.bundle))
        }
      }
    }
  }

  func cancel() {
    task?.cancel()
    task = nil
    refresh()
  }

  func delete() {
    cancel()
    try? FileManager.default.removeItem(at: folder(for: variant))
    UserDefaults.standard.set(false, forKey: Self.enabledKey)
    refresh()
  }

  /// Cellular and personal hotspots are "expensive"; a 150–480 MB model is not something to
  /// pull over one without being asked. This is a check at the start, not a guarantee for
  /// the whole transfer: a network that flips to cellular mid-download is not interrupted.
  private static func isExpensive() async -> Bool {
    let monitor = NWPathMonitor()
    let queue = DispatchQueue(label: "whisper.path")
    let paths = AsyncStream<NWPath> { continuation in
      monitor.pathUpdateHandler = { continuation.yield($0) }
      continuation.onTermination = { _ in monitor.cancel() }
      monitor.start(queue: queue)
    }
    for await path in paths {
      monitor.cancel()
      return path.isExpensive || path.isConstrained
    }
    return false
  }
}
