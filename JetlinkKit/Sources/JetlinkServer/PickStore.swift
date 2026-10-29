import Foundation
import JetlinkKit
import JetlinkRegistry

/// The big model picked last, wherever it was picked: here (the web page, an
/// app's Use Model, `prepare` on the control channel) or on the comma, whose
/// hello says what it picked and how long ago. The newer pick wins, and the
/// hello's answer carries it, so a comma whose own pick lost takes this one
/// and both ends name the same model.
///
/// Kept beside the cache (`CacheLayout.pickURL`), so a restart remembers it. Each end
/// dates a pick by its own clock and only ages cross the link, so the two
/// clocks never have to agree.
public final class PickStore: @unchecked Sendable {
  public struct Pick: Equatable, Sendable {
    public var sha256: String?
    public var ref: String?
    public var nbytes: Int64?
    public var name: String?
    /// When it was picked, by this machine's clock.
    public var at: TimeInterval
    /// Where: `here`, or `comma`.
    public var by: String

    /// The same model, by its catalog ref where both have one: two refs can
    /// share one export, and the comma names its pick by the ref.
    func sameModel(as other: Pick) -> Bool {
      if let ref, let theirs = other.ref { return ref == theirs }
      if let sha256, let theirs = other.sha256 { return sha256 == theirs }
      return false
    }
  }

  private let url: URL
  private let lock = NSLock()
  private var pick: Pick?
  private let log = ServerLog(category: "server")

  public init(layout: CacheLayout) {
    url = layout.pickURL
    if let data = try? Data(contentsOf: url), let d = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
      let at = (d["at"] as? NSNumber)?.doubleValue
    {
      pick = PickStore.parse(d, at: at, by: (d["by"] as? String) ?? "here")
    }
  }

  public func current() -> Pick? {
    lock.withLock { pick }
  }

  /// A pick made here. Says nothing when it is the model picked already.
  public func pickHere(sha256: String, ref: String?, nbytes: Int64?, name: String?, now: TimeInterval = Date().timeIntervalSince1970) {
    let made = Pick(sha256: sha256, ref: ref, nbytes: nbytes.flatMap { $0 > 0 ? $0 : nil }, name: name, at: now, by: "here")
    lock.withLock {
      if let pick, pick.by == "here", pick.sameModel(as: made) { return }
      pick = made
      save(made)
    }
    log.info("picked here: \(name ?? String(sha256.prefix(16)))")
  }

  /// The pick a comma's hello carries, `{ref, sha256, nbytes, name, age_s}`,
  /// against the one kept here; the newer is kept, and returned for the
  /// hello's answer. A comma with no pick of its own (no `age_s`, it runs
  /// its default) does not compete.
  public func meet(_ hello: [String: Any]?, now: TimeInterval = Date().timeIntervalSince1970) -> Pick? {
    guard let hello, let age = (hello["age_s"] as? NSNumber)?.doubleValue, age.isFinite, age >= 0,
      let theirs = PickStore.parse(hello, at: now - age, by: "comma")
    else { return current() }
    return lock.withLock {
      if let mine = pick, mine.sameModel(as: theirs) || mine.at >= theirs.at { return mine }
      log.info("the comma's pick is newer: \(theirs.name ?? theirs.ref ?? String(theirs.sha256?.prefix(16) ?? "?"))")
      pick = theirs
      save(theirs)
      return theirs
    }
  }

  /// A pick as the hello's answer carries it, with its age by this clock.
  public static func wire(_ pick: Pick?, now: TimeInterval = Date().timeIntervalSince1970) -> Any {
    guard let pick else { return NSNull() }
    return [
      "sha256": pick.sha256 ?? NSNull(), "ref": pick.ref ?? NSNull(), "nbytes": pick.nbytes.map { NSNumber(value: $0) } ?? NSNull(),
      "name": pick.name ?? NSNull(), "age_s": pythonRound(max(0, now - pick.at), 1), "by": pick.by,
    ] as [String: Any]
  }

  /// A pick from a hello or the file: a model identity at least, the rest as far as it is good.
  static func parse(_ d: [String: Any], at: TimeInterval, by: String) -> Pick? {
    let sha256 = (d["sha256"] as? String).flatMap { CacheLayout.isSHA256($0) ? $0 : nil }
    let ref = (d["ref"] as? String).flatMap { CacheLayout.isRef($0) ? $0 : nil }
    guard sha256 != nil || ref != nil else { return nil }
    let nbytes = (d["nbytes"] as? NSNumber).flatMap { $0.int64Value > 0 ? $0.int64Value : nil }
    let name = (d["name"] as? String).flatMap { $0.isEmpty ? nil : String($0.prefix(200)) }
    return Pick(sha256: sha256, ref: ref, nbytes: nbytes, name: name, at: at, by: by)
  }

  /// Hold `lock`.
  private func save(_ pick: Pick) {
    var d: [String: Any] = ["at": pick.at, "by": pick.by]
    d["sha256"] = pick.sha256
    d["ref"] = pick.ref
    d["nbytes"] = pick.nbytes.map { NSNumber(value: $0) }
    d["name"] = pick.name
    do {
      let data = try JSONSerialization.data(withJSONObject: d, options: [.sortedKeys])
      try data.write(to: url, options: .atomic)
    } catch {
      log.warning("could not keep the pick: \(String(describing: error))")
    }
  }
}
