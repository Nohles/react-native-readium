package com.margelo.nitro.reactnativereadium

/**
 * Audiobook playback is intentionally iOS-only until Android playback is
 * implemented with an appropriate media session and background service.
 */
class HybridReadiumAudio : HybridReadiumAudioSpec() {
  override var onStateChange: ((state: AudiobookSessionState) -> Unit)? = null

  private fun unsupported(): Nothing {
    throw UnsupportedOperationException(
      "Readium audiobook sessions are currently supported on iOS only."
    )
  }

  override fun open(file: ReadiumFile) = unsupported()
  override fun play() = unsupported()
  override fun pause() = unsupported()
  override fun seekTo(position: Double) = unsupported()
  override fun goForward() = unsupported()
  override fun goBackward() = unsupported()
  override fun setPlaybackRate(rate: Double) = unsupported()
  override fun setVolume(volume: Double) = unsupported()
  override fun setSleepTimer(seconds: Double?) = unsupported()
  override fun close() = unsupported()
}
