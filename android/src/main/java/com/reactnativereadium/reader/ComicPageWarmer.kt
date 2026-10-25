package com.reactnativereadium.reader

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

/**
 * Downloads comic pages ahead of display, in the order [ComicPagePlanner] gives.
 *
 * Re-planning on every page change keeps in-flight downloads that are still
 * wanted, so scrolling never restarts work; pages already warmed are skipped and
 * failed pages are not retried here (the visible page retries on its own).
 * Urgent pages run with more concurrency than background ones, leaving
 * bandwidth for what is on screen.
 *
 * Not thread-safe: call [plan] and [dispose] from the thread [scope] runs on.
 */
internal class ComicPageWarmer(
  private val scope: CoroutineScope,
  private val load: suspend (index: Int) -> Unit
) {
  private var queue: List<ComicWarmupEntry> = emptyList()
  private val active = HashMap<Int, Job>()
  private val warmed = HashSet<Int>()
  private val failed = HashSet<Int>()
  private var disposed = false

  val activeCount: Int
    get() = active.size

  fun plan(entries: List<ComicWarmupEntry>) {
    if (disposed) return
    val wanted = entries.mapTo(HashSet()) { it.index }
    active.entries.filter { it.key !in wanted }.forEach { it.value.cancel() }
    queue = entries.filter { it.index !in warmed && it.index !in failed && it.index !in active }
    pump()
  }

  fun dispose() {
    disposed = true
    queue = emptyList()
    active.values.forEach { it.cancel() }
    active.clear()
  }

  private fun pump() {
    while (!disposed && queue.isNotEmpty()) {
      val next = queue.first()
      val limit = if (next.urgent) URGENT_CONCURRENCY else BACKGROUND_CONCURRENCY
      if (active.size >= limit) return
      queue = queue.drop(1)
      start(next.index)
    }
  }

  private fun start(index: Int) {
    val job = scope.launch(start = CoroutineStart.LAZY) {
      try {
        load(index)
        warmed += index
      } catch (cancelled: CancellationException) {
        throw cancelled
      } catch (_: Throwable) {
        failed += index
      }
    }
    active[index] = job
    job.invokeOnCompletion {
      // Completion handlers run on the finishing thread; hop back so the
      // bookkeeping stays on the scope's (main) thread.
      scope.launch {
        if (active[index] === job) active.remove(index)
        pump()
      }
    }
    job.start()
  }

  companion object {
    /** Concurrent downloads while the next pages to read are still missing. */
    const val URGENT_CONCURRENCY = 4

    /** Concurrent background downloads. */
    const val BACKGROUND_CONCURRENCY = 2
  }
}
