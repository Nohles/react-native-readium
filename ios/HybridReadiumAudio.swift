import Foundation

final class HybridReadiumAudio: HybridReadiumAudioSpec {
  var onStateChange: ((AudiobookSessionState) -> Void)? {
    didSet {
      AudiobookSession.shared.onStateChange = onStateChange
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
  func setSleepTimer(seconds: Double?) throws { AudiobookSession.shared.setSleepTimer(seconds) }
  func close() throws { AudiobookSession.shared.close() }
}
