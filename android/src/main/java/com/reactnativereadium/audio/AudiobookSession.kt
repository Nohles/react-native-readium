package com.reactnativereadium.audio

import android.content.Intent
import android.os.Handler
import android.os.Looper
import androidx.media3.common.Player
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.util.RNLog
import com.margelo.nitro.NitroModules
import com.reactnativereadium.reader.ReaderService
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import org.readium.adapter.exoplayer.audio.ExoPlayerEngineProvider
import org.readium.navigator.media.audio.AudioNavigator
import org.readium.navigator.media.audio.AudioNavigatorFactory
import org.readium.navigator.media.common.DefaultMediaMetadataProvider
import org.readium.r2.shared.DelicateReadiumApi
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Try
import org.readium.r2.shared.util.Url as ReadiumUrl
import org.readium.r2.shared.util.mediatype.MediaType
import kotlin.time.Duration.Companion.seconds

/**
 * A host-owned audiobook bookmark. Mirrors the JS `AudiobookBookmark`: the
 * Readium [Locator] for [position] on the chapter timeline, so a bookmark
 * survives a re-open even if the item durations shift slightly.
 */
data class AudiobookBookmark(
  val id: String,
  val locator: Locator,
  val position: Double,
  val note: String? = null,
)

/** Mirrors iOS `AudiobookSessionStatus`. */
enum class AudiobookStatus { IDLE, LOADING, READY, PLAYING, PAUSED, ENDED, ERROR }

/**
 * Snapshot of the persistent audiobook playback session. `position` and
 * `duration` are absolute seconds across the whole book (chapter timeline),
 * matching the iOS parity bar.
 */
data class AudiobookSessionState(
  val status: AudiobookStatus = AudiobookStatus.IDLE,
  val publication: Publication? = null,
  val position: Double = 0.0,
  val duration: Double = 0.0,
  val rate: Double = 1.0,
  val volume: Double = 1.0,
  val currentHref: String? = null,
  val currentTitle: String? = null,
  val sleepTimerRemaining: Double? = null,
  val error: String? = null,
)

/**
 * Owns audiobook playback independently from any visual host — the Android
 * mirror of iOS `AudiobookSession` (ios/Reader/Audiobook/AudiobookSession.swift).
 *
 * Playback is delegated to kotlin-toolkit's Media3-based `AudioNavigator`
 * with the ExoPlayer engine adapter; a `MediaSessionService`
 * ([AudiobookMediaService]) publishes lock-screen / system media controls
 * (the Android equivalent of iOS Now Playing) so audio continues in the
 * background while the reader view is torn down.
 */
@OptIn(ExperimentalReadiumApi::class, DelicateReadiumApi::class)
object AudiobookSession {

  private const val TAG = "AudiobookSession"

  /**
   * Boundary slack, mirroring iOS's `+ 0.25` guards on chapter comparisons
   * (:937, :951, :954, :960). A position that lands a fraction of a second past
   * a chapter start should still count as being in that chapter.
   */
  private const val CHAPTER_EPSILON = 0.25

  /**
   * How far into a chapter "previous" restarts it instead of stepping back a
   * chapter, mirroring iOS `currentPosition - current.time > 3` (:951).
   */
  private const val RESTART_CHAPTER_THRESHOLD_SECONDS = 3.0

  private val mainHandler = Handler(Looper.getMainLooper())
  private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  private val _state = MutableStateFlow(AudiobookSessionState())
  val state: StateFlow<AudiobookSessionState> = _state.asStateFlow()

  private var readerService: ReaderService? = null
  private var engineProvider: ExoPlayerEngineProvider? = null

  private var publication: Publication? = null
  private var navigator: AudioNavigator<*, *>? = null
  private var mediaPlayer: Player? = null

  /**
   * Chapter start times in absolute seconds, derived from the publication's
   * table of contents. Mirrors iOS `flattenChapters` +
   * `absoluteTime(forHref:)`
   * (ios/Reader/Audiobook/AudiobookViewController.swift:615-628, :970-972).
   *
   * A publication whose TOC does not resolve against the reading order yields an
   * empty list, and [goForward]/[goBackward] fall back to reading-order items.
   */
  private var chapters: List<Double> = emptyList()

