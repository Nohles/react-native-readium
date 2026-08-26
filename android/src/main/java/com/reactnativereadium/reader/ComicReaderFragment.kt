/*
 * Bespoke comic (CBZ/DIVINA) navigator, mirroring the iOS
 * `ComicImageViewController` (ios/Reader/CBZ/ComicImageViewController.swift).
 *
 * Like iOS, this deliberately does NOT use a Readium navigator: it is built on
 * plain scroll views + linear layouts consuming only readium-shared/streamer
 * primitives, so every behavior of the iOS reader (five reading modes, scale
 * types with capping rules, spreads with RTL cover rule, page gap, theme,
 * preload windowing, webtoon %-of-viewport paging, locator contract) is
 * ported 1:1.
 */

package com.reactnativereadium.reader

import android.animation.Animator
import android.animation.AnimatorListenerAdapter
import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.view.Gravity
import android.view.LayoutInflater
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.animation.DecelerateInterpolator
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.ScrollView
import androidx.core.view.children
import androidx.lifecycle.ViewModelProvider
import androidx.lifecycle.lifecycleScope
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.readium.r2.navigator.Navigator
import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.mediatype.MediaType

class ComicReaderFragment : VisualReaderFragment(), Navigator {

  override lateinit var model: ReaderViewModel
  override val navigator: Navigator
    get() = this

  private lateinit var publication: Publication
  private lateinit var factory: ReaderViewModel.Factory

  /** Bitmap-filtered reading order — iOS init :35-36. */
  private lateinit var links: List<Link>
  private lateinit var bitmaps: Array<Bitmap?>
  private lateinit var imageViews: List<ImageView>

  private lateinit var currentLocatorFlow: MutableStateFlow<Locator>
  override val currentLocator: StateFlow<Locator>
    get() = currentLocatorFlow

  private var preferences = ComicPreferences()

  private var currentIndex = 0

  private val loadingIndices = mutableSetOf<Int>()

  // View hierarchy: root > scroll container (ScrollView | HorizontalScrollView)
  // > stack (LinearLayout) > image views.
  private var rootView: FrameLayout? = null
  private var scrollContainer: ViewGroup? = null
  private var stackView: LinearLayout? = null
  private var loadingIndicator: ProgressBar? = null

  private var programmaticScrollAnimator: ValueAnimator? = null
  private var isApplyingProgrammaticScroll = false

  private var touchDownX = 0f
  private var touchDownY = 0f

  private var isLayoutDirty = true
  private var appliedViewportWidth = -1
  private var appliedViewportHeight = -1

  fun initFactory(publication: Publication, initialLocation: Locator?) {
    factory = ReaderViewModel.Factory(publication, initialLocation)
  }

  override fun onCreate(savedInstanceState: Bundle?) {
    check(::factory.isInitialized) { "ComicReaderFragment factory was not initialized" }

    ViewModelProvider(this, factory)
      .get(ReaderViewModel::class.java)
      .let {
        model = it
        publication = it.publication
      }

    val bitmapLinks = publication.readingOrder.filter { it.mediaType?.isBitmap == true }
    links = bitmapLinks.ifEmpty { publication.readingOrder }
    bitmaps = arrayOfNulls(links.size)

    currentIndex = initialIndex()
    currentLocatorFlow = MutableStateFlow(locatorAt(currentIndex))

    setHasOptionsMenu(true)

    super.onCreate(savedInstanceState)
  }

  override fun onCreateView(
    inflater: LayoutInflater,
    container: ViewGroup?,
    savedInstanceState: Bundle?
  ): View? {
    val view = super.onCreateView(inflater, container, savedInstanceState)
    buildViews(binding.fragmentReaderContainer)
    return view
  }

  override fun onViewCreated(view: View, savedInstanceState: Bundle?) {
    super.onViewCreated(view, savedInstanceState)

    rootView?.addOnLayoutChangeListener { _, _, _, _, _, _, _, _, _ ->
      applyLayoutIfNeeded()
    }

    applyTheme()
    rebuildContent()
    loadImagesAround(initialIndex(), hidesLoadingIndicatorOnCompletion = true)
  }

