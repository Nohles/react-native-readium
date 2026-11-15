package com.reactnativereadium.reader

import android.annotation.SuppressLint
import android.content.Context
import android.view.MotionEvent
import android.view.ScaleGestureDetector
import android.view.VelocityTracker
import android.view.View
import android.view.ViewConfiguration
import android.widget.FrameLayout
import android.widget.HorizontalScrollView
import android.widget.ScrollView
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min

/**
 * Pinch-to-zoom for the comic reader. Wraps the reader's scroll container and
 * scales it around the pinch focus; while zoomed in, one-finger drags pan.
 *
 * Panning moves the scaled container first; along the container's own scroll
 * axis (vertical for the vertical modes, horizontal for continuous
 * horizontal) the rest of the drag scrolls it, and a fling keeps scrolling.
 * Taps are never intercepted, so tap zones keep working while zoomed.
 *
 * The child is transformed with a top-left pivot, so a point at `local` in the
 * child draws at `translation + scale * local`.
 */
class ComicZoomLayout(context: Context) : FrameLayout(context) {

  /** Called when zoom returns to 1, or leaves it. */
  var onZoomChanged: ((zoomed: Boolean) -> Unit)? = null

  var scale = 1f
    private set

  val isZoomed: Boolean
    get() = scale > 1.01f

  private val touchSlop = ViewConfiguration.get(context).scaledTouchSlop
  private var isScaling = false
  private var isPanning = false
  private var lastX = 0f
  private var lastY = 0f
  private var downX = 0f
  private var downY = 0f
  private var velocityTracker: VelocityTracker? = null

  private val scaleDetector = ScaleGestureDetector(
    context,
    object : ScaleGestureDetector.SimpleOnScaleGestureListener() {
      override fun onScaleBegin(detector: ScaleGestureDetector): Boolean {
        isScaling = true
        return true
      }

      override fun onScale(detector: ScaleGestureDetector): Boolean {
        zoomTo(scale * detector.scaleFactor, detector.focusX, detector.focusY)
        return true
      }
    }
  ).apply {
    // Quick-scale (double-tap-and-drag) would delay every tap's delivery.
    isQuickScaleEnabled = false
  }

  private val target: View?
    get() = if (childCount > 0) getChildAt(0) else null

  /** Scales the child to [newScale] while keeping the content under ([focusX], [focusY]) in place. */
  fun zoomTo(newScale: Float, focusX: Float, focusY: Float) {
    val child = target ?: return
    val clamped = newScale.coerceIn(MIN_SCALE, MAX_SCALE)
    val wasZoomed = isZoomed
    child.pivotX = 0f
    child.pivotY = 0f
    val localX = (focusX - child.translationX) / scale
    val localY = (focusY - child.translationY) / scale
    scale = clamped
    child.scaleX = clamped
    child.scaleY = clamped
    child.translationX = focusX - clamped * localX
    child.translationY = focusY - clamped * localY
    clampTranslation()
    if (wasZoomed != isZoomed) onZoomChanged?.invoke(isZoomed)
  }

  fun resetZoom() {
    val child = target ?: return
    if (scale == 1f && child.translationX == 0f && child.translationY == 0f) return
    val wasZoomed = isZoomed
    scale = 1f
    child.scaleX = 1f
    child.scaleY = 1f
    child.translationX = 0f
    child.translationY = 0f
    if (wasZoomed) onZoomChanged?.invoke(false)
  }

  /** Maps a point in the child's coordinates to this layout's (screen) coordinates. */
  fun toLayoutPoint(x: Float, y: Float): Pair<Float, Float> {
    val child = target ?: return x to y
    return (child.translationX + scale * x) to (child.translationY + scale * y)
  }

  private fun clampTranslation() {
    val child = target ?: return
    val minX = min(0f, width - width * scale)
    val minY = min(0f, height - height * scale)
    child.translationX = child.translationX.coerceIn(minX, 0f)
    child.translationY = child.translationY.coerceIn(minY, 0f)
  }