  /** Absolute start time of each reading-order item, in seconds. */
  private var itemStartOffsets: List<Double> = emptyList()
  private var totalDuration: Double = 0.0

  /**
   * Bookmarks for the active book, keyed by their host-assigned id.
   *
   * iOS keeps its bookmarks inside `AudiobookViewController` because that view
   * owns the bookmark UI. Android has no native audiobook UI — hosts render
   * their own — so the session owns the list and publishes changes through
   * [onBookmarkChange]. Both platforms now expose the same imperative methods.
   */
  private val bookmarks = LinkedHashMap<String, AudiobookBookmark>()
  private val bookmarkListenerLock = Any()
  private var bookmarkListener: ((type: String, bookmark: AudiobookBookmark) -> Unit)? = null

  var fileURL: String? = null
    private set

  private var observeJob: Job? = null
  private var sleepJob: Job? = null
  private var mediaServiceStarted = false

  @Volatile
  private var mediaSession: androidx.media3.session.MediaSession? = null

  private fun context(): ReactApplicationContext =
    NitroModules.applicationContext
      ?: error("NitroModules.applicationContext is not available yet.")

  private fun onMain(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
  }

  /**
   * Structured trace of the open path, so a slow or failed open names the phase
   * it stalled in instead of surfacing only as a host-side timeout. The open
   * crosses several unbounded-looking boundaries (manifest fetch, per-item
   * duration resolution, playlist metadata awaiting cover art), and guessing
   * which one is slow costs more than logging them.
   */
  private fun phase(name: String, vararg details: String) {
    val suffix = if (details.isEmpty()) "" else " " + details.joinToString(" ")
    android.util.Log.i(TAG, "$name$suffix")
  }

  // MARK: - Opening

  /**
   * Headless open (JS `ReadiumAudio.open`). Retrieves and parses the
   * publication, then adopts it into playback.
   */
  fun open(fileUrl: String, initialLocator: Locator?) = onMain {
    if (fileURL == fileUrl && navigator != null) {
      return@onMain
    }
    emitLoading(fileUrl)
    mainScope.launch {
      phase("open:start")
      val publication = service().retrievePublication(fileUrl)
      if (publication == null) {
        phase("open:publication", "null")
        if (fileURL == fileUrl) {
          emitError("Failed to open audiobook.")
        }
        return@launch
      }
      phase(
        "open:publication",
        "readingOrder=${publication.readingOrder.size}",
        "manifestDurationSeconds=${publication.metadata.duration}",
        "linkDurationSeconds=${publication.readingOrder.map { it.duration }}"
      )
      attachInternal(publication, fileUrl, initialLocator)
    }
  }

  /**
   * View-path adoption: the visual host already retrieved the publication.
   * Idempotent — re-hosting the active book reuses the running navigator so
   * playback survives reader close/reopen.
   */
  fun adopt(publication: Publication, fileUrl: String, initialLocator: Locator?) = onMain {
    if (fileURL == fileUrl && navigator != null) return@onMain
    attachInternal(publication, fileUrl, initialLocator)
  }