  override fun onDestroyView() {
    programmaticScrollAnimator?.cancel()
    programmaticScrollAnimator = null
    rootView?.removeAllViews()
    rootView = null
    scrollContainer = null
    stackView = null
    loadingIndicator = null
    super.onDestroyView()
  }

  // MARK: - Preferences

  /**
   * Port of iOS `updatePreferences` (:59-70): rebuilds subviews only if the
   * pagination axis changed, re-applies layout, stays on [currentIndex].
   */
  fun updatePreferences(preferences: ComicPreferences) {
    val changedPagination = this.preferences.scroll != preferences.scroll && isContentBuilt
    this.preferences = preferences

    if (!isContentBuilt) return

    applyTheme()
    if (changedPagination) {
      rebuildContent()
    } else {
      invalidateLayout()
    }
    navigateToIndex(currentIndex, animated = false, emit = false)
    loadImagesAround(currentIndex)
  }

  override suspend fun computePositions(): List<Locator> =
    links.indices.map { locatorAt(it) }

  // MARK: - Navigator

  override fun go(locator: Locator, animated: Boolean): Boolean {
    if (links.isEmpty()) return false
    val index = indexFor(locator) ?: currentIndex
    navigateToIndex(index, animated)
    return true
  }

  override fun go(link: Link, animated: Boolean): Boolean {
    val locator = publication.locatorFromLink(link) ?: return false
    return go(locator, animated)
  }

  /** Port of iOS `goForward` (:83-90): webtoon fractional scroll; step 2 in spreads. */
  override fun goForward(): Boolean {
    if (!isContentBuilt || links.isEmpty()) return false
    if (isWebtoonMode) {
      scrollWebtoon(forward = true)
      return true
    }
    val step = if (isDoublePageMode) 2 else 1
    navigateToIndex(min(currentIndex + step, max(links.size - 1, 0)), animated = true)
    return true
  }

  override fun goBackward(): Boolean {
    if (!isContentBuilt || links.isEmpty()) return false
    if (isWebtoonMode) {
      scrollWebtoon(forward = false)
      return true
    }
    val step = if (isDoublePageMode) 2 else 1
    navigateToIndex(max(currentIndex - step, 0), animated = true)
    return true
  }

  // MARK: - Mode predicates (iOS :358-376)

  private val isPaginatedMode: Boolean
    get() = preferences.scroll != true

  private val isDoublePageMode: Boolean
    get() = preferences.spread == "always"

  private val isHorizontalScrollMode: Boolean
    get() = preferences.readingMode == "continuousHorizontal"

  private val isWebtoonMode: Boolean
    get() = preferences.readingMode == "webtoon"

  private val pageTurnThresholdPx: Float
    get() = 48f * resources.displayMetrics.density

  private val isRTL: Boolean
    get() = preferences.readingProgression == "rtl"

  /** Spread halves shown for the current page — iOS `visiblePageIndices` :378-387. */
  private val visiblePageIndices: List<Int>
    get() {
      if (links.isEmpty()) return emptyList()
      if (!isDoublePageMode) return listOf(currentIndex)
      if (isRTL) {
        return if (currentIndex > 0) listOf(currentIndex, currentIndex - 1) else listOf(currentIndex)
      }
      return if (currentIndex + 1 < imageViews.size) {
        listOf(currentIndex, currentIndex + 1)
      } else {
        listOf(currentIndex)
      }
    }

  /** Page gap in dp — iOS `gap` :389-391 (`pageMargins * 16`). */
  private val gap: Double
    get() = max(preferences.pageMargins ?: 0.0, 0.0) * 16.0

  /** [gap] converted to screen pixels. */
  private val gapPx: Int
    get() = (gap * resources.displayMetrics.density).roundToInt()

  /** Preload amount clamped 0-10, default 5 — iOS :393-395. */
  private val preloadAmount: Int
    get() = ((preferences.imagePreloadAmount ?: 5.0).toInt()).coerceIn(0, 10)

  /** Webtoon paging % of viewport height, clamped 10-100, default 95 — iOS :454. */
  private val scrollAmountPercent: Double
    get() = preferences.scrollAmountPercent ?: 95.0

  // MARK: - View building

