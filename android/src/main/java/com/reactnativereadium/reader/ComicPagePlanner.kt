package com.reactnativereadium.reader

import kotlin.math.max
import kotlin.math.min

/** One page to download, in the order the warmer should fetch it. */
internal data class ComicWarmupEntry(val index: Int, val urgent: Boolean)

/**
 * Which comic pages to download and which to keep decoded, relative to the page
 * being read. Pure index math so it is shared verbatim with iOS
 * (`ComicPagePlanner.swift`) and unit-tested.
 */
internal object ComicPagePlanner {
  /** Pages ahead of the cursor downloaded before background warmup of the rest. */
  const val URGENT_AHEAD = 3

  /** Upper bound on pages warmed ahead, so whole volumes do not queue thousands. */
  const val WARMUP_AHEAD_LIMIT = 150

  /** Pages warmed behind the cursor once everything ahead is queued. */
  const val WARMUP_BEHIND_LIMIT = 10

  /** Decoded pages kept ahead of the cursor in continuous modes. */
  const val DECODE_AHEAD = 4

  /** Decoded pages kept behind the cursor in continuous modes. */
  const val DECODE_BEHIND = 2

  /** Decoded pages kept on each side of the visible page(s) in paginated modes. */
  const val PAGINATED_DECODE_RADIUS = 2

  /**
   * Download order: the cursor page and the next [URGENT_AHEAD] pages in the
   * reading direction (urgent), then one page behind, then everything ahead in
   * reading order, then the remaining pages behind.
   */
  fun warmupOrder(
    pageCount: Int,
    cursor: Int,
    direction: Int,
    urgentAhead: Int = URGENT_AHEAD,
    aheadLimit: Int = WARMUP_AHEAD_LIMIT,
    behindLimit: Int = WARMUP_BEHIND_LIMIT
  ): List<ComicWarmupEntry> {
    if (cursor !in 0 until pageCount) return emptyList()
    val step = if (direction < 0) -1 else 1
    val order = mutableListOf(ComicWarmupEntry(cursor, urgent = true))
    fun pageAt(offset: Int): Int? = (cursor + offset * step).takeIf { it in 0 until pageCount }

    val urgentCount = min(max(urgentAhead, 0), aheadLimit)
    for (offset in 1..urgentCount) {
      pageAt(offset)?.let { order += ComicWarmupEntry(it, urgent = true) }
    }
    if (behindLimit > 0) {
      pageAt(-1)?.let { order += ComicWarmupEntry(it, urgent = false) }
    }
    for (offset in urgentCount + 1..aheadLimit) {
      val index = pageAt(offset) ?: break
      order += ComicWarmupEntry(index, urgent = false)
    }
    for (offset in 2..behindLimit) {
      val index = pageAt(-offset) ?: break
      order += ComicWarmupEntry(index, urgent = false)
    }
    return order
  }

  /**
   * Pages that should hold a decoded bitmap. Everything else is released, so a
   * long webtoon keeps a bounded number of bitmaps alive.
   */
  fun decodeWindow(
    pageCount: Int,
    cursor: Int,
    direction: Int,
    paginated: Boolean,
    doublePage: Boolean
  ): Set<Int> {
    if (cursor !in 0 until pageCount) return emptySet()
    val (behind, ahead) = if (paginated) {
      // A spread shows two pages, so keep the next spread decoded as well.
      val radius = PAGINATED_DECODE_RADIUS * (if (doublePage) 2 else 1)
      radius to radius + (if (doublePage) 1 else 0)
    } else if (direction < 0) {
      DECODE_AHEAD to DECODE_BEHIND
    } else {
      DECODE_BEHIND to DECODE_AHEAD
    }
    val first = max(cursor - behind, 0)
    val last = min(cursor + ahead, pageCount - 1)
    return (first..last).toSet()
  }
}
