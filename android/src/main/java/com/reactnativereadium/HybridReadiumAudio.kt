package com.margelo.nitro.reactnativereadium

import com.reactnativereadium.audio.AudiobookSession
import com.reactnativereadium.utils.nitroLocatorToReadium
import com.reactnativereadium.utils.toNitroSessionState
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
  override fun setNowPlayingInfoEnabled(enabled: Boolean) = Unit
  override fun setNowPlayingMetadataEnabled(enabled: Boolean) = Unit
  override fun setSleepTimer(seconds: Double?) { AudiobookSession.setSleepTimer(seconds) }
  override fun close() { AudiobookSession.close() }
}