  private fun attachInternal(publication: Publication, fileUrl: String, initialLocator: Locator?) {
    releaseNavigator()

    this.publication = publication
    this.fileURL = fileUrl
    itemStartOffsets = emptyList()
    chapters = emptyList()
    totalDuration = 0.0
    _state.value = AudiobookSessionState(status = AudiobookStatus.LOADING)

    mainScope.launch {
      val factory = AudioNavigatorFactory(
        publication,
        engineProvider()
      ) ?: run {
        emitError("The publication is not an audiobook.")
        return@launch
      }

      // createNavigator must run on the main thread. It calls
      // AudioEngineProvider.createEngine, which reaches
      // ExoPlayer.setMediaItems, and ExoPlayer verifies its application thread
      // on every call — running it on a worker throws
      // "Player is accessed on the wrong thread. Expected thread: 'main'".
      //
      // The phase logs around it are not noise. This call resolves a duration
      // for every reading-order item, and where the manifest supplies none it
      // opens the resource and runs MetadataRetriever over it
      // (AudioNavigatorFactory.duration, :88-99) — and building the playlist
      // metadata awaits cover art. Both are unbounded from the caller's point
      // of view, so which one is slow is not something to guess at.
      phase("createNavigator:start")
      val result = factory.createNavigator(initialLocator)
      phase("createNavigator:done")
      val createdNavigator = result.getOrNull()
      if (createdNavigator == null) {
        val message = (result as? Try.Failure)?.value?.message ?: "Failed to initialize playback."
        emitError(message)
        return@launch
      }

      navigator = createdNavigator
      mediaPlayer = createdNavigator.asMedia3Player().also { player ->
        updateState { it.copy(rate = player.playbackParameters.speed.toDouble()) }
      }
      phase("timeline:start")
      computeTimeline(createdNavigator)
      phase("timeline:done", "items=${itemStartOffsets.size}", "chapters=${chapters.size}")
      observe(createdNavigator)
      // Seeds the now-playing entry for the newly attached publication so the
      // first lock-screen render is not empty while the host catches up. Touches
      // the player, so it has to stay on the main thread too.
      applyNowPlayingMetadata()
      emit(status = AudiobookStatus.READY)
      phase("ready")
    }
  }

  // MARK: - Transport controls

  fun play() = onMain {
    val player = mediaPlayer ?: return@onMain
    ensureMediaServiceStarted()
    player.play()
  }

  fun pause() = onMain {
    mediaPlayer?.pause()
  }

  /** Absolute-time seek across the chapter timeline, in seconds. */
  fun seekTo(position: Double) = onMain { seekToInternal(position) }

  private fun seekToInternal(position: Double) {
    val nav = navigator ?: return
    val index = itemIndexForAbsolutePosition(position)
    val localOffset = (position - itemStartOffsets.getOrElse(index) { 0.0 })
      .coerceAtLeast(0.0).seconds
    nav.skipTo(index, localOffset)
  }

  fun goForward() = onMain {
    val nav = navigator ?: return@onMain
    val next = chapters.firstOrNull { it > _state.value.position + CHAPTER_EPSILON }
    if (next == null) {
      // No chapter boundary ahead: keep the reading-order behaviour so the
      // control still does something on a publication with a flat TOC.
      nav.skipForward()
      return@onMain
    }
    seekToInternal(next)
  }

  fun goBackward() = onMain {
    val nav = navigator ?: return@onMain
    if (chapters.isEmpty()) {
      nav.skipBackward()
      return@onMain
    }
    val position = _state.value.position
    val current = chapters.lastOrNull { it <= position + CHAPTER_EPSILON }
    if (current == null) {
      seekToInternal(0.0)
      return@onMain
    }
    // Mirrors iOS seekToPreviousChapter (:938-957): more than 3s into a chapter
    // restarts it, otherwise step back to the previous chapter.
    val target = if (position - current > RESTART_CHAPTER_THRESHOLD_SECONDS) {
      current
    } else {
      chapters.lastOrNull { it < current - CHAPTER_EPSILON } ?: 0.0
    }
    seekToInternal(target)
  }

  fun setPlaybackRate(rate: Double) = onMain {
    val player = mediaPlayer ?: return@onMain
    player.setPlaybackSpeed(rate.toFloat())
    updateState { it.copy(rate = rate) }
  }

  fun setVolume(volume: Double) = onMain {
    val player = mediaPlayer ?: return@onMain
    player.volume = volume.toFloat().coerceIn(0f, 1f)
    updateState { it.copy(volume = volume.coerceIn(0.0, 1.0)) }
  }

  /**
   * Timed sleep timer; `null` cancels. Pauses playback when it elapses.
   * (iOS's end-of-chapter variant is not part of the JS API surface.)
   */
  fun setSleepTimer(seconds: Double?) = onMain {
    sleepJob?.cancel()
    sleepJob = null
    if (seconds == null || seconds <= 0.0) {
      updateState { it.copy(sleepTimerRemaining = null) }
      return@onMain
    }
    val deadline = System.currentTimeMillis() + (seconds * 1000).toLong()
    sleepJob = mainScope.launch {
      while (isActive) {
        val remaining = (deadline - System.currentTimeMillis()) / 1000.0
        if (remaining <= 0.0) {
          pause()
          updateState { it.copy(sleepTimerRemaining = null) }
          break
        }
        updateState { it.copy(sleepTimerRemaining = remaining) }
        delay(500)
      }
    }
  }

