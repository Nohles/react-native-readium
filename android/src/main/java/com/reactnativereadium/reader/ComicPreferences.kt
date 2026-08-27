package com.reactnativereadium.reader

/**
 * Comic (CBZ/DIVINA) reader preferences, mirroring the keys produced by the
 * shared TypeScript layer (`createComicPreferences` in src/interfaces/Comic.ts)
 * and consumed by the iOS `ComicImageViewController`. Null means "not set";
 * each consumer applies the same default as iOS.
 */
data class ComicPreferences(
  val scroll: Boolean? = null,
  val spread: String? = null,
  val readingMode: String? = null,
  val scaleType: String? = null,
  val readingProgression: String? = null,
  val backgroundColor: String? = null,
  val pageMargins: Double? = null,
  val stretchSmallPages: Boolean? = null,
  val widthLimitEnabled: Boolean? = null,
  val widthLimitPercent: Double? = null,
  val scrollAmountPercent: Double? = null,
  val imagePreloadAmount: Double? = null
)
