import Foundation

final class HybridReadiumAudio: HybridReadiumAudioSpec {
  var onStateChange: ((AudiobookSessionState) -> Void)? {
    didSet {
      AudiobookSession.shared.onStateChange = onStateChange
    }
  }

  var onBookmarkChange: ((AudiobookBookmarkChangeEvent) -> Void)? {
    didSet {
      AudiobookSession.shared.onBookmarkChange = onBookmarkChange
    }
  }

  func open(file: ReadiumFile) throws {
    AudiobookSession.shared.open(file: file)
  }

  func play() throws { AudiobookSession.shared.play() }
  func pause() throws { AudiobookSession.shared.pause() }
  func seekTo(position: Double) throws { AudiobookSession.shared.seekTo(position) }
  func goForward() throws { AudiobookSession.shared.goForward() }
  func goBackward() throws { AudiobookSession.shared.goBackward() }
  func setPlaybackRate(rate: Double) throws { AudiobookSession.shared.setPlaybackRate(rate) }
  func setVolume(volume: Double) throws { AudiobookSession.shared.setVolume(volume) }
  func setNowPlayingInfoEnabled(enabled: Bool) throws {
    AudiobookSession.shared.setNowPlayingInfoEnabled(enabled)
  }
  func setNowPlayingMetadataEnabled(enabled: Bool) throws {
    AudiobookSession.shared.setNowPlayingMetadataEnabled(enabled)
  }
  func setNowPlayingMetadata(metadata: NowPlayingMetadata?) throws {
    AudiobookSession.shared.setNowPlayingMetadata(metadata)
  }
  func setSleepTimer(seconds: Double?) throws { AudiobookSession.shared.setSleepTimer(seconds) }
  func setBookmarks(bookmarks: [AudiobookBookmark]) throws {
    AudiobookSession.shared.setBookmarks(bookmarks)
  }
  func addBookmark(position: Double, note: String?) throws {
    AudiobookSession.shared.addBookmark(id: UUID().uuidString, position: position, note: note)
  }
  func updateBookmark(id: String, note: String?) throws {
    AudiobookSession.shared.updateBookmark(id: id, note: note)
  }
  func removeBookmark(id: String) throws {
    AudiobookSession.shared.removeBookmark(id: id)
  }
  func close() throws { AudiobookSession.shared.close() }
}