  /** Full teardown back to idle, mirroring iOS `AudiobookSession.close`. */
  fun close() = onMain { teardown() }

  /**
   * Drops the running session so the next open starts from scratch. Used by
   * `ReadiumView` when the host passes `reopenActiveAudiobook: false` — iOS
   * treats that as "do not resume the active book"
   * (ios/HybridReadiumView.swift:167-171), and previously Android had no way to
   * express it.
   */
  fun reset() = onMain { teardown() }

  private fun teardown() {
    mediaPlayer?.pause()
    stopMediaService()
    releaseNavigator()
    publication = null
    fileURL = null
    itemStartOffsets = emptyList()
    chapters = emptyList()
    totalDuration = 0.0
    synchronized(bookmarks) { bookmarks.clear() }
    sleepJob?.cancel()
    sleepJob = null
    _state.value = AudiobookSessionState()
  }

  // MARK: - Bookmarks

  /** Registers the host's bookmark-change listener; returns a detach function. */
  fun setBookmarkListener(listener: ((type: String, bookmark: AudiobookBookmark) -> Unit)?) {
    synchronized(bookmarkListenerLock) { bookmarkListener = listener }
  }

  /**
   * Replaces the bookmark list, emitting `update` for each so a host that
   * round-trips its own persisted bookmarks sees them acknowledged.
   */
  fun setBookmarks(values: List<AudiobookBookmark>) = onMain {
    val changed = synchronized(bookmarks) {
      bookmarks.clear()
      values.forEach { bookmarks[it.id] = it }
      values.toList()
    }
    changed.forEach { emitBookmarkChange("update", it) }
  }

  fun addBookmark(id: String, position: Double, note: String?) = onMain {
    val locator = locatorForAbsolutePosition(position)
    val bookmark = AudiobookBookmark(
      id = id,
      locator = locator,
      position = position,
      note = note
    )
    val existing = synchronized(bookmarks) {
      val previous = bookmarks.put(id, bookmark)
      if (previous == null) "add" else "update"
    }
    emitBookmarkChange(existing, bookmark)
  }

  fun updateBookmark(id: String, note: String?) = onMain {
    val bookmark = synchronized(bookmarks) {
      val previous = bookmarks[id] ?: return@onMain
      val updated = previous.copy(note = note)
      bookmarks[id] = updated
      updated
    }
    emitBookmarkChange("update", bookmark)
  }

  fun removeBookmark(id: String) = onMain {
    val bookmark = synchronized(bookmarks) { bookmarks.remove(id) } ?: return@onMain
    emitBookmarkChange("remove", bookmark)
  }

  private fun emitBookmarkChange(type: String, bookmark: AudiobookBookmark) {
    val listener = synchronized(bookmarkListenerLock) { bookmarkListener } ?: return
    listener(type, bookmark)
  }

  /**
   * Builds a Readium locator for an absolute chapter-timeline position.
   * Mirrors iOS `locator(forAbsoluteTime:)` (:746-763): the reading-order item
   * containing the position, with the local offset carried in a `t=` fragment.
   */
  private fun locatorForAbsolutePosition(position: Double): Locator {
    val pub = publication
    val links = pub?.readingOrder.orEmpty()
    val index = itemIndexForAbsolutePosition(position)
    val link = links.getOrNull(index)
    val offset = (position - itemStartOffsets.getOrElse(index) { 0.0 }).coerceAtLeast(0.0)
    val href = ReadiumUrl(
      com.reactnativereadium.utils.normalizeHref(link?.href?.toString().orEmpty()).resourcePath
    ) ?: ReadiumUrl("about:blank")!!
    return Locator(
      href = href,
      mediaType = link?.mediaType ?: MediaType("audio/*")!!,
      title = link?.title,
      locations = Locator.Locations(fragments = listOf("t=$offset"))
    )
  }

  // MARK: - Media service bridge

