package com.reactnativereadium.reader

import android.annotation.SuppressLint
import android.content.Context
import android.content.res.ColorStateList
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.graphics.drawable.RippleDrawable
import android.util.TypedValue
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.core.graphics.ColorUtils
import androidx.core.view.ViewCompat
import kotlin.math.min
import kotlin.math.roundToInt

enum class ComicBoundaryKind(val value: String) {
  PREVIOUS("previous"),
  NEXT("next")
}

/**
 * Host-provided strings for one chapter boundary page. Mirrors the
 * `ComicBoundaryPage` Nitro struct without tying the reader to bridge types.
 */
data class ComicBoundaryContent(
  val finishedLabel: String? = null,
  val finishedTitle: String? = null,
  val label: String? = null,
  val title: String? = null,
  val actions: List<Action> = emptyList()
) {
  data class Action(val id: String, val label: String, val secondary: Boolean)
}

/**
 * Full-viewport page shown before the first or after the last comic page in
 * scroll modes, laid out like the web reader's chapter boundary page (and the
 * iOS `ComicBoundaryPageView`): an optional "Finished" section above a section
 * with the adjacent chapter (or the end-of-series message) and its actions.
 */
@SuppressLint("ViewConstructor")
class ComicBoundaryPageView(context: Context, val kind: ComicBoundaryKind) : FrameLayout(context) {
  /** Called with the action id when one of the page's buttons is pressed. */
  var onAction: ((String) -> Unit)? = null

  private val contentStack = LinearLayout(context).apply {
    orientation = LinearLayout.VERTICAL
  }
  private var content: ComicBoundaryContent? = null
  private var textColor = Color.WHITE
  private var pageBackgroundColor = Color.BLACK

  init {
    tag = "comic-boundary-${kind.value}"
    addView(
      contentStack,
      LayoutParams(LayoutParams.WRAP_CONTENT, LayoutParams.WRAP_CONTENT, Gravity.CENTER)
    )
  }

  override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
    // Content is at most 360dp wide, with 32dp of page padding on narrow screens.
    val available = MeasureSpec.getSize(widthMeasureSpec) - dp(PAGE_PADDING_DP) * 2
    val width = min(dp(MAX_CONTENT_WIDTH_DP), available).coerceAtLeast(0)
    val params = contentStack.layoutParams
    if (params.width != width) {
      params.width = width
      contentStack.layoutParams = params
    }
    super.onMeasure(widthMeasureSpec, heightMeasureSpec)
  }

  fun configure(content: ComicBoundaryContent, textColor: Int, backgroundColor: Int) {
    val themeChanged = textColor != this.textColor || backgroundColor != pageBackgroundColor
    this.textColor = textColor
    pageBackgroundColor = backgroundColor
    setBackgroundColor(backgroundColor)
    if (content == this.content && !themeChanged) return
    this.content = content
    rebuild()
  }

  private fun rebuild() {
    contentStack.removeAllViews()
    val content = content ?: return
    val sections = mutableListOf<View>()
    if (content.finishedLabel != null || content.finishedTitle != null) {
      sections += section(content.finishedLabel, content.finishedTitle, emptyList())
    }
    if (content.label != null || content.title != null || content.actions.isNotEmpty()) {
      sections += section(content.label, content.title, content.actions)
    }
    sections.forEachIndexed { index, section ->
      contentStack.addView(
        section,
        LinearLayout.LayoutParams(
          LinearLayout.LayoutParams.MATCH_PARENT,
          LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { if (index > 0) topMargin = dp(48) }
      )
    }
  }

  private fun section(
    label: String?,
    title: String?,
    actions: List<ComicBoundaryContent.Action>
  ): View {
    val stack = LinearLayout(context).apply { orientation = LinearLayout.VERTICAL }
    val children = mutableListOf<View>()
    label?.let { children += text(it, 18f) }
    title?.let { children += text(it, 22f) }
    actions.forEach { children += button(it) }
    children.forEachIndexed { index, child ->
      stack.addView(
        child,
        LinearLayout.LayoutParams(
          LinearLayout.LayoutParams.MATCH_PARENT,
          LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { if (index > 0) topMargin = dp(12) }
      )
    }
    return stack
  }

  private fun text(value: String, sizeSp: Float): TextView =
    TextView(context).apply {
      text = value
      setTextColor(textColor)
      setTextSize(TypedValue.COMPLEX_UNIT_SP, sizeSp)
      typeface = Typeface.DEFAULT_BOLD
      isFocusable = false
      importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_YES
      ViewCompat.setAccessibilityHeading(this, true)
    }

  private fun button(action: ComicBoundaryContent.Action): Button {
    val fill = if (action.secondary) {
      ColorUtils.setAlphaComponent(textColor, (0.04f * 255).roundToInt())
    } else {
      textColor
    }
    val shape = GradientDrawable().apply {
      cornerRadius = dp(8).toFloat()
      setColor(fill)
      if (action.secondary) {
        setStroke(dp(1), ColorUtils.setAlphaComponent(textColor, (0.14f * 255).roundToInt()))
      }
    }
    val rippleColor = ColorUtils.setAlphaComponent(
      if (action.secondary) textColor else pageBackgroundColor,
      (0.16f * 255).roundToInt()
    )
    return Button(context).apply {
      text = action.label
      isAllCaps = false
      stateListAnimator = null
      minWidth = 0
      minimumWidth = 0
      gravity = Gravity.CENTER
      setTextColor(if (action.secondary) textColor else pageBackgroundColor)
      setTextSize(TypedValue.COMPLEX_UNIT_SP, 15f)
      typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
      minHeight = dp(44)
      setPadding(dp(16), dp(10), dp(16), dp(10))
      background = RippleDrawable(ColorStateList.valueOf(rippleColor), shape, null)
      isClickable = true
      isFocusable = true
      contentDescription = action.label
      setOnClickListener { onAction?.invoke(action.id) }
    }
  }

  private fun dp(value: Int): Int = (value * resources.displayMetrics.density).roundToInt()

  private companion object {
    const val MAX_CONTENT_WIDTH_DP = 360
    const val PAGE_PADDING_DP = 32
  }
}
