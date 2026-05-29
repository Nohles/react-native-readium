import Foundation
import ReadiumShared
import UIKit

/// Owns audiobook playback independently from the visual reader host.
final class AudiobookSession {
  static let shared = AudiobookSession()

  var onStateChange: ((AudiobookSessionState) -> Void)? {
    didSet { onStateChange?(lastState) }
  }

  private var readerService = ReaderService()
  private(set) var controller: AudiobookViewController?
  private(set) var fileURL: String?
  private var metadata: PublicationMetadata?
  private var lastState = AudiobookSessionState(
    status: .idle,
    publication: nil,
    position: 0,
    duration: 0,
    rate: 1,
    volume: 1,
    currentHref: nil,
    currentTitle: nil,
    sleepTimerRemaining: nil,
    error: nil
  )

  private init() {}

  func open(file: ReadiumFile) {
    if fileURL == file.url, controller != nil {
      onStateChange?(lastState)
      return
    }

    close()
    fileURL = file.url
    emit(status: .loading)

    let initialLocation = file.initialLocation.flatMap { nitroLocatorToReadium($0) }
    let sender = UIApplication.shared.delegate?.window??.rootViewController
    readerService.buildViewController(
      url: file.url,
      bookId: file.url,
      locator: initialLocation,
      selectionActions: nil,
      sender: sender,
      completion: { [weak self] host in
        guard let self else { return }
        guard let audiobook = host as? AudiobookViewController else {
          self.emit(status: .error, error: "The publication is not an audiobook.")
          return
        }
        self.adopt(audiobook, url: file.url)
        audiobook.loadViewIfNeeded()
        self.emit(status: .ready)
      }
    )
  }

  func host(for url: String) -> AudiobookViewController? {
    fileURL == url ? controller : nil
  }

  func activeHost() -> AudiobookViewController? {
    controller
  }

  func adopt(_ host: AudiobookViewController, url: String) {
    if controller !== host {
      controller?.pause()
      controller = host
      fileURL = url
    }
    metadata = readiumMetadataToNitro(host.publication.metadata)
    host.onPlaybackStateChange = { [weak self] state in
      self?.receivePlayback(state)
    }
    if lastState.status == .idle || lastState.status == .loading {
      emit(status: .ready)
    }
  }

  func play() { controller?.play() }
  func pause() { controller?.pause() }
  func seekTo(_ position: Double) { controller?.seekTo(position: position) }
  func setPlaybackRate(_ rate: Double) { controller?.setPlaybackRate(rate) }
  func setVolume(_ volume: Double) { controller?.setVolume(volume) }
  func setSleepTimer(_ seconds: Double?) { controller?.setSleepTimer(seconds: seconds) }

  func goForward() {
    Task { @MainActor in await controller?.goForward() }
  }

  func goBackward() {
    Task { @MainActor in await controller?.goBackward() }
  }

  func close() {
    controller?.pause()
    controller = nil
    fileURL = nil
    metadata = nil
    emit(status: .idle)
  }

  func receivePlayback(_ playback: AudiobookPlaybackState) {
    lastState = AudiobookSessionState(
      status: playback.isPlaying ? .playing : .paused,
      publication: metadata,
      position: playback.position,
      duration: playback.duration,
      rate: playback.rate,
      volume: playback.volume,
      currentHref: playback.currentHref,
      currentTitle: playback.currentTitle,
      sleepTimerRemaining: playback.sleepTimerRemaining,
      error: nil
    )
    onStateChange?(lastState)
  }

  private func emit(status: AudiobookSessionStatus, error: String? = nil) {
    lastState = AudiobookSessionState(
      status: status,
      publication: metadata,
      position: status == .idle ? 0 : lastState.position,
      duration: status == .idle ? 0 : lastState.duration,
      rate: lastState.rate,
      volume: lastState.volume,
      currentHref: status == .idle ? nil : lastState.currentHref,
      currentTitle: status == .idle ? nil : lastState.currentTitle,
      sleepTimerRemaining: status == .idle ? nil : lastState.sleepTimerRemaining,
      error: error
    )
    onStateChange?(lastState)
  }
}