  /** The Media3 player backing the active session, for [AudiobookMediaService]. */
  fun media3Player(): Player? = mediaPlayer

  /**
   * The live `MediaSession` wrapper, published by [AudiobookMediaService]. Held
   * here so the service does not have to be reached back into when the now
   * playing master switch changes.
   */
  fun attachMediaSession(session: androidx.media3.session.MediaSession?) {
    mediaSession = session
  }

  // MARK: - Now Playing

  /**
   * Master switch for library-published now-playing info, mirroring iOS
   * `AudiobookViewController.isNowPlayingInfoEnabled`
   * (ios/Reader/Audiobook/AudiobookViewController.swift:36-41).
   *
   * On Android this decides whether the `MediaSessionService` runs, i.e. whether
   * a media notification and lock-screen entry exist at all. The two platforms
   * differ in one important way: iOS's `MPNowPlayingInfoCenter` is passive, so
   * turning it off costs a host nothing, whereas on Android the same session
   * *is* the background-playback mechanism — turning it off means no
   * lock-screen transport controls. A host that disables it is taking ownership
   * of the system media entry.
   */
  @Volatile
  var isNowPlayingInfoEnabled: Boolean = true
    set(value) {
      field = value
      if (value) {
        if (_state.value.status == AudiobookStatus.PLAYING) ensureMediaServiceStarted()
        applyNowPlayingMetadata()
      } else {
        stopMediaService()
        applyNowPlayingMetadata()
      }
    }

  /**
   * Whether the descriptive fields (title, album, artist, artwork) are
   * published, mirroring iOS `isNowPlayingMetadataEnabled` (:43-48, :852-874).
   */
  @Volatile
  var isNowPlayingMetadataEnabled: Boolean = true
    set(value) {
      field = value
      applyNowPlayingMetadata()
    }

  /**
   * Host-supplied now-playing fields, overriding the publication's own metadata.
   * Mirrors iOS, where the host writes `MPNowPlayingInfoCenter` directly.
   */
  @Volatile
  private var hostNowPlaying: NowPlayingMetadata? = null

  /**
   * Java-facing setter for [isNowPlayingInfoEnabled] semantics; see the spec's
   * `setNowPlayingMetadata` for why the host override exists.
   */
  fun setNowPlayingMetadata(metadata: NowPlayingMetadata?) {
    hostNowPlaying = metadata
    applyNowPlayingMetadata()
  }

  /**
   * Pushes the current now-playing fields onto the player.
   *
   * Media3 1.x has no `MediaSession.setMediaMetadata`; the lock screen and media
   * notification read the *player's* playlist metadata. So this sets
   * `playlistMetadata`, which is the one live-update lever Android exposes, and
   * merges the host override on top of the publication's own values.
   *
   * Always hops to the main thread. `Player` methods are thread-checked against
   * the looper the player was built on, and this is reachable from JS — which is
   * not the main thread — through the now-playing setters.
   */
  private fun applyNowPlayingMetadata() {
    onMain { applyNowPlayingMetadataOnMain() }
  }

  private fun applyNowPlayingMetadataOnMain() {
    val player = mediaPlayer ?: return
    val pub = publication ?: return
    if (!isNowPlayingInfoEnabled || !isNowPlayingMetadataEnabled) {
      player.setPlaylistMetadata(androidx.media3.common.MediaMetadata.Builder().build())
      return
    }

    val host = hostNowPlaying
    val builder = androidx.media3.common.MediaMetadata.Builder()
      .setMediaType(androidx.media3.common.MediaMetadata.MEDIA_TYPE_AUDIO_BOOK_CHAPTER)
      .setIsBrowsable(false)
      .setIsPlayable(true)

    val title = host?.title?.takeIf { it.isNotBlank() } ?: pub.metadata.title
    title?.let { builder.setTitle(it) }
    builder.setAlbumTitle(
      host?.albumTitle?.takeIf { it.isNotBlank() } ?: pub.metadata.title
    )
    builder.setGenre("Audiobook")

    val artist = host?.artist?.takeIf { it.isNotBlank() }
      ?: pub.metadata.authors.joinToString(", ") { it.name }.takeIf { it.isNotBlank() }
    artist?.let { builder.setArtist(it) }
    pub.metadata.narrators
      .joinToString(", ") { it.name }
      .takeIf { it.isNotBlank() }
      ?.let { builder.setComposer(it) }

    host?.artworkUrl?.takeIf { it.isNotBlank() }?.let { url ->
      runCatching { android.net.Uri.parse(url) }.getOrNull()?.let { builder.setArtworkUri(it) }
    }
    // `defaultPlaybackRate` has no MediaMetadata equivalent. Android's system
    // media entry derives the rate from the player, which is what
    // `AudiobookPlaybackState.rate` already reports to the host, so the field is
    // accepted and ignored here rather than silently misrepresented.

    runCatching { player.setPlaylistMetadata(builder.build()) }
  }

