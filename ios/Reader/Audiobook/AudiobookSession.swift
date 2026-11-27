import Foundation
import ReadiumShared
import UIKit

/// Owns audiobook playback independently from the visual reader host.
final class AudiobookSession {
  static let shared = AudiobookSession()

  var onStateChange: ((AudiobookSessionState) -> Void)? {
    didSet { onStateChange?(lastState) }
  }

  /// Bookmark mutations from either the native UI or a headless host. Android
  /// has no native audiobook UI, so this is the only path a bookmark takes
  /// there; keeping it on the session makes both platforms emit identically.
  var onBookmarkChange: ((AudiobookBookmarkChangeEvent) -> Void)?

  private var readerService = ReaderService()
  private(set) var controller: AudiobookViewController?
  private(set) var fileURL: String?
  private var metadata: PublicationMetadata?
  private var isNowPlayingInfoEnabled = true
  private var isNowPlayingMetadataEnabled = true
  private var hostNowPlayingMetadata: NowPlayingMetadata?
  /// True from `open` until the opening seek has finished. Playback events
  /// arrive before then (at 0:00, before the initial location is applied), and
  /// reporting them as `paused` would tell the host the book is ready at the
  /// wrong place.
  private var isOpening = false
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
    isBuffering: nil,
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
    isOpening = true
    emit(status: .loading)

    let initialLocation = file.initialLocation.flatMap { nitroLocatorToReadium($0) }
    let sender = UIApplication.shared.delegate?.window??.rootViewController
    readerService.buildViewController(
      url: file.url,
      bookId: file.url,
      locator: initialLocation,
      selectionActions: nil,
      customFonts: nil,
      sender: sender,
      completion: { [weak self] host in
        guard let self else { return }
        guard let audiobook = host as? AudiobookViewController else {
          self.isOpening = false
          self.emit(status: .error, error: "The publication is not an audiobook.")
          return
        }
        self.adopt(audiobook, url: file.url, emitReady: false)
        audiobook.loadViewIfNeeded()
        Task { @MainActor [weak self, weak audiobook] in
          guard let self, let audiobook else { return }
          let restored = await audiobook.preparePlayback()
          guard self.controller === audiobook, self.fileURL == file.url else { return }
          if !restored {
            // The host compares the reported position with the place it asked
            // for and decides what to do; it is not an open failure.
            NSLog("[ReadiumAudio] initial location could not be restored for \(file.url)")
          }
          self.isOpening = false
          self.emit(status: .ready)
        }
      },
      onFailure: { [weak self] error in
        guard let self, self.fileURL == file.url else { return }
        self.isOpening = false
        self.emit(status: .error, error: error.localizedDescription)
      }
    )
  }

  func host(for url: String) -> AudiobookViewController? {
    fileURL == url ? controller : nil
  }

  func activeHost() -> AudiobookViewController? {
    controller
  }

  func adopt(_ host: AudiobookViewController, url: String, emitReady: Bool = true) {
    if controller !== host {
      controller?.pause()
      controller = host
      fileURL = url
    }
    metadata = readiumMetadataToNitro(host.publication.metadata)
    host.isNowPlayingInfoEnabled = isNowPlayingInfoEnabled
    host.isNowPlayingMetadataEnabled = isNowPlayingMetadataEnabled
    host.hostNowPlayingMetadata = hostNowPlayingMetadata
    host.onPlaybackStateChange = { [weak self] state in
      self?.receivePlayback(state)
    }
    host.onBookmarkChange = { [weak self] event in
      self?.onBookmarkChange?(event)
    }
    if emitReady && (lastState.status == .idle || lastState.status == .loading) {
      isOpening = false
      emit(status: .ready)
    }
  }

  func play() { controller?.play() }
  func pause() { controller?.pause() }
  func seekTo(_ position: Double) { controller?.seekTo(position: position) }
  func setPlaybackRate(_ rate: Double) { controller?.setPlaybackRate(rate) }
  func setVolume(_ volume: Double) { controller?.setVolume(volume) }
  func setNowPlayingInfoEnabled(_ enabled: Bool) {
    isNowPlayingInfoEnabled = enabled
    controller?.isNowPlayingInfoEnabled = enabled
  }
  func setNowPlayingMetadataEnabled(_ enabled: Bool) {
    isNowPlayingMetadataEnabled = enabled
    controller?.isNowPlayingMetadataEnabled = enabled
  }
  func setNowPlayingMetadata(_ metadata: NowPlayingMetadata?) {
    hostNowPlayingMetadata = metadata
    controller?.hostNowPlayingMetadata = metadata
  }
  func setSleepTimer(_ seconds: Double?) { controller?.setSleepTimer(seconds: seconds) }

  func setBookmarks(_ bookmarks: [AudiobookBookmark]) {
    Task { @MainActor in controller?.setBookmarks(bookmarks) }
  }

  func addBookmark(id: String, position: Double, note: String?) {
    Task { @MainActor in controller?.addBookmark(id: id, position: position, note: note) }
  }

  func updateBookmark(id: String, note: String?) {
    Task { @MainActor in controller?.updateBookmark(id: id, note: note) }
  }

  func removeBookmark(id: String) {
    Task { @MainActor in controller?.removeBookmark(id: id) }
  }

  func goForward() {
    Task { @MainActor in await controller?.goForward() }
  }

  func goBackward() {
    Task { @MainActor in await controller?.goBackward() }
  }

  func close() {
    isOpening = false
    controller?.pause()
    controller = nil
    fileURL = nil
    metadata = nil
    emit(status: .idle)
  }

  func receivePlayback(_ playback: AudiobookPlaybackState) {
    lastState = AudiobookSessionState(
      status: isOpening ? .loading : (playback.isPlaying ? .playing : .paused),
      publication: metadata,
      position: playback.position,
      duration: playback.duration,
      rate: playback.rate,
      volume: playback.volume,
      currentHref: playback.currentHref,
      currentTitle: playback.currentTitle,
      sleepTimerRemaining: playback.sleepTimerRemaining,
      isBuffering: isOpening ? false : playback.isBuffering,
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
      isBuffering: false,
      error: error
    )
    onStateChange?(lastState)
  }
}
