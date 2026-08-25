package com.reactnativereadium.audio

import android.content.Intent
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Foreground `MediaSessionService` publishing the audiobook's Media3 player
 * as a system media session — the Android equivalent of iOS Now Playing /
 * lock-screen controls (MPRemoteCommandCenter + MPNowPlayingInfoCenter).
 *
 * The player itself is owned by [AudiobookSession]; the service only wraps it
 * in a session and lets Media3 render the media notification, handle
 * background playback, and route system media commands.
 */
class AudiobookMediaService : MediaSessionService() {

  private var mediaSession: MediaSession? = null

  override fun onCreate() {
    super.onCreate()
    bindToCurrentPlayer()
  }

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    // The session may have adopted a different book since the last start.
    bindToCurrentPlayer()
    return super.onStartCommand(intent, flags, startId)
  }

  override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? {
    bindToCurrentPlayer()
    return mediaSession
  }

  private fun bindToCurrentPlayer() {
    val player = AudiobookSession.media3Player()
    val current = mediaSession
    when {
      player == null -> Unit
      current != null && current.player === player -> Unit
      else -> {
        current?.release()
        mediaSession = MediaSession.Builder(this, player).build()
      }
    }
  }

  override fun onTaskRemoved(rootIntent: Intent?) {
    val session = mediaSession
    if (session == null || !session.player.playWhenReady) {
      stopSelf()
    }
  }

  override fun onDestroy() {
    // The player is owned by AudiobookSession — release only the wrapper.
    mediaSession?.release()
    mediaSession = null
    super.onDestroy()
  }
}
