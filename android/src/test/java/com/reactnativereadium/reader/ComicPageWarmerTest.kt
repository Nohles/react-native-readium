package com.reactnativereadium.reader

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ComicPageWarmerTest {

  private class Harness(scope: CoroutineScope) {
    val started = LinkedHashMap<Int, CompletableDeferred<Unit>>()
    val cancelled = mutableSetOf<Int>()
    val warmer = ComicPageWarmer(scope) { index ->
      val gate = CompletableDeferred<Unit>()
      started[index] = gate
      try {
        gate.await()
      } catch (error: kotlinx.coroutines.CancellationException) {
        cancelled += index
        throw error
      }
    }
  }

  private fun entries(vararg indices: Int, urgentCount: Int = 0) =
    indices.mapIndexed { position, index -> ComicWarmupEntry(index, position < urgentCount) }

  private suspend fun settle() = repeat(10) { yield() }

  @Test
  fun runsUrgentPagesWithMoreConcurrencyThanBackgroundPages() = runBlocking {
    val urgent = Harness(this)
    urgent.warmer.plan(entries(0, 1, 2, 3, 4, 5, 6, 7, urgentCount = 6))
    settle()
    assertEquals(ComicPageWarmer.URGENT_CONCURRENCY, urgent.started.size)

    val background = Harness(this)
    background.warmer.plan(entries(0, 1, 2, 3, 4, 5))
    settle()
    assertEquals(ComicPageWarmer.BACKGROUND_CONCURRENCY, background.started.size)

    urgent.warmer.dispose()
    background.warmer.dispose()
  }

  @Test
  fun continuesInOrderAndSkipsWarmedPagesOnReplan() = runBlocking {
    val harness = Harness(this)
    harness.warmer.plan(entries(0, 1, 2))
    settle()
    assertEquals(listOf(0, 1), harness.started.keys.toList())

    harness.started.getValue(0).complete(Unit)
    settle()
    assertEquals(listOf(0, 1, 2), harness.started.keys.toList())

    harness.started.clear()
    harness.warmer.plan(entries(0, 1, 2, 3))
    settle()
    // 0 is warmed; 1 and 2 are still running, so only 3 is new.
    assertTrue(harness.started.keys.none { it == 0 || it == 1 || it == 2 })
    harness.warmer.dispose()
  }

  @Test
  fun cancelsPagesThatAreNoLongerWanted() = runBlocking {
    val harness = Harness(this)
    harness.warmer.plan(entries(0, 1))
    settle()

    harness.warmer.plan(entries(1, 2))
    settle()

    assertEquals(setOf(0), harness.cancelled)
    assertTrue(2 in harness.started)
    harness.warmer.dispose()
    settle()
    assertTrue(harness.cancelled.containsAll(listOf(1, 2)))
  }

  @Test
  fun doesNotRetryFailedPages() = runBlocking {
    val harness = Harness(this)
    harness.warmer.plan(entries(5))
    settle()
    harness.started.getValue(5).completeExceptionally(IllegalStateException("404"))
    settle()
    harness.started.clear()

    harness.warmer.plan(entries(5, 6))
    settle()

    assertEquals(listOf(6), harness.started.keys.toList())
    harness.warmer.dispose()
  }
}