  private fun buildViews(parent: ViewGroup) {
    val context = parent.context

    imageViews = links.mapIndexed { index, _ ->
      ImageView(context).apply {
        tag = index
        scaleType = ImageView.ScaleType.FIT_CENTER
        setBackgroundColor(readerBackgroundColor())
      }
    }

    val root = FrameLayout(context).apply {
      layoutParams = ViewGroup.LayoutParams(
        ViewGroup.LayoutParams.MATCH_PARENT,
        ViewGroup.LayoutParams.MATCH_PARENT
      )
    }
    root.setBackgroundColor(readerBackgroundColor())

    val indicator = ProgressBar(context).apply {
      isIndeterminate = true
      layoutParams = FrameLayout.LayoutParams(
        ViewGroup.LayoutParams.WRAP_CONTENT,
        ViewGroup.LayoutParams.WRAP_CONTENT,
        Gravity.CENTER
      )
    }
    root.addView(indicator)
    loadingIndicator = indicator

    parent.addView(root)
    rootView = root
  }

  private val isContentBuilt: Boolean
    get() = scrollContainer != null && stackView != null

  /**
   * Rebuilds the scroll container for the current mode — the Android
   * counterpart of the layout switch in `applyLayoutForCurrentPreferences`
   * plus `rebuildArrangedSubviews` (iOS :224-261, :191-207):
   *
   * - paginated: one screenful, only the visible page(s) attached, no scrolling
   *   (stack pinned to both axes; content offset always zero)
   * - continuousHorizontal: horizontal scroll view, pages side by side at full height
   * - continuousVertical / webtoon: vertical scroll view, pages stacked at full width
   */
  @SuppressLint("ClickableViewAccessibility")
  private fun rebuildContent() {
    val root = rootView ?: return
    val context = root.context

    programmaticScrollAnimator?.cancel()
    programmaticScrollAnimator = null
    isApplyingProgrammaticScroll = false

    scrollContainer?.let { root.removeView(it) }

    val paginated = isPaginatedMode
    val horizontalAxis = isPaginatedMode || isHorizontalScrollMode

    val scrollView: ViewGroup =
      if (horizontalAxis) HorizontalScrollView(context) else ScrollView(context)
    scrollView.layoutParams = ViewGroup.LayoutParams(
      ViewGroup.LayoutParams.MATCH_PARENT,
      ViewGroup.LayoutParams.MATCH_PARENT
    )
    // Scroll physics port (iOS applyScrollAxisPolicy :462-484): no bounce when
    // paginated; directional bounce + indicators in continuous modes.
    scrollView.overScrollMode =
      if (paginated) View.OVER_SCROLL_NEVER else View.OVER_SCROLL_ALWAYS
    scrollView.isVerticalScrollBarEnabled = !paginated && !isHorizontalScrollMode
    scrollView.isHorizontalScrollBarEnabled = !paginated && isHorizontalScrollMode
    if (scrollView is ScrollView) {
      scrollView.isFillViewport = paginated
    }

    val stack = LinearLayout(context)
    stack.orientation = if (horizontalAxis) LinearLayout.HORIZONTAL else LinearLayout.VERTICAL
    stack.gravity = Gravity.CENTER
    if (horizontalAxis) {
      // Reading direction as a preference (iOS isRTL :374-376): an RTL
      // publication lays horizontal pages right-to-left, so an RTL spread's
      // [current, previous] pair mirrors the iOS trait-collection behavior.
      stack.layoutDirection =
        if (isRTL) View.LAYOUT_DIRECTION_RTL else View.LAYOUT_DIRECTION_LTR
    }
    scrollView.addView(
      stack,
      when {
        paginated -> ViewGroup.LayoutParams(
          ViewGroup.LayoutParams.MATCH_PARENT,
          ViewGroup.LayoutParams.MATCH_PARENT
        )
        isHorizontalScrollMode -> ViewGroup.LayoutParams(
          ViewGroup.LayoutParams.WRAP_CONTENT,
          ViewGroup.LayoutParams.MATCH_PARENT
        )
        else -> ViewGroup.LayoutParams(
          ViewGroup.LayoutParams.MATCH_PARENT,
          ViewGroup.LayoutParams.WRAP_CONTENT
        )
      }
    )

    val attachedIndices = if (paginated) visiblePageIndices else links.indices.toList()
    attachedIndices.forEach { index ->
      imageViews.getOrNull(index)?.let { imageView ->
        // A preference update can rebuild the container without recreating
        // the page views. Detach each page from the previous stack before
        // moving it into the new one.
        (imageView.parent as? ViewGroup)?.removeView(imageView)
        stack.addView(imageView)
      }
    }

    root.addView(scrollView, 0)

    scrollContainer = scrollView
    stackView = stack

    scrollView.setOnScrollChangeListener { _, _, _, _, _ ->
      updateCurrentIndexFromScrollPosition()
    }
    // Mirror of iOS scrollViewWillBeginDragging (:535-537): a user *drag* takes
    // over from an in-flight programmatic scroll; a mere tap does not.
    scrollView.setOnTouchListener { v, event ->
      if (isPaginatedMode) {
        when (event.actionMasked) {
          MotionEvent.ACTION_DOWN -> {
            touchDownX = event.x
            touchDownY = event.y
          }

          MotionEvent.ACTION_UP -> {
            val deltaX = event.x - touchDownX
            val deltaY = event.y - touchDownY
            val isHorizontalSwipe =
              abs(deltaX) >= pageTurnThresholdPx && abs(deltaX) > abs(deltaY)

            if (isHorizontalSwipe) {
              // A left swipe advances an LTR publication; RTL reverses the
              // physical direction while keeping the reading order semantic.
              val goesForward = if (isRTL) deltaX > 0 else deltaX < 0
              if (goesForward) goForward() else goBackward()
            }

            v.performClick()
          }
        }

        // Paginated mode attaches only the current page, so the scroll view has
        // no native horizontal movement to handle. Consume the gesture here
        // and turn horizontal swipes into navigator page turns.
        true
      } else {
        if (event.actionMasked == MotionEvent.ACTION_MOVE) {
          programmaticScrollAnimator?.cancel()
          programmaticScrollAnimator = null
          isApplyingProgrammaticScroll = false
        }
        v.performClick()
        false
      }
    }

    applyTheme()
    invalidateLayout()
  }