  override fun dispatchTouchEvent(event: MotionEvent): Boolean {
    // The scale detector must see every event, including those a child takes.
    scaleDetector.onTouchEvent(event)
    if (event.actionMasked == MotionEvent.ACTION_UP || event.actionMasked == MotionEvent.ACTION_CANCEL) {
      if (isScaling && !isZoomed) resetZoom()
    }
    return super.dispatchTouchEvent(event)
  }

  override fun onInterceptTouchEvent(event: MotionEvent): Boolean {
    when (event.actionMasked) {
      MotionEvent.ACTION_DOWN -> {
        isScaling = false
        isPanning = false
        downX = event.x
        downY = event.y
        lastX = event.x
        lastY = event.y
        startVelocity(event)
      }
      MotionEvent.ACTION_POINTER_DOWN -> return true
      MotionEvent.ACTION_MOVE -> {
        trackVelocity(event)
        if (isScaling) return true
        if (isZoomed && (abs(event.x - downX) > touchSlop || abs(event.y - downY) > touchSlop)) {
          isPanning = true
          lastX = event.x
          lastY = event.y
          return true
        }
      }
    }
    return false
  }

  @SuppressLint("ClickableViewAccessibility")
  override fun onTouchEvent(event: MotionEvent): Boolean {
    trackVelocity(event)
    when (event.actionMasked) {
      MotionEvent.ACTION_MOVE -> {
        if (isScaling || event.pointerCount > 1) {
          lastX = event.x
          lastY = event.y
          return true
        }
        if (isZoomed) {
          isPanning = true
          pan(event.x - lastX, event.y - lastY)
        }
        lastX = event.x
        lastY = event.y
      }
      MotionEvent.ACTION_POINTER_UP -> {
        // Continue panning from the finger that stays down.
        val remaining = if (event.actionIndex == 0) 1 else 0
        lastX = event.getX(remaining)
        lastY = event.getY(remaining)
      }
      MotionEvent.ACTION_UP -> {
        if (isPanning && !isScaling) fling()
        recycleVelocity()
        isPanning = false
        isScaling = false
      }
      MotionEvent.ACTION_CANCEL -> {
        recycleVelocity()
        isPanning = false
        isScaling = false
      }
    }
    return true
  }

  /** Moves the content by ([dx], [dy]) screen pixels. */
  private fun pan(dx: Float, dy: Float) {
    val child = target ?: return
    val beforeX = child.translationX
    val beforeY = child.translationY
    child.translationX += dx
    child.translationY += dy
    clampTranslation()
    val leftoverX = dx - (child.translationX - beforeX)
    val leftoverY = dy - (child.translationY - beforeY)
    when (child) {
      is HorizontalScrollView -> child.scrollBy((-leftoverX / scale).toInt(), 0)
      is ScrollView -> child.scrollBy(0, (-leftoverY / scale).toInt())
    }
  }

  private fun fling() {
    val tracker = velocityTracker ?: return
    tracker.computeCurrentVelocity(1000)
    when (val child = target) {
      is HorizontalScrollView -> child.fling((-tracker.xVelocity / scale).toInt())
      is ScrollView -> child.fling((-tracker.yVelocity / scale).toInt())
    }
  }

  private fun startVelocity(event: MotionEvent) {
    recycleVelocity()
    velocityTracker = VelocityTracker.obtain().also { it.addMovement(event) }
  }

  private fun trackVelocity(event: MotionEvent) {
    velocityTracker?.addMovement(event)
  }

  private fun recycleVelocity() {
    velocityTracker?.recycle()
    velocityTracker = null
  }

  override fun onSizeChanged(w: Int, h: Int, oldw: Int, oldh: Int) {
    super.onSizeChanged(w, h, oldw, oldh)
    resetZoom()
  }

  companion object {
    const val MIN_SCALE = 1f
    const val MAX_SCALE = 4f
  }
}
