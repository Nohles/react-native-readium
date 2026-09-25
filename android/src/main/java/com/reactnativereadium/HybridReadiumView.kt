package com.margelo.nitro.reactnativereadium

import android.util.Log
import android.view.Choreographer
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import androidx.fragment.app.FragmentActivity
import com.reactnativereadium.ReaderHostView
import com.reactnativereadium.audio.AudiobookSession
import com.reactnativereadium.reader.BaseReaderFragment
import com.reactnativereadium.reader.ComicReaderFragment
import com.reactnativereadium.reader.EpubReaderFragment
import com.reactnativereadium.reader.ReaderService
import com.reactnativereadium.reader.ReaderViewModel
import com.reactnativereadium.reader.SelectionAction as FragmentSelectionAction
import com.reactnativereadium.utils.nitroPreferencesToEpub
import com.reactnativereadium.utils.nitroPreferencesToComic
import com.reactnativereadium.utils.nitroLocatorToReadium
import com.reactnativereadium.utils.nitroDecorationToReadium
import com.reactnativereadium.utils.readiumLocatorToNitro
import com.reactnativereadium.utils.readiumLinkToNitro
import com.reactnativereadium.utils.flattenReadiumLinks
import com.reactnativereadium.utils.readiumDecorationToNitro
import com.reactnativereadium.utils.readiumMetadataToNitro
import com.reactnativereadium.utils.toNitroPlaybackState
import com.margelo.nitro.core.Promise
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.services.search.SearchIterator
import org.readium.r2.shared.publication.services.search.isSearchable
import org.readium.r2.shared.publication.services.search.search

@OptIn(ExperimentalReadiumApi::class)
class HybridReadiumView(private val context: android.content.Context) : HybridReadiumViewSpec() {
  companion object {
    private const val CONTAINER_ID_ATTEMPTS = 20
    private const val TAG = "HybridReadiumView"
    private var nextInstanceId = 0
    // Fabric creates the new native view before removing the old one when React
    // remounts via key change. The old hostView (with its WebView) stays in the
    // tree covering the new view until Fabric eventually detaches it. This
    // registry lets a new instance force-clear stale ones immediately.
    private val liveInstances = mutableMapOf<Int, HybridReadiumView>()
    init {
      NitroReadiumOnLoad.initializeNative()
    }
  }

  private val instanceId = nextInstanceId++
  private val hostView = ReaderHostView(context)
  private var scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  /**
   * Publication search runs off the main looper. `publication.search()` and
   * `SearchIterator.next()` both do file and network I/O — for a remote WebPub
   * that is a round trip per page — and they were previously dispatched on
   * [scope], which is pinned to `Dispatchers.Main`.
   */
  private var searchScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
  private val searchLock = Any()
  private var svc: ReaderService? = null
  private var fragment: BaseReaderFragment? = null
  private var audiobookJob: kotlinx.coroutines.Job? = null
  private var hostedAudiobookPublication: org.readium.r2.shared.publication.Publication? = null
  private var isFragmentAdded = false
  private var isBuilding = false
  private var isAttached = false
  private var isDestroyed = false
  private var frameCallback: Choreographer.FrameCallback? = null
  private var searchIterator: SearchIterator? = null
  private var searchQuery = ""
  private var searchResultOffset = 0

  override val view: View get() = hostView