  // MARK: - Layout

  private fun invalidateLayout() {
    isLayoutDirty = true
    applyLayoutIfNeeded()
  }

  /**
   * Applies per-image display sizes for the current preferences and viewport —
   * the constraint pass of `applyLayoutForCurrentPreferences` (iOS :224-261),
   * driven by an invalidation flag so repeated layout passes are cheap.
   */
  private fun applyLayoutIfNeeded() {
    val scrollView = scrollContainer ?: return
    val stack = stackView ?: return
    if (links.isEmpty()) return

    val viewportWidth = scrollView.width
    val viewportHeight = scrollView.height
    if (viewportWidth <= 0 || viewportHeight <= 0) return

    if (!isLayoutDirty &&
      viewportWidth == appliedViewportWidth && viewportHeight == appliedViewportHeight
    ) {
      return
    }

    appliedViewportWidth = viewportWidth
    appliedViewportHeight = viewportHeight
    isLayoutDirty = false

    val gap = gapPx
    val viewport = Size(viewportWidth.toFloat(), viewportHeight.toFloat())
    val attached = stack.children.toList()

    for ((index, imageView) in imageViews.withIndex()) {
      if (imageView.parent !== stack) continue

      val bitmap = bitmaps[index]
      // Unloaded pages reserve the viewport — iOS :253 (`images[index]?.size ?? viewport`).
      val naturalWidth = max(bitmap?.width?.toFloat() ?: viewport.width, 1f)
      val naturalHeight = max(bitmap?.height?.toFloat() ?: viewport.height, 1f)
      val displaySize = displayedImageSize(
        naturalWidth = naturalWidth,
        naturalHeight = naturalHeight,
        viewport = viewport
      )

      val params = imageView.layoutParams as? LinearLayout.LayoutParams
        ?: LinearLayout.LayoutParams(0, 0)
      params.width = displaySize.width.roundToInt()
      params.height = displaySize.height.roundToInt()
      // Page gap px between pages/spread halves — trailing margin only, so
      // edges stay flush with the viewport.
      val isLastAttached = imageView === attached.lastOrNull()
      if (stack.orientation == LinearLayout.HORIZONTAL) {
        params.marginEnd = if (!isLastAttached) gapPx else 0
        params.bottomMargin = 0
      } else {
        params.bottomMargin = if (!isLastAttached) gapPx else 0
        params.marginEnd = 0
      }
      imageView.layoutParams = params
    }

    clampContentOffsetForCurrentMode()
  }