  /** Host-supplied now-playing fields; mirrors the spec's `NowPlayingMetadata`. */
  data class NowPlayingMetadata(
    val title: String? = null,
    val artist: String? = null,
    val albumTitle: String? = null,
    val artworkUrl: String? = null,
    val defaultPlaybackRate: Double? = null
  )

  private fun ensureMediaServiceStarted() {
    try {
      // Idempotent: (re)starting the service lets it re-bind to the current
      // player when the session adopted a different book.
      context().startService(Intent(context(), AudiobookMediaService::class.java))
      mediaServiceStarted = true
    } catch (e: Exception) {
      RNLog.w(context(), "AudiobookMediaService failed to start: ${e.message}")
    }
  }

  private fun stopMediaService() {
    if (!mediaServiceStarted) return
    mediaServiceStarted = false
    try {
      context().stopService(Intent(context(), AudiobookMediaService::class.java))
    } catch (_: Exception) {
    }
  }

  // MARK: - Internals

  private fun service(): ReaderService {
    if (readerService == null) {
      readerService = ReaderService(context())
    }
    return readerService!!
  }

  private fun engineProvider(): ExoPlayerEngineProvider {
    if (engineProvider == null) {
      // Baseline descriptive metadata comes from the toolkit's
      // `MediaMetadataProvider`, which bakes it into the media items at
      // engine-build time. A host override and the two enable flags are layered
      // on afterwards by [applyNowPlayingMetadata], which writes the player's
      // playlist metadata — the one live lever Media3 exposes.
      engineProvider = ExoPlayerEngineProvider(
        context().applicationContext as android.app.Application,
        DefaultMediaMetadataProvider()
      )
    }
    return engineProvider!!
  }

  private fun emitLoading(fileUrl: String) {
    releaseNavigator()
    sleepJob?.cancel()
    sleepJob = null
    fileURL = fileUrl
  }

  private fun releaseNavigator() {
    observeJob?.cancel()
    observeJob = null
    navigator?.close()
    navigator = null
    mediaPlayer = null
    mediaServiceStarted = false
    // The service owns the session wrapper; drop our reference so a stale
    // session cannot keep receiving metadata for a publication we just closed.
    mediaSession = null
  }

  private fun computeTimeline(nav: AudioNavigator<*, *>) {
    var accumulator = 0.0
    itemStartOffsets = nav.readingOrder.items.map { item ->
      val start = accumulator
      accumulator += (item.duration?.inWholeSeconds ?: 0L).toDouble()
      start
    }
    totalDuration = nav.readingOrder.duration?.inWholeSeconds?.toDouble() ?: accumulator
    chapters = computeChapterTimes()
  }

