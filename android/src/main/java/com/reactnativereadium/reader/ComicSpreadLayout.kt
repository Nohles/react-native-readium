package com.reactnativereadium.reader

/**
 * Pairs comic pages into the spreads double-page mode shows. Mirrors iOS
 * `ComicSpreadLayout.swift` and thorium-web's `comicSpreads.ts`.
 *
 * Pairing follows the book, not the page the reader is on, so the same two
 * pages always show together:
 * - A page that is a whole spread on its own (wider than tall, or marked
 *   `page: center` in the manifest) shows alone, and pairing restarts after it.
 * - The first page (the cover) shows alone when [coverAlone] is on, unless a
 *   wide page later in that first run proves otherwise: a printed spread sits
 *   on a left/right pair, so the pages before it must pair evenly.
 * - [shift] flips that first-page choice for books the rules get wrong.
 *
 * A server can mark each page `readerSpread: "alone"` or `"pair"` from its own
 * page analysis. With marks, they replace the cover and wide-page rules: a
 * page marked alone shows alone and pairing restarts after it. [shift] still
 * flips the first page.
 *
 * Spreads hold page indices in reading order.
 */
class ComicSpreadLayout private constructor(
  val spreads: List<List<Int>>,
  private val spreadIndexByPage: IntArray
) {

  /** The spread holding [pageIndex], or a lone page when it is out of range. */
  fun spreadFor(pageIndex: Int): List<Int> =
    spreadIndexByPage.getOrNull(pageIndex)?.let { spreads[it] } ?: listOf(pageIndex)

  /** First page of the next spread, or null at the last one. */
  fun nextSpreadStart(pageIndex: Int): Int? {
    val spreadIndex = spreadIndexByPage.getOrNull(pageIndex) ?: return null
    return spreads.getOrNull(spreadIndex + 1)?.first()
  }

  /**
   * First page of the previous spread, or null at the first one. From the
   * second page of a spread this is the start of that same spread.
   */
  fun previousSpreadStart(pageIndex: Int): Int? {
    val spreadIndex = spreadIndexByPage.getOrNull(pageIndex) ?: return null
    val spread = spreads[spreadIndex]
    if (spread.first() < pageIndex) return spread.first()
    return spreads.getOrNull(spreadIndex - 1)?.first()
  }

  companion object {
    /** A page this much wider than tall is a stored two-page spread. */
    private const val WIDE_PAGE_MIN_RATIO = 1.0

    fun isStandalone(width: Int?, height: Int?, page: String?): Boolean {
      if (page == "center") return true
      if (width == null || height == null || width <= 0 || height <= 0) return false
      return width.toDouble() / height.toDouble() > WIDE_PAGE_MIN_RATIO
    }

    fun build(
      pages: List<Boolean>,
      coverAlone: Boolean,
      shift: Boolean,
      hints: List<String?> = emptyList()
    ): ComicSpreadLayout {
      val standalone = pages.toMutableList()
      val leadAlone: Boolean
      if (hints.any { it == "alone" || it == "pair" }) {
        val firstHintedAlone = standalone.firstOrNull() == false && hints.firstOrNull() == "alone"
        hints.forEachIndexed { index, hint ->
          if (index < standalone.size && hint == "alone") standalone[index] = true
        }
        if (shift && firstHintedAlone) {
          standalone[0] = false
          leadAlone = false
        } else {
          leadAlone = shift && standalone.firstOrNull() == false
        }
      } else {
        leadAlone = leadsAlone(standalone, coverAlone) != shift
      }
      val spreads = mutableListOf<List<Int>>()
      var pending: Int? = null
      fun flush() {
        pending?.let { spreads.add(listOf(it)) }
        pending = null
      }
      for ((index, isStandalone) in standalone.withIndex()) {
        when {
          isStandalone -> {
            flush()
            spreads.add(listOf(index))
          }
          index == 0 && leadAlone -> spreads.add(listOf(index))
          pending == null -> pending = index
          else -> {
            spreads.add(listOf(pending!!, index))
            pending = null
          }
        }
      }
      flush()

      val spreadIndexByPage = IntArray(standalone.size)
      spreads.forEachIndexed { spreadIndex, spread ->
        spread.forEach { spreadIndexByPage[it] = spreadIndex }
      }
      return ComicSpreadLayout(spreads, spreadIndexByPage)
    }

    private fun leadsAlone(standalone: List<Boolean>, coverAlone: Boolean): Boolean {
      if (standalone.size <= 1 || standalone[0]) return false
      val firstWide = standalone.indexOfFirst { it }
      if (firstWide > 0) return firstWide % 2 == 1
      return coverAlone
    }
  }
}