  /**
   * Scale-type math — direct port of iOS `displayedImageSize(for:viewport:)`
   * (:409-451), including per-mode height capping, never-upscale default,
   * `stretchSmallPages`, and width-limit % for width-driven scale types.
   */
  private fun displayedImageSize(
    naturalWidth: Float,
    naturalHeight: Float,
    viewport: Size
  ): Size {
    val pageWidth = if (isDoublePageMode && isPaginatedMode) {
      max((viewport.width - gapPx.toFloat()) / 2f, 1f)
    } else {
      viewport.width
    }

    val scaleType = preferences.scaleType ?: "originalSize"
    val widthLimitApplies = scaleType == "fitWidth" || scaleType == "fitScreen"
    @Suppress("FloatingPointDivision")
    val widthPercent =
      ((preferences.widthLimitPercent ?: 50.0).coerceIn(10.0, 100.0)).toFloat() / 100f
    val availableWidth = max(
      1f,
      pageWidth * (
        if (preferences.widthLimitEnabled == true && widthLimitApplies) widthPercent else 1f
        )
    )

    val capHeight = isPaginatedMode || isHorizontalScrollMode
    val widthScale = availableWidth / naturalWidth
    val heightScale = viewport.height / naturalHeight
    val scale: Float = when (scaleType) {
      "fitWidth" -> if (capHeight) min(widthScale, heightScale) else widthScale
      "fitHeight" -> min(heightScale, widthScale)
      "fitScreen" -> min(widthScale, heightScale)
      else -> {
        var originalScale = min(1f, widthScale)
        if (capHeight) {
          originalScale = min(originalScale, heightScale)
        }
        originalScale
      }
    }

    val canStretch = preferences.stretchSmallPages == true && scaleType != "originalSize"
    val widthDriven = scaleType == "fitWidth" || scaleType == "fitScreen"
    val effectiveScale = if (canStretch || widthDriven) scale else min(scale, 1f)

    return Size(max(naturalWidth * effectiveScale, 1f), max(naturalHeight * effectiveScale, 1f))
  }

  // MARK: - Navigation

  /**
   * Port of iOS `navigateToIndex` (:273-301): paginated rebuilds the arranged
   * subviews and resets the offset to zero; continuous modes center the target
   * page along the scroll axis.
   */
  private fun navigateToIndex(index: Int, animated: Boolean, emit: Boolean = true) {
    if (links.isEmpty()) return
    currentIndex = index.coerceIn(0, links.size - 1)
    loadImagesAround(currentIndex)

    if (isPaginatedMode) {
      rebuildContent()
      rootView?.post {
        invalidateLayout()
        scrollContainer?.scrollTo(0, 0)
      }
    } else {
      val target = imageViews.getOrNull(currentIndex)
      val scrollView = scrollContainer
      if (target != null && scrollView != null && target.parent === stackView) {
        val x: Int
        val y: Int
        if (isHorizontalScrollMode) {
          x = max(target.left + target.width / 2 - scrollView.width / 2, 0)
          y = 0
        } else {
          x = 0
          y = max(target.top + target.height / 2 - scrollView.height / 2, 0)
        }
        scrollToOffset(x, y, animated)
      }
    }

    if (emit) {
      emitLocator(currentIndex)
    }
  }

