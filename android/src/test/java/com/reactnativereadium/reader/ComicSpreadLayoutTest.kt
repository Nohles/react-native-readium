package com.reactnativereadium.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ComicSpreadLayoutTest {

  /** "n" = normal page, "W" = stored two-page spread. */
  private fun spreads(pattern: String, coverAlone: Boolean = true, shift: Boolean = false) =
    ComicSpreadLayout.build(pattern.map { it == 'W' }, coverAlone, shift).spreads

  @Test
  fun standaloneDetection() {
    assertTrue(ComicSpreadLayout.isStandalone(1400, 1000, null))
    assertFalse(ComicSpreadLayout.isStandalone(700, 1000, null))
    assertFalse(ComicSpreadLayout.isStandalone(1000, 1000, null))
    assertFalse(ComicSpreadLayout.isStandalone(null, null, null))
    assertTrue(ComicSpreadLayout.isStandalone(null, null, "center"))
  }

  @Test
  fun coverAloneThenPairs() {
    assertEquals(listOf(listOf(0), listOf(1, 2), listOf(3, 4)), spreads("nnnnn"))
    assertEquals(listOf(listOf(0, 1), listOf(2, 3), listOf(4)), spreads("nnnnn", coverAlone = false))
  }

  @Test
  fun shiftFlipsFirstPage() {
    assertEquals(listOf(listOf(0, 1), listOf(2, 3), listOf(4)), spreads("nnnnn", shift = true))
  }

  @Test
  fun widePageStandsAloneAndRestartsPairing() {
    assertEquals(
      listOf(listOf(0), listOf(1, 2), listOf(3), listOf(4, 5), listOf(6)),
      spreads("nnnWnnn")
    )
  }

  @Test
  fun widePageDecidesTheCover() {
    assertEquals(listOf(listOf(0, 1), listOf(2, 3), listOf(4), listOf(5, 6)), spreads("nnnnWnn"))
  }

  @Test
  fun steps() {
    val layout = ComicSpreadLayout.build("nnnWnn".map { it == 'W' }, coverAlone = true, shift = false)
    // [[0], [1, 2], [3], [4, 5]]
    assertEquals(1, layout.nextSpreadStart(0))
    assertEquals(3, layout.nextSpreadStart(1))
    assertEquals(3, layout.nextSpreadStart(2))
    assertNull(layout.nextSpreadStart(4))
    assertEquals(3, layout.previousSpreadStart(4))
    assertEquals(4, layout.previousSpreadStart(5))
    assertEquals(0, layout.previousSpreadStart(1))
    assertNull(layout.previousSpreadStart(0))
    assertEquals(listOf(4, 5), layout.spreadFor(5))
    assertEquals(listOf(99), layout.spreadFor(99))
  }

  /** "p" = marked pair, "a" = marked alone, "W" = stored two-page spread. */
  private fun hinted(pattern: String, shift: Boolean = false) =
    ComicSpreadLayout.build(
      pattern.map { it == 'W' },
      coverAlone = true,
      shift = shift,
      hints = pattern.map { if (it == 'a') "alone" else if (it == 'p') "pair" else null }
    ).spreads

  @Test
  fun serverMarksReplaceTheCoverRule() {
    assertEquals(listOf(listOf(0, 1), listOf(2, 3)), hinted("pppp"))
  }

  @Test
  fun serverMarksRestartPairingAndKeepWidePagesAlone() {
    assertEquals(listOf(listOf(0), listOf(1, 2), listOf(3), listOf(4, 5)), hinted("appapp"))
    assertEquals(listOf(listOf(0, 1), listOf(2), listOf(3), listOf(4, 5)), hinted("pppWpp"))
  }

  @Test
  fun shiftFlipsAMarkedFirstPage() {
    assertEquals(listOf(listOf(0), listOf(1, 2), listOf(3)), hinted("pppp", shift = true))
    assertEquals(listOf(listOf(0, 1), listOf(2, 3)), hinted("appp", shift = true))
  }
}