  /**
   * Flattens the publication TOC into absolute chapter start times.
   *
   * A TOC entry's absolute time is the start of the reading-order item it
   * points at, plus the media fragment offset (`#t=`) if it carries one. TOC
   * hrefs are routinely written as root-relative (`/chapter1.mp3`) or as a bare
   * filename, so each is tried against every alias the item is indexed under,
   * mirroring iOS `resourceKeys(for:)` (:992-1000). Entries that resolve to
   * nothing are dropped rather than collapsed onto 0.
   */
  private fun computeChapterTimes(): List<Double> {
    val pub = publication ?: return emptyList()

    val offsetsByKey = HashMap<String, Double>()
    pub.readingOrder.forEachIndexed { index, link ->
      val start = itemStartOffsets.getOrElse(index) { 0.0 }
      resourceKeys(link.href.toString()).forEach { key ->
        offsetsByKey.putIfAbsent(key, start)
      }
    }
    if (offsetsByKey.isEmpty()) return emptyList()

    val times = mutableListOf<Double>()
    fun walk(links: List<org.readium.r2.shared.publication.Link>) {
      for (link in links) {
        val normalized = com.reactnativereadium.utils.normalizeHref(link.href.toString())
        val offset = resourceKeys(normalized.resourcePath)
          .firstNotNullOfOrNull { offsetsByKey[it] }
        if (offset != null) {
          times += offset + fragmentTime(normalized.fragment)
        }
        walk(link.children)
      }
    }
    walk(pub.tableOfContents)
    return times.sorted()
  }

  /**
   * Lookup aliases for a media resource. Mirrors iOS `resourceKeys(for:)`: the
   * fragment-free path, the path as authored, and the bare filename, since a
   * TOC may reference any of them.
   */
  private fun resourceKeys(path: String): List<String> {
    val keys = LinkedHashSet<String>()
    keys.add(path)
    keys.add(path.substringBefore('#'))
    path.substringAfterLast('/').takeIf { it.isNotEmpty() }?.let { keys.add(it) }
    return keys.toList()
  }

  /** Parses a Readium media-fragment offset (`t=12.5`, `t=12,5` tolerated). */
  private fun fragmentTime(fragment: String?): Double {
    if (fragment == null || !fragment.startsWith("t=")) return 0.0
    val value = fragment.removePrefix("t=").split(',').firstOrNull() ?: return 0.0
    return value.toDoubleOrNull() ?: 0.0
  }

  private fun itemIndexForAbsolutePosition(position: Double): Int {
    if (itemStartOffsets.isEmpty()) return 0
    var index = 0
    for (i in itemStartOffsets.indices) {
      if (position >= itemStartOffsets[i]) index = i else break
    }
    return index
  }

  private fun observe(nav: AudioNavigator<*, *>) {
    observeJob = mainScope.launch {
      nav.playback.collect { playback ->
        val pub = publication
        val offsets = itemStartOffsets
        val index = playback.index.coerceIn(0, offsets.size - 1)
        val absolutePosition = offsets.getOrElse(index) { 0.0 } + playback.offset.inWholeSeconds

        val status = when {
          playback.state is AudioNavigator.State.Failure<*> -> AudiobookStatus.ERROR
          playback.state is AudioNavigator.State.Ended -> AudiobookStatus.ENDED
          playback.playWhenReady -> AudiobookStatus.PLAYING
          else -> AudiobookStatus.PAUSED
        }

        val error = (playback.state as? AudioNavigator.State.Failure<*>)?.error?.message

        updateState { current ->
          current.copy(
            status = status,
            publication = pub,
            error = error,
            position = absolutePosition,
            duration = totalDuration,
            rate = mediaPlayer?.playbackParameters?.speed?.toDouble() ?: current.rate,
            volume = mediaPlayer?.volume?.toDouble() ?: current.volume,
            currentHref = nav.readingOrder.items.getOrNull(index)?.href?.toString(),
            currentTitle = pub?.readingOrder?.getOrNull(index)?.title
              ?: current.currentTitle
          )
        }
      }
    }
  }

  private fun emit(
    status: AudiobookStatus,
    error: String? = null
  ) {
    val attachedPublication = publication
    updateState { current ->
      val idle = status == AudiobookStatus.IDLE
      current.copy(
        status = status,
        publication = if (idle) null else attachedPublication,
        error = error,
        position = if (idle) 0.0 else current.position,
        duration = if (idle) 0.0 else current.duration,
        currentHref = if (idle) null else current.currentHref,
        currentTitle = if (idle) null else current.currentTitle,
        sleepTimerRemaining = if (idle) null else current.sleepTimerRemaining
      )
    }
  }

  private fun emitError(message: String) {
    emit(status = AudiobookStatus.ERROR, error = message)
  }

  private fun updateState(transform: (AudiobookSessionState) -> AudiobookSessionState) {
    _state.value = transform(_state.value)
  }
}