  private fun scrollToOffset(x: Int, y: Int, animated: Boolean) {
    val scrollView = scrollContainer ?: return
    programmaticScrollAnimator?.cancel()
    programmaticScrollAnimator = null

    if (!animated) {
      isApplyingProgrammaticScroll = true
      scrollView.scrollTo(x, y)
      isApplyingProgrammaticScroll = false
      updateCurrentIndexFromScrollPosition()
      return
    }

    // Animated programmatic scrolls run through our own animator so the
    // suppression flag maps exactly to iOS's isApplyingProgrammaticScroll.
    isApplyingProgrammaticScroll = true
    val startX = scrollView.scrollX
    val startY = scrollView.scrollY
    val animator = ValueAnimator.ofFloat(0f, 1f).apply {
      duration = 250
      interpolator = DecelerateInterpolator()
      addUpdateListener { animation ->
        val fraction = animation.animatedValue as Float
        scrollView.scrollTo(
          (startX + (x - startX) * fraction).roundToInt(),
          (startY + (y - startY) * fraction).roundToInt()
        )
      }
      addListener(object : AnimatorListenerAdapter() {
        private var cancelled = false

        override fun onAnimationCancel(animation: Animator) {
          cancelled = true
        }

        override fun onAnimationEnd(animation: Animator) {
          isApplyingProgrammaticScroll = false
          if (!cancelled) {
            updateCurrentIndexFromScrollPosition()
          }
        }
      })
    }
    programmaticScrollAnimator = animator
    animator.start()
  }

  /** Emits a locator for [index] through the navigator contract. */
  private fun emitLocator(index: Int) {
    currentLocatorFlow.value = locatorAt(index)
  }

  /**
   * Port of iOS `updateCurrentIndexFromScrollPosition` (:303-328): probe point
   * at the viewport center along the scroll axis; nearest image center wins;
   * emits a locator and triggers preload on change.
   */
  private fun updateCurrentIndexFromScrollPosition() {
    if (isApplyingProgrammaticScroll) return
    if (isPaginatedMode || links.isEmpty()) return
    val scrollView = scrollContainer ?: return
    val stack = stackView ?: return

    val probeX = scrollView.scrollX + scrollView.width / 2
    val probeY = scrollView.scrollY + scrollView.height / 2
    val horizontal = isHorizontalScrollMode

    var closestIndex = currentIndex
    var closestDistance = Double.MAX_VALUE

    for ((index, imageView) in imageViews.withIndex()) {
      if (imageView.parent !== stack) continue

      val center = if (horizontal) {
        imageView.left + imageView.width / 2f
      } else {
        imageView.top + imageView.height / 2f
      }
      val target = if (horizontal) probeX else probeY
      val distance = abs(center - target).toDouble()
      if (distance < closestDistance) {
        closestDistance = distance
        closestIndex = index
      }
    }

    if (closestIndex == currentIndex) return
    currentIndex = closestIndex.coerceIn(0, links.size - 1)
    loadImagesAround(currentIndex)
    emitLocator(currentIndex)
  }

  /**
   * Webtoon programmatic page turn by % of viewport height — port of iOS
   * `scrollWebtoon` (:453-460).
   */
  private fun scrollWebtoon(forward: Boolean) {
    val scrollView = scrollContainer ?: return
    val stack = stackView ?: return

    @Suppress("FloatingPointDivision")
    val amount = scrollAmountPercent.coerceIn(10.0, 100.0) / 100
    val delta = scrollView.height * amount * (if (forward) 1 else -1)
    val maxY = max(stack.height - scrollView.height, 0)
    val targetY = (scrollView.scrollY + delta).roundToInt().coerceIn(0, maxY)
    scrollToOffset(0, targetY, animated = true)
  }

  /**
   * Content-offset clamping per mode — port of iOS
   * `clampContentOffsetForCurrentMode` (:486-506). Android clamps natively
   * during user scrolls; this guards layout changes (e.g. after a mode or
   * scale-type switch shrinks the content).
   */
  private fun clampContentOffsetForCurrentMode() {
    val scrollView = scrollContainer ?: return
    val stack = stackView ?: return

    when (scrollView) {
      is HorizontalScrollView -> {
        if (isPaginatedMode) {
          if (scrollView.scrollX != 0 || scrollView.scrollY != 0) {
            scrollView.scrollTo(0, 0)
          }
          return
        }
        val maxX = max(stack.width - scrollView.width, 0)
        val clampedX = scrollView.scrollX.coerceIn(0, maxX)
        if (clampedX != scrollView.scrollX) {
          scrollView.scrollTo(clampedX, 0)
        }
      }
      is ScrollView -> {
        val maxY = max(stack.height - scrollView.height, 0)
        val clampedY = scrollView.scrollY.coerceIn(0, maxY)
        if (clampedY != scrollView.scrollY) {
          scrollView.scrollTo(0, clampedY)
        }
      }
    }
  }

  // MARK: - Image loading

