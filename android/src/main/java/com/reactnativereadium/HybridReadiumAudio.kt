package com.margelo.nitro.reactnativereadium

import com.reactnativereadium.audio.AudiobookSession
import com.reactnativereadium.utils.nitroBookmarkToReadium
import com.reactnativereadium.utils.nitroLocatorToReadium
import com.reactnativereadium.utils.readiumBookmarkToNitro
import com.reactnativereadium.utils.toNitroSessionState
import java.util.UUID
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * Android implementation of the `ReadiumAudio` Nitro spec. A thin delegate to
 * the persistent [AudiobookSession], mirroring iOS `HybridReadiumAudio.swift`.
 */
class HybridReadiumAudio : HybridReadiumAudioSpec() {

  private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
  private var observeJob: Job? = null

  override var onStateChange: ((state: AudiobookSessionState) -> Unit)? = null
    set(value) {
      field = value
      observeJob?.cancel()
      observeJob = null
      if (value != null) {
        // Collecting the StateFlow replays the current state immediately,
        // matching iOS `AudiobookSession.onStateChange` didSet semantics.
        observeJob = scope.launch {
          AudiobookSession.state.collect { sessionState ->
            value(sessionState.toNitroSessionState())
          }
        }
      }
    }

  override var onBookmarkChange: ((event: AudiobookBookmarkChangeEvent) -> Unit)? = null
    set(value) {
      field = value
      AudiobookSession.setBookmarkListener(
        if (value == null) {
          null
        } else { type, bookmark ->
          value(
            AudiobookBookmarkChangeEvent(
              type = type,
              bookmark = readiumBookmarkToNitro(bookmark)
            )
          )
        }
      )
    }

  override fun open(file: ReadiumFile) {
    AudiobookSession.open(
      fileUrl = file.url,
      initialLocator = file.initialLocation?.let { nitroLocatorToReadium(it) }
    )
  }

  override fun play() { AudiobookSession.play() }
  override fun pause() { AudiobookSession.pause() }
  override fun seekTo(position: Double) { AudiobookSession.seekTo(position) }
  override fun goForward() { AudiobookSession.goForward() }
  override fun goBackward() { AudiobookSession.goBackward() }
  override fun setPlaybackRate(rate: Double) { AudiobookSession.setPlaybackRate(rate) }
  override fun setVolume(volume: Double) { AudiobookSession.setVolume(volume) }
  override fun setNowPlayingInfoEnabled(enabled: Boolean) {
    AudiobookSession.isNowPlayingInfoEnabled = enabled
  }
  override fun setNowPlayingMetadataEnabled(enabled: Boolean) {
    AudiobookSession.isNowPlayingMetadataEnabled = enabled
  }
  override fun setNowPlayingMetadata(metadata: NowPlayingMetadata?) {
    AudiobookSession.setNowPlayingMetadata(
      metadata?.let {
        AudiobookSession.NowPlayingMetadata(
          title = it.title,
          artist = it.artist,
          albumTitle = it.albumTitle,
          artworkUrl = it.artworkUrl,
          defaultPlaybackRate = it.defaultPlaybackRate
        )
      }
    )
  }
  override fun setSleepTimer(seconds: Double?) { AudiobookSession.setSleepTimer(seconds) }
  override fun close() { AudiobookSession.close() }

  override fun setBookmarks(bookmarks: Array<AudiobookBookmark>) {
    AudiobookSession.setBookmarks(bookmarks.mapNotNull(::nitroBookmarkToReadium))
  }

  override fun addBookmark(position: Double, note: String?) {
    AudiobookSession.addBookmark(UUID.randomUUID().toString(), position, note)
  }

  override fun updateBookmark(id: String, note: String?) {
    AudiobookSession.updateBookmark(id, note)
  }

  override fun removeBookmark(id: String) {
    AudiobookSession.removeBookmark(id)
  }
}
