import Foundation

/// Pairs comic pages into the spreads double-page mode shows. Mirrors
/// Android's `ComicSpreadLayout.kt` and thorium-web's `comicSpreads.ts`.
///
/// Pairing follows the book, not the page the reader is on, so the same two
/// pages always show together:
/// - A page that is a whole spread on its own (wider than tall, or marked
///   `page: center` in the manifest) shows alone, and pairing restarts after it.
/// - The first page (the cover) shows alone when `coverAlone` is on, unless a
///   wide page later in that first run proves otherwise: a printed spread sits
///   on a left/right pair, so the pages before it must pair evenly.
/// - `shift` flips that first-page choice for books the rules get wrong.
///
/// A server can mark each page `readerSpread: "alone"` or `"pair"` from its own
/// page analysis. With marks, they replace the cover and wide-page rules: a
/// page marked alone shows alone and pairing restarts after it. `shift` still
/// flips the first page.
///
/// Spreads hold page indices in reading order.
struct ComicSpreadLayout {
  let spreads: [[Int]]
  private let spreadIndexByPage: [Int]

  /// A page this much wider than tall is a stored two-page spread.
  private static let widePageMinRatio = 1.0

  static func isStandalone(width: Int?, height: Int?, page: String?) -> Bool {
    if page == "center" { return true }
    guard let width, let height, width > 0, height > 0 else { return false }
    return Double(width) / Double(height) > widePageMinRatio
  }

  init(standalone: [Bool], coverAlone: Bool, shift: Bool, hints: [String?] = []) {
    var standalone = standalone
    let leadAlone: Bool
    if hints.contains(where: { $0 == "alone" || $0 == "pair" }) {
      let firstHintedAlone = !(standalone.first ?? true) && hints.first == "alone"
      for (index, hint) in hints.enumerated() where index < standalone.count && hint == "alone" {
        standalone[index] = true
      }
      if shift && firstHintedAlone {
        standalone[0] = false
        leadAlone = false
      } else {
        leadAlone = shift && !(standalone.first ?? true)
      }
    } else {
      leadAlone = Self.leadsAlone(standalone, coverAlone: coverAlone) != shift
    }
    var spreads: [[Int]] = []
    var pending: Int?
    for (index, isStandalone) in standalone.enumerated() {
      if isStandalone {
        if let waiting = pending { spreads.append([waiting]) }
        pending = nil
        spreads.append([index])
      } else if index == 0 && leadAlone {
        spreads.append([index])
      } else if let waiting = pending {
        spreads.append([waiting, index])
        pending = nil
      } else {
        pending = index
      }
    }
    if let waiting = pending { spreads.append([waiting]) }

    var byPage = Array(repeating: 0, count: standalone.count)
    for (spreadIndex, spread) in spreads.enumerated() {
      for page in spread { byPage[page] = spreadIndex }
    }
    self.spreads = spreads
    self.spreadIndexByPage = byPage
  }

  /// The spread holding `pageIndex`, or a lone page when it is out of range.
  func spread(containing pageIndex: Int) -> [Int] {
    guard spreadIndexByPage.indices.contains(pageIndex) else { return [pageIndex] }
    return spreads[spreadIndexByPage[pageIndex]]
  }

  /// First page of the next spread, or nil at the last one.
  func nextSpreadStart(from pageIndex: Int) -> Int? {
    guard spreadIndexByPage.indices.contains(pageIndex) else { return nil }
    let next = spreadIndexByPage[pageIndex] + 1
    return spreads.indices.contains(next) ? spreads[next].first : nil
  }

  /// First page of the previous spread, or nil at the first one. From the
  /// second page of a spread this is the start of that same spread.
  func previousSpreadStart(from pageIndex: Int) -> Int? {
    guard spreadIndexByPage.indices.contains(pageIndex) else { return nil }
    let spreadIndex = spreadIndexByPage[pageIndex]
    if let first = spreads[spreadIndex].first, first < pageIndex { return first }
    let previous = spreadIndex - 1
    return spreads.indices.contains(previous) ? spreads[previous].first : nil
  }

  private static func leadsAlone(_ standalone: [Bool], coverAlone: Bool) -> Bool {
    guard standalone.count > 1, !standalone[0] else { return false }
    if let firstWide = standalone.firstIndex(of: true), firstWide > 0 {
      return firstWide % 2 == 1
    }
    return coverAlone
  }
}