  /**
   * Preload window ±N around [index] with dedup via [loadingIndices], decoding
   * sequentially off the main thread — port of iOS `loadImages(around:)`
   * (:162-189).
   */
  private fun loadImagesAround(index: Int, hidesLoadingIndicatorOnCompletion: Boolean = false) {
    if (links.isEmpty()) return
    // iOS :165-167: paginated mode raises the window floor to the spread size.
    val amount = if (isPaginatedMode) {
      max(if (isDoublePageMode) 1 else 0, preloadAmount)
    } else {
      preloadAmount
    }
    val lowerBound = max(0, index - amount)
    val upperBound = min(links.size - 1, index + amount + (if (isDoublePageMode) 1 else 0))

    lifecycleScope.launch {
      for (i in lowerBound..upperBound) {
        if (bitmaps[i] != null || loadingIndices.contains(i)) continue
        loadingIndices.add(i)

        val link = links[i]
        val data = try {
          publication.get(link)?.read()?.getOrNull()
        } catch (e: Exception) {
          null
        }

        val bitmap = withContext(Dispatchers.Default) {
          data?.let { runCatching { BitmapFactory.decodeByteArray(it, 0, it.size) }.getOrNull() }
        }

        loadingIndices.remove(i)
        if (bitmap == null) continue

        bitmaps[i] = bitmap
        withContext(Dispatchers.Main) {
          imageViews.getOrNull(i)?.setImageBitmap(bitmap)
          isLayoutDirty = true
          applyLayoutIfNeeded()
        }
      }

      if (hidesLoadingIndicatorOnCompletion) {
        withContext(Dispatchers.Main) {
          loadingIndicator?.let { indicator ->
            (indicator.parent as? ViewGroup)?.removeView(indicator)
          }
          loadingIndicator = null
        }
      }
    }
  }

  // MARK: - Locator model

  /** Restore by position first, then href match — iOS `index(for:)` :330-340. */
  private fun initialIndex(): Int {
    val locator = model.initialLocation ?: return 0
    return indexFor(locator) ?: 0
  }

  private fun indexFor(locator: Locator): Int? {
    val position = locator.locations.position
    if (position != null && position > 0) {
      return min(position - 1, max(links.size - 1, 0))
    }

    // Port of iOS :330-340: raw and normalized href comparisons.
    val href = locator.href.toString()
    val normalizedHref = locator.href.normalize().toString()
    return links.indexOfFirst { link ->
      link.href.toString() == href ||
        link.url().toString() == href ||
        link.url().normalize().toString() == normalizedHref
    }
      .takeIf { it >= 0 }
  }

  /** `position = index+1`, `totalProgression = index/(count-1)` — iOS :342-356. */
  private fun locatorAt(index: Int): Locator {
    val link = links[index]
    val total = max(links.size, 1)
    val totalProgression = if (total > 1) index.toDouble() / (total - 1) else 0.0
    return Locator(
      href = link.url(),
      mediaType = link.mediaType ?: MediaType("image/jpeg")!!,
      title = link.title,
      locations = Locator.Locations(
        progression = 0.0,
        totalProgression = totalProgression,
        position = index + 1
      )
    )
  }

  // MARK: - Theme

  /** Hex background defaulting to black — iOS `UIColor(readerHex:)` :509-521. */
  private fun readerBackgroundColor(): Int {
    val hex = preferences.backgroundColor
      ?.trim()
      ?.filter { it.isLetterOrDigit() }
      ?: return Color.BLACK
    if (hex.length != 6) return Color.BLACK
    return try {
      Color.parseColor("#$hex")
    } catch (e: Exception) {
      Color.BLACK
    }
  }

  /**
   * Background color propagated to every reader surface — iOS `applyTheme`
   * (:401-407).
   */
  private fun applyTheme() {
    val color = readerBackgroundColor()
    rootView?.setBackgroundColor(color)
    scrollContainer?.setBackgroundColor(color)
    stackView?.setBackgroundColor(color)
    if (::imageViews.isInitialized) {
      imageViews.forEach { it.setBackgroundColor(color) }
    }
  }

  private data class Size(val width: Float, val height: Float)

  companion object {
    fun newInstance(): ComicReaderFragment {
      return ComicReaderFragment()
    }
  }
}
