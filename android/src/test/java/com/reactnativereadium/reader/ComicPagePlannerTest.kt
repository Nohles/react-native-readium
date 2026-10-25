package com.reactnativereadium.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ComicPagePlannerTest {

  private fun summarize(order: List<ComicWarmupEntry>) =
    order.map { "${it.index}${if (it.urgent) "!" else ""}" }

  @Test
  fun downloadsNextPagesUrgentlyThenOneBehindThenTheRest() {
    assertEquals(
      listOf("3!", "4!", "5!", "2", "6", "7", "8", "9", "1", "0"),
      summarize(ComicPagePlanner.warmupOrder(pageCount = 10, cursor = 3, direction = 1, urgentAhead = 2))
    )
  }

  @Test
  fun followsTheReadingDirectionWhenScrollingBackward() {
    assertEquals(
      listOf("6!", "5!", "7", "4", "3", "2", "1", "0", "8"),
      summarize(
        ComicPagePlanner.warmupOrder(
          pageCount = 10,
          cursor = 6,
          direction = -1,
          urgentAhead = 1,
          behindLimit = 2
        )
      )
    )
  }

  @Test
  fun boundsHowFarAheadItWarms() {
    assertEquals(
      listOf("0!", "1!", "2!", "3!", "4"),
      summarize(
        ComicPagePlanner.warmupOrder(
          pageCount = 10,
          cursor = 0,
          direction = 1,
          urgentAhead = 3,
          aheadLimit = 4,
          behindLimit = 1
        )
      )
    )
  }

  @Test
  fun returnsNothingForACursorOutsideThePublication() {
    assertTrue(ComicPagePlanner.warmupOrder(pageCount = 3, cursor = 9, direction = 1).isEmpty())
    assertTrue(
      ComicPagePlanner.decodeWindow(3, 9, 1, paginated = false, doublePage = false).isEmpty()
    )
  }

  @Test
  fun keepsMorePagesDecodedAheadThanBehind() {
    assertEquals(
      (8..14).toSet(),
      ComicPagePlanner.decodeWindow(30, 10, 1, paginated = false, doublePage = false)
    )
    assertEquals(
      (6..12).toSet(),
      ComicPagePlanner.decodeWindow(30, 10, -1, paginated = false, doublePage = false)
    )
  }

  @Test
  fun keepsNeighbouringPagesAndSpreadsDecodedWhenPaginated() {
    assertEquals(
      (8..12).toSet(),
      ComicPagePlanner.decodeWindow(30, 10, 1, paginated = true, doublePage = false)
    )
    assertEquals(
      (6..15).toSet(),
      ComicPagePlanner.decodeWindow(30, 10, 1, paginated = true, doublePage = true)
    )
    assertEquals(
      (0..2).toSet(),
      ComicPagePlanner.decodeWindow(3, 0, 1, paginated = true, doublePage = false)
    )
  }
}
