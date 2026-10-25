import Foundation

/// Downloads comic pages ahead of display, in the order `ComicPagePlanner`
/// gives. Mirrors Android's `ComicPageWarmer.kt`.
///
/// Re-planning on every page change keeps in-flight downloads that are still
/// wanted, so scrolling never restarts work; pages already warmed are skipped
/// and failed pages are not retried here (the visible page retries on its own).
/// Urgent pages run with more concurrency than background ones, leaving
/// bandwidth for what is on screen.
@MainActor
final class ComicPageWarmer {
  typealias Load = @MainActor (Int) async throws -> Void

  /// Concurrent downloads while the next pages to read are still missing.
  static let urgentConcurrency = 4
  /// Concurrent background downloads.
  static let backgroundConcurrency = 2

  private let load: Load
  private var queue: [ComicWarmupEntry] = []
  private var active: [Int: (token: UUID, task: Task<Void, Never>)] = [:]
  private var warmed = Set<Int>()
  private var failed = Set<Int>()
  private var isDisposed = false

  init(load: @escaping Load) {
    self.load = load
  }

  func plan(_ entries: [ComicWarmupEntry]) {
    guard !isDisposed else { return }
    let wanted = Set(entries.map(\.index))
    for (index, entry) in active where !wanted.contains(index) {
      entry.task.cancel()
    }
    queue = entries.filter {
      !warmed.contains($0.index) && !failed.contains($0.index) && active[$0.index] == nil
    }
    pump()
  }

  func dispose() {
    isDisposed = true
    queue.removeAll()
    active.values.forEach { $0.task.cancel() }
    active.removeAll()
  }

  private func pump() {
    while !isDisposed, let next = queue.first {
      let limit = next.urgent ? Self.urgentConcurrency : Self.backgroundConcurrency
      guard active.count < limit else { return }
      queue.removeFirst()
      start(next.index)
    }
  }

  private func start(_ index: Int) {
    let token = UUID()
    let load = self.load
    let task = Task { @MainActor [weak self] in
      do {
        try await load(index)
        if !Task.isCancelled { self?.warmed.insert(index) }
      } catch {
        if !Task.isCancelled { self?.failed.insert(index) }
      }
      self?.finish(index, token: token)
    }
    active[index] = (token, task)
  }

  private func finish(_ index: Int, token: UUID) {
    if active[index]?.token == token {
      active[index] = nil
    }
    pump()
  }
}
