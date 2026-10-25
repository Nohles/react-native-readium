import Foundation

/// One page to download, in the order the warmer should fetch it.
struct ComicWarmupEntry: Equatable {
  let index: Int
  let urgent: Bool
}

/// Which comic pages to download and which to keep decoded, relative to the
/// page being read. Pure index math, mirrored verbatim by Android's
/// `ComicPagePlanner.kt` (which carries the unit tests).
enum ComicPagePlanner {
  /// Pages ahead of the cursor downloaded before background warmup of the rest.
  static let urgentAhead = 3
  /// Upper bound on pages warmed ahead, so whole volumes do not queue thousands.
  static let warmupAheadLimit = 150
  /// Pages warmed behind the cursor once everything ahead is queued.
  static let warmupBehindLimit = 10
  /// Decoded pages kept ahead of the cursor in continuous modes.
  static let decodeAhead = 4
  /// Decoded pages kept behind the cursor in continuous modes.
  static let decodeBehind = 2
  /// Decoded pages kept on each side of the visible page(s) in paginated modes.
  static let paginatedDecodeRadius = 2

  /// Download order: the cursor page and the next `urgentAhead` pages in the
  /// reading direction (urgent), then one page behind, then everything ahead
  /// in reading order, then the remaining pages behind.
  static func warmupOrder(
    pageCount: Int,
    cursor: Int,
    direction: Int,
    urgentAhead: Int = ComicPagePlanner.urgentAhead,
    aheadLimit: Int = ComicPagePlanner.warmupAheadLimit,
    behindLimit: Int = ComicPagePlanner.warmupBehindLimit
  ) -> [ComicWarmupEntry] {
    guard (0..<pageCount).contains(cursor) else { return [] }
    let step = direction < 0 ? -1 : 1
    func page(at offset: Int) -> Int? {
      let index = cursor + offset * step
      return (0..<pageCount).contains(index) ? index : nil
    }

    var order = [ComicWarmupEntry(index: cursor, urgent: true)]
    let urgentCount = min(max(urgentAhead, 0), aheadLimit)
    if urgentCount > 0 {
      for offset in 1...urgentCount {
        if let index = page(at: offset) { order.append(.init(index: index, urgent: true)) }
      }
    }
    if behindLimit > 0, let index = page(at: -1) {
      order.append(.init(index: index, urgent: false))
    }
    if aheadLimit > urgentCount {
      for offset in (urgentCount + 1)...aheadLimit {
        guard let index = page(at: offset) else { break }
        order.append(.init(index: index, urgent: false))
      }
    }
    if behindLimit >= 2 {
      for offset in 2...behindLimit {
        guard let index = page(at: -offset) else { break }
        order.append(.init(index: index, urgent: false))
      }
    }
    return order
  }

  /// Pages that should hold a decoded image. Everything else is released, so a
  /// long webtoon keeps a bounded number of bitmaps alive.
  static func decodeWindow(
    pageCount: Int,
    cursor: Int,
    direction: Int,
    paginated: Bool,
    doublePage: Bool
  ) -> Set<Int> {
    guard (0..<pageCount).contains(cursor) else { return [] }
    let behind: Int
    let ahead: Int
    if paginated {
      // A spread shows two pages, so keep the next spread decoded as well.
      let radius = paginatedDecodeRadius * (doublePage ? 2 : 1)
      behind = radius
      ahead = radius + (doublePage ? 1 : 0)
    } else if direction < 0 {
      behind = decodeAhead
      ahead = decodeBehind
    } else {
      behind = decodeBehind
      ahead = decodeAhead
    }
    let first = max(cursor - behind, 0)
    let last = min(cursor + ahead, pageCount - 1)
    return Set(first...last)
  }
}
