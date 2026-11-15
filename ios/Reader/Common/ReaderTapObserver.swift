import CoreGraphics
import Foundation
import ReadiumNavigator

/// Recognizes a single-finger tap on the publication.
///
/// Readium's `.tap` observer waits until every touch it has seen goes up
/// before it recognizes another tap. Touch events come from the web page, and
/// the page can drop a touch's end, for example when it ignores the event or
/// reloads during navigation. After that, no later tap is recognized until
/// the reader is reopened. This observer forgets a touch that has been down
/// longer than `staleAfter`, so the next tap is recognized.
@MainActor
final class ReaderTapObserver: InputObserving {
  private let staleAfter: TimeInterval
  private let slop: CGFloat
  private let now: () -> Date
  private let onTap: @MainActor (PointerEvent) async -> Bool

  /// When each touch currently down started.
  private var activeTouches: [AnyHashable: Date] = [:]
  /// The touch that can still become a tap, and where it started.
  private var candidate: (id: AnyHashable, start: CGPoint)?

  init(
    staleAfter: TimeInterval = 2,
    slop: CGFloat = 10,
    now: @escaping () -> Date = Date.init,
    onTap: @MainActor @escaping (PointerEvent) async -> Bool
  ) {
    self.staleAfter = staleAfter
    self.slop = slop
    self.now = now
    self.onTap = onTap
  }

  func didReceive(_ event: PointerEvent) async -> Bool {
    guard event.pointer.type == .touch else {
      return false
    }
    let id = event.pointer.id

    switch event.phase {
    case .down:
      let time = now()
      activeTouches = activeTouches.filter { time.timeIntervalSince($0.value) < staleAfter }
      // A second finger means this is not a tap.
      candidate = activeTouches.isEmpty && event.modifiers.isEmpty ? (id, event.location) : nil
      activeTouches[id] = time
      return false

    case .move:
      if let candidate, candidate.id == id,
         abs(event.location.x - candidate.start.x) > slop || abs(event.location.y - candidate.start.y) > slop
      {
        self.candidate = nil
      }
      return false

    case .up:
      activeTouches[id] = nil
      guard let candidate, candidate.id == id else {
        return false
      }
      self.candidate = nil
      return await onTap(event)

    case .cancel:
      activeTouches[id] = nil
      if candidate?.id == id {
        candidate = nil
      }
      return false
    }
  }

  func didReceive(_ event: KeyEvent) async -> Bool {
    false
  }
}
