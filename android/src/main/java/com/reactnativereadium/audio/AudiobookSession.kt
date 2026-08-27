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
import org.readium.r2.shared.DelicateReadiumApi
import org.readium.r2.shared.ExperimentalReadiumApi
import org.readium.r2.shared.publication.Locator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Try
import kotlin.time.Duration.Companion.seconds

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

  private val mainHandler = Handler(Looper.getMainLooper())
  private val mainScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

  private val _state = MutableStateFlow(AudiobookSessionState())
  val state: StateFlow<AudiobookSessionState> = _state.asStateFlow()

  private var readerService: ReaderService? = null
  private var engineProvider: ExoPlayerEngineProvider? = null

  private var publication: Publication? = null
  private var navigator: AudioNavigator<*, *>? = null
  private var mediaPlayer: Player? = null

  /** Cumulative absolute-time offset of each reading-order item, in seconds. */
  private var itemStartOffsets: List<Double> = emptyList()
  private var totalDuration: Double = 0.0

  var fileURL: String? = null
    private set

  private var observeJob: Job? = null
  private var sleepJob: Job? = null
  private var mediaServiceStarted = false

  private fun context(): ReactApplicationContext =
    NitroModules.applicationContext
      ?: error("NitroModules.applicationContext is not available yet.")

  private fun onMain(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
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
      val publication = service().retrievePublication(fileUrl)
      if (publication == null) {
        if (fileURL == fileUrl) {
          emitError("Failed to open audiobook.")
        }
        return@launch
      }
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

      val result = factory.createNavigator(initialLocator)
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
      computeTimeline(createdNavigator)
      observe(createdNavigator)
      emit(status = AudiobookStatus.READY)
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
  fun seekTo(position: Double) = onMain {
    val nav = navigator ?: return@onMain
    val index = itemIndexForAbsolutePosition(position)
    val localOffset = (position - itemStartOffsets.getOrElse(index) { 0.0 })
      .coerceAtLeast(0.0).seconds
    nav.skipTo(index, localOffset)
  }

  fun goForward() = onMain { navigator?.skipForward() }
  fun goBackward() = onMain { navigator?.skipBackward() }

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
  fun close() = onMain {
    mediaPlayer?.pause()
    stopMediaService()
    releaseNavigator()
    publication = null
    fileURL = null
    itemStartOffsets = emptyList()
    totalDuration = 0.0
    sleepJob?.cancel()
    sleepJob = null
    _state.value = AudiobookSessionState()
  }

  // MARK: - Media service bridge

  /** The Media3 player backing the active session, for [AudiobookMediaService]. */
  fun media3Player(): Player? = mediaPlayer

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
      engineProvider = ExoPlayerEngineProvider(context().applicationContext as android.app.Application)
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
  }

  private fun computeTimeline(nav: AudioNavigator<*, *>) {
    var accumulator = 0.0
    itemStartOffsets = nav.readingOrder.items.map { item ->
      val start = accumulator
      accumulator += (item.duration?.inWholeSeconds ?: 0L).toDouble()
      start
    }
    totalDuration = nav.readingOrder.duration?.inWholeSeconds?.toDouble() ?: accumulator
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