  init {
    hostView.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
      override fun onViewAttachedToWindow(v: View) {
        isAttached = true
        buildForViewIfReady()
      }
      override fun onViewDetachedFromWindow(v: View) {
        isAttached = false
        teardownFragment()
      }
    })
  }

  // MARK: - Props

  override var file: ReadiumFile? = null
    set(value) {
      val previousUrl = field?.url
      field = value
      if (value != null) {
        if (isFragmentAdded && value.url != previousUrl) {
          teardownFragment()
        }
        buildForViewIfReady()
      }
    }

  override var reopenActiveAudiobook: Boolean? = null
    set(value) {
      field = value
      // iOS reads this when adopting the persistent session
      // (HybridReadiumView.swift:167-171): with the flag off, a re-open starts
      // a fresh session instead of resuming the running one. Android previously
      // ignored it and always resumed, so a host could not force a reset.
      if (value == false) {
        AudiobookSession.reset()
      }
    }

  override var preferences: Preferences? = null
    set(value) {
      field = value
      updatePreferences()
    }

  override var decorations: Array<DecorationGroup>? = null
    set(value) {
      field = value
      updateDecorations()
    }

  override var selectionActions: Array<SelectionAction>? = null
    set(value) {
      field = value
      updateSelectionActions()
    }

  override var audiobookBookmarks: Array<AudiobookBookmark>? = null
  override var onLocationChange: ((locator: Locator) -> Unit)? = null
  override var onTap: ((point: Point) -> Unit)? = null
  override var onPublicationReady: ((event: PublicationReadyEvent) -> Unit)? = null
  override var onDecorationActivated: ((event: DecorationActivatedEvent) -> Unit)? = null
  override var onSelectionChange: ((event: SelectionEvent) -> Unit)? = null
  override var onSelectionAction: ((event: SelectionActionEvent) -> Unit)? = null
  override var onAudiobookPlaybackStateChange: ((state: AudiobookPlaybackState) -> Unit)? = null
  override var onAudiobookBookmarkChange: ((event: AudiobookBookmarkChangeEvent) -> Unit)? = null

  private fun ensureService(): Boolean {
    if (svc != null) return true
    val reactContext =
      (context as? com.facebook.react.uimanager.ThemedReactContext)?.reactApplicationContext
    if (reactContext == null) {
      // Previously this returned silently, so `buildForViewIfReady` bailed with
      // no diagnostic and the host saw an empty view with no way to tell why.
      Log.e(
        TAG,
        "ReadiumView requires a ThemedReactContext to open publications " +
          "(got ${context.javaClass.name}). The reader will not load."
      )
      return false
    }
    svc = ReaderService(reactContext)
    return true
  }

  // MARK: - Preferences

  private fun updatePreferences() {
    val prefs = preferences ?: return
    when (val frag = fragment) {
      is EpubReaderFragment -> frag.updatePreferences(nitroPreferencesToEpub(prefs))
      is ComicReaderFragment -> frag.updatePreferences(nitroPreferencesToComic(prefs))
      else -> Unit
    }
  }

  // MARK: - Decorations

  private fun updateDecorations() {
    val groups = decorations ?: return
    val frag = fragment ?: return

    val readiumGroups = mutableMapOf<String, List<org.readium.r2.navigator.Decoration>>()
    for (group in groups) {
      readiumGroups[group.name] = group.decorations.mapNotNull { nitroDecorationToReadium(it) }
    }

    frag.applyDecorations(readiumGroups)
  }

  // MARK: - Selection Actions

  private fun updateSelectionActions() {
    val actions = selectionActions?.takeIf { it.isNotEmpty() } ?: return
    val frag = fragment as? EpubReaderFragment ?: return
    frag.updateSelectionActions(actions.map { FragmentSelectionAction(it.id, it.label) })
  }

  // MARK: - Imperative navigation

  override fun goTo(locator: Locator) {
    val action = Runnable {
      val readiumLocator = nitroLocatorToReadium(locator) ?: return@Runnable
      fragment?.go(com.reactnativereadium.utils.LinkOrLocator.Locator(readiumLocator), true)
    }
    if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
      action.run()
    } else {
      hostView.post(action)
    }
  }

  override fun goForward() { fragment?.goForward() }
  override fun goBackward() { fragment?.goBackward() }

  // MARK: - Audiobook playback (delegated to the persistent session when this
  // view hosts an audiobook; mirrors iOS view adoption of AudiobookSession)

  private fun withAudiobook(block: (AudiobookSession) -> Unit) {
    if (isFragmentAdded && fragment == null) {
      block(AudiobookSession)
    }
  }

  override fun play() = withAudiobook { it.play() }
  override fun pause() = withAudiobook { it.pause() }
  override fun seekTo(position: Double) = withAudiobook { it.seekTo(position) }
  override fun setPlaybackRate(rate: Double) = withAudiobook { it.setPlaybackRate(rate) }
  override fun setVolume(volume: Double) = withAudiobook { it.setVolume(volume) }
  override fun setSleepTimer(seconds: Double?) = withAudiobook { it.setSleepTimer(seconds) }

  override fun search(query: String): Promise<PublicationSearchPage> {
    // Read the fragment on the calling (main) thread: `fragment` is mutated by
    // the main-thread fragment lifecycle, so touching it from a worker is a data
    // race and, for a `lateinit` behind it, a crash.
    val publication = fragment?.publication()
      ?: return Promise.async(searchScope) {
        throw IllegalStateException("Publication is not ready.")
      }

    val normalizedQuery = query.trim()
    if (normalizedQuery.isEmpty()) {
      return Promise.async(searchScope) {
        throw IllegalArgumentException("Search query must not be empty.")
      }
    }

    return Promise.async(searchScope) {
      cancelSearch()
      val iterator = publication.search(normalizedQuery)
        ?: throw IllegalStateException("Publication search is unavailable.")
      synchronized(searchLock) {
        searchIterator = iterator
        searchQuery = normalizedQuery
        searchResultOffset = 0
      }
      nextSearchPage(iterator, normalizedQuery)
    }
  }

  override fun searchNext(): Promise<PublicationSearchPage> {
    val iterator = synchronized(searchLock) { searchIterator }
    val query = synchronized(searchLock) { searchQuery }

    return Promise.async(searchScope) {
      if (iterator == null) {
        return@async PublicationSearchPage(
          query = query,
          locators = emptyArray(),
          total = null,
          hasNext = false
        )
      }
      nextSearchPage(iterator, query)
    }
  }

  private suspend fun nextSearchPage(
    iterator: SearchIterator,
    query: String
  ): PublicationSearchPage {
    val result = iterator.next()
    val failure = result.failureOrNull()
    if (failure != null) {
      throw IllegalStateException(failure.message)
    }
    val collection = result.getOrNull()
    if (collection == null) {
      iterator.close()
      synchronized(searchLock) {
        if (searchIterator === iterator) searchIterator = null
      }
      return PublicationSearchPage(
        query = query,
        locators = emptyArray(),
        total = iterator.resultCount?.toDouble(),
        hasNext = false
      )
    }
    val total = iterator.resultCount
    val offset = synchronized(searchLock) {
      searchResultOffset += collection.locators.size
      searchResultOffset
    }
    return PublicationSearchPage(
      query = query,
      locators = collection.locators.map { readiumLocatorToNitro(it) }.toTypedArray(),
      total = total?.toDouble(),
      hasNext = total?.let { offset < it } ?: collection.locators.isNotEmpty()
    )
  }

  override fun cancelSearch() {
    synchronized(searchLock) {
      searchIterator?.close()
      searchIterator = null
      searchResultOffset = 0
    }
  }

  override fun destroy() {
    if (android.os.Looper.myLooper() == android.os.Looper.getMainLooper()) {
      cleanup()
    } else {
      hostView.post { cleanup() }
    }
  }

  // MARK: - Audiobook hosting

  /**
   * The file routed to the persistent audiobook session instead of a reader
   * fragment. Playback is owned by [AudiobookSession] and keeps running when
   * this view tears down; we only observe state while mounted.
   */
  private fun hostAudiobook() {
    if (isDestroyed) return
    isFragmentAdded = true
    isBuilding = false

    audiobookJob?.cancel()
    audiobookJob = scope.launch {
      var readyFor: org.readium.r2.shared.publication.Publication? = null
      AudiobookSession.state.collect { sessionState ->
        val publication = sessionState.publication
        if (publication != null && publication !== readyFor &&
          sessionState.status != com.reactnativereadium.audio.AudiobookStatus.LOADING
        ) {
          readyFor = publication
          hostedAudiobookPublication = publication
          onPublicationReady?.invoke(PublicationReadyEvent(
            tableOfContents = flattenReadiumLinks(publication.tableOfContents).toTypedArray(),
            positions = publication.readingOrder.mapNotNull { publication.locatorFromLink(it) }
              .map { readiumLocatorToNitro(it) }.toTypedArray(),
            metadata = readiumMetadataToNitro(publication.metadata),
            // Search is currently implemented for visual fragments; audiobooks
            // are hosted headlessly and have no fragment-backed search iterator.
            capabilities = PublicationCapabilities(search = false, searchHref = null)
          ))
        }
        onAudiobookPlaybackStateChange?.invoke(sessionState.toNitroPlaybackState())
      }
    }
  }

  // MARK: - Fragment management

  /**
   * Tears down the current fragment and resets state so a new fragment can
   * be built. Safe to call multiple times. Does NOT detach hostView from the
   * tree — use [cleanup] for permanent removal.
   */
  private fun teardownFragment() {
    cancelSearch()
    liveInstances.remove(instanceId)

    frameCallback?.let {
      try {
        Choreographer.getInstance().removeFrameCallback(it)
      } catch (e: Exception) {
        Log.w(TAG, "Failed to remove frame callback during teardown: ${e.message}")
      }
    }
    frameCallback = null

    fragment?.let { frag ->
      try {
        findActivity()?.supportFragmentManager
          ?.beginTransaction()
          ?.remove(frag)
          ?.commitNowAllowingStateLoss()
      } catch (e: Exception) {
        Log.w(TAG, "teardownFragment: failed to remove fragment: ${e.message}")
      }
    }

    hostView.removeAllViews()
    fragment = null
    isFragmentAdded = false
    isBuilding = false

    // Detach from audiobook playback but do NOT stop it: the persistent
    // session keeps playing across reader close/reopen (iOS parity).
    audiobookJob?.cancel()
    audiobookJob = null
    hostedAudiobookPublication = null

    scope.cancel()
    scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    // The search scope is cancelled separately so an in-flight remote search is
    // abandoned with the reader rather than outliving it on a background thread.
    searchScope.cancel()
    searchScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
  }

  /**
   * Permanently tears down the fragment and physically detaches hostView from
   * the tree so it cannot overlay or intercept touches on other views.
   *
   * Reachable from two places: the JS `destroy()` method, and the stale-instance
   * sweep in [addFragment] when Fabric remounts this view under a new key. It is
   * *not* wired to `ViewManager.onDropViewInstance` — the nitrogen-generated
   * manager has no such override — so a host that unmounts the React view
   * without calling `destroy()` leaks the fragment until another instance
   * sweeps it. A JS `destroy()` is always paired with an unmount in
   * `ReadiumView.tsx`, which is why the gap has not surfaced.
   */
  internal fun cleanup() {
    if (isDestroyed) return
    isDestroyed = true

    teardownFragment()
    (hostView.parent as? ViewGroup)?.removeView(hostView)
  }

  private fun buildForViewIfReady() {
    if (isDestroyed) return
    if (!isAttached) return
    if (isFragmentAdded) return
    if (isBuilding) return
    val currentFile = file ?: return
    val fileUrl = currentFile.url
    if (fileUrl.isEmpty()) return

    ensureService()
    val service = svc ?: run {
      isBuilding = false
      return
    }

    isBuilding = true

    val path = fileUrl.replace("^(file:/+)?(/.*)$".toRegex(), "$2")

    val initialLocator = currentFile.initialLocation?.let { loc ->
      nitroLocatorToReadium(loc)?.let { com.reactnativereadium.utils.LinkOrLocator.Locator(it) }
    }

    scope.launch {
      service.openPublication(
        path,
        initialLocator,
        callback = { result ->
          when (result) {
            is ReaderService.OpenResult.Visual -> addFragment(result.fragment)
            ReaderService.OpenResult.Audiobook -> hostAudiobook()
          }
        },
        onFailure = { message ->
          // Mirror of iOS loadBook onFailure reset: log and clear the build
          // state so the same file can be retried (e.g. after re-attach).
          Log.e(TAG, "Failed to open publication: $message")
          isBuilding = false
        }
      )
    }
  }

  private fun addFragment(frag: BaseReaderFragment) {
    if (isFragmentAdded) return

    // Force-clear any stale instances whose hostViews are still in Fabric's
    // tree from a key-change remount.
    liveInstances.values.toList().filter { it !== this }.forEach { other ->
      other.cleanup()
    }
    liveInstances[instanceId] = this

    fragment = frag
    isFragmentAdded = true
    setupLayout()

    val activity = findActivity()
    if (activity == null) {
      Log.e(TAG, "Could not find FragmentActivity")
      return
    }

    val containerId = assignContainerId(activity)

    // Apply selection actions BEFORE committing so they're available
    // during onCreate when the callback is conditionally registered.
    selectionActions?.takeIf { it.isNotEmpty() }?.let { actions ->
      if (frag is EpubReaderFragment) {
        frag.updateSelectionActions(actions.map { FragmentSelectionAction(it.id, it.label) })
      }
    }

    activity.supportFragmentManager
      .beginTransaction()
      .replace(containerId, frag, containerId.toString())
      .commitNow()

    // The FragmentManager may not find hostView via activity.findViewById()
    // in React Native's Fabric view tree. Manually add the fragment's view
    // to hostView if needed.
    frag.view?.let { fragView ->
      if (fragView.parent !== hostView) {
        (fragView.parent as? ViewGroup)?.removeView(fragView)
        hostView.addView(fragView, FrameLayout.LayoutParams(
          FrameLayout.LayoutParams.MATCH_PARENT,
          FrameLayout.LayoutParams.MATCH_PARENT
        ))
      } else {
        fragView.layoutParams = FrameLayout.LayoutParams(
          FrameLayout.LayoutParams.MATCH_PARENT,
          FrameLayout.LayoutParams.MATCH_PARENT
        )
      }
    } ?: Log.w(TAG, "addFragment: fragment view is null after commitNow!")

    preferences?.let { updatePreferences() }
    decorations?.let { updateDecorations() }

    frag.channel.receive(frag) { event ->
      when (event) {
        is ReaderViewModel.Event.LocatorUpdate -> {
          onLocationChange?.invoke(readiumLocatorToNitro(event.locator))
        }
        is ReaderViewModel.Event.PublicationReady -> {
          val publication = frag.publication()
          val searchLink = publication.linkWithRel("search")
          onPublicationReady?.invoke(PublicationReadyEvent(
            tableOfContents = flattenReadiumLinks(event.tableOfContents).toTypedArray(),
            positions = event.positions.map { readiumLocatorToNitro(it) }.toTypedArray(),
            metadata = readiumMetadataToNitro(event.metadata),
            capabilities = PublicationCapabilities(
              search = publication.isSearchable || searchLink != null,
              searchHref = searchLink?.href?.toString()
            )
          ))
        }
        is ReaderViewModel.Event.DecorationActivated -> {
          val rect = event.rect?.let {
            Rect(x = it.left.toDouble(), y = it.top.toDouble(), width = it.width().toDouble(), height = it.height().toDouble())
          }
          val point = event.point?.let { Point(x = it.x.toDouble(), y = it.y.toDouble()) }
          onDecorationActivated?.invoke(DecorationActivatedEvent(
            decoration = readiumDecorationToNitro(event.decoration),
            group = event.group,
            rect = rect,
            point = point
          ))
        }
        is ReaderViewModel.Event.SelectionChanged -> {
          onSelectionChange?.invoke(SelectionEvent(
            locator = event.locator?.let { readiumLocatorToNitro(it) },
            selectedText = event.selectedText
          ))
        }
        is ReaderViewModel.Event.SelectionAction -> {
          onSelectionAction?.invoke(SelectionActionEvent(
            locator = readiumLocatorToNitro(event.locator),
            selectedText = event.selectedText,
            actionId = event.actionId
          ))
        }
        is ReaderViewModel.Event.Tapped -> {
          onTap?.invoke(Point(x = event.point.x.toDouble(), y = event.point.y.toDouble()))
        }
      }
    }
  }

  private fun setupLayout() {
    frameCallback = object : Choreographer.FrameCallback {
      override fun doFrame(frameTimeNanos: Long) {
        manuallyLayoutChildren()
        hostView.viewTreeObserver.dispatchOnGlobalLayout()
        Choreographer.getInstance().postFrameCallback(this)
      }
    }
    frameCallback?.let { Choreographer.getInstance().postFrameCallback(it) }
  }

  /**
   * Gives [hostView] an id that FragmentManager will resolve back to it, and
   * returns that id.
   *
   * FragmentManager looks the container up with `activity.findViewById()`, so a
   * colliding id silently attaches the reader somewhere else entirely.
   * `View.generateViewId()` draws from a process-wide counter starting at 1, and
   * React Native labels its root views with the surface tag - also a small
   * integer - so the first id generated in a process is typically 1, the very id
   * `ReactSurfaceView` carries. The fragment then lands on the React root, and
   * the corrective re-parent in [addFragment] has to move an already-attached
   * view. That is fatal for PDF: AndroidPdfViewer's `PDFView` nulls its rendering
   * `HandlerThread` in `onDetachedFromWindow()` and never recreates it, so the
   * next `load()` completes into a NullPointerException.
   */
  private fun assignContainerId(activity: FragmentActivity): Int {
    repeat(CONTAINER_ID_ATTEMPTS) {
      val candidate = View.generateViewId()
      hostView.id = candidate

      when (activity.findViewById<View>(candidate)) {
        // Resolves to us: FragmentManager will attach the fragment to hostView.
        hostView -> return candidate
        // Unreachable from the activity, so nothing can collide with it either.
        // FragmentManager resolves a null container and leaves the fragment view
        // unparented, which addFragment then adopts without detaching anything.
        null -> return candidate
        // Collision with another view - try a different id.
        else -> Unit
      }
    }

    Log.w(TAG, "addFragment: could not find a non-colliding container id for hostView")
    return hostView.id
  }

  private fun manuallyLayoutChildren() {
    val w = hostView.measuredWidth
    val h = hostView.measuredHeight
    if (w <= 0 || h <= 0) return

    for (i in 0 until hostView.childCount) {
      val child = hostView.getChildAt(i)
      child.measure(
        View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
        View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY)
      )
      child.layout(0, 0, w, h)
    }
  }

  private fun findActivity(): FragmentActivity? {
    var ctx: android.content.Context? = hostView.context
    while (ctx != null) {
      if (ctx is FragmentActivity) return ctx
      ctx = (ctx as? android.content.ContextWrapper)?.baseContext
    }
    return null
  }
}
