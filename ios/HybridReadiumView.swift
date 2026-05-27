import Combine
import Foundation
import NitroModules
import ReadiumShared
import ReadiumStreamer
import UIKit
import ReadiumNavigator

class HybridReadiumView: HybridReadiumViewSpec {

  // MARK: - HybridReadiumViewSpec conformance

  var view: UIView {
    ensureHostViewConfigured()
    return hostView
  }

  var file: ReadiumFile? = nil {
    didSet {
      guard let file = file else { return }
      ensureHostViewConfigured()
      pendingFileUrl = file.url
      pendingInitialLocation = file.initialLocation
      tryLoadBook()
    }
  }

  private func ensureHostViewConfigured() {
    guard !didConfigureHostView else { return }
    didConfigureHostView = true
    hostView.onLayoutSubviews = { [weak self] in
      self?.attemptEmbedReaderView()
    }
    hostView.onDidMoveToWindow = { [weak self] in
      self?.attemptEmbedReaderView()
      self?.retryLoadBookIfNeeded()
    }
  }

  var preferences: Preferences? = nil {
    didSet {
      updatePreferences()
    }
  }

  var decorations: [DecorationGroup]? = nil {
    didSet {
      updateDecorations()
    }
  }

  var selectionActions: [SelectionAction]? = nil {
    didSet {
      selectionActionsReceived = true
      tryLoadBook()
    }
  }

  var audiobookBookmarks: [AudiobookBookmark]? = nil {
    didSet {
      (readerHost as? AudiobookViewController)?.setBookmarks(audiobookBookmarks ?? [])
    }
  }

  var onLocationChange: ((Locator) -> Void)? = nil
  var onPublicationReady: ((PublicationReadyEvent) -> Void)? = nil
  var onDecorationActivated: ((DecorationActivatedEvent) -> Void)? = nil
  var onSelectionChange: ((SelectionEvent) -> Void)? = nil
  var onSelectionAction: ((SelectionActionEvent) -> Void)? = nil
  var onAudiobookPlaybackStateChange: ((AudiobookPlaybackState) -> Void)? = nil
  var onAudiobookBookmarkChange: ((AudiobookBookmarkChangeEvent) -> Void)? = nil

  // MARK: - Private state

  private final class ReaderHostContainerView: UIView {
    var onLayoutSubviews: (() -> Void)?
    var onDidMoveToWindow: (() -> Void)?

    override func layoutSubviews() {
      super.layoutSubviews()
      onLayoutSubviews?()
    }

    override func didMoveToWindow() {
      super.didMoveToWindow()
      onDidMoveToWindow?()
    }
  }

  private let hostView = ReaderHostContainerView()
  private var readerService = ReaderService()
  private var readerHost: ReadiumReaderHosting?
  private var subscriptions = Set<AnyCancellable>()
  private var pendingFileUrl: String?
  private var pendingInitialLocation: Locator?
  private var hasLoadedBook = false
  private var isReaderEmbedded = false
  private var hasNotifiedPublicationReady = false
  private var selectionActionsReceived = false
  private var activeDecorationGroups = Set<String>()
  private var didConfigureHostView = false

  /// Resolves the parent view controller for embedding reader children.
  /// Falls back to the app root controller when the responder chain does not
  /// include a UIViewController (common in Expo / Fabric-hosted Nitro views).
  private var parentViewController: UIViewController? {
    if let vc = sequence(first: hostView, next: { $0.next }).first(where: { $0 is UIViewController }) as? UIViewController {
      return vc
    }
    return UIApplication.shared.delegate?.window??.rootViewController
  }

  // MARK: - Book loading

  private func tryLoadBook() {
    guard let url = pendingFileUrl,
          selectionActionsReceived,
          !hasLoadedBook else {
      return
    }

    guard parentViewController != nil else {
      DispatchQueue.main.async { [weak self] in
        self?.tryLoadBook()
      }
      return
    }

    hasLoadedBook = true
    let initialLoc = pendingInitialLocation
    pendingFileUrl = nil
    pendingInitialLocation = nil

    loadBook(url: url, location: initialLoc)
  }

  private func retryLoadBookIfNeeded() {
    guard !hasLoadedBook, pendingFileUrl != nil, selectionActionsReceived else { return }
    tryLoadBook()
  }

  private func loadBook(url: String, location: Locator?) {
    guard parentViewController != nil else {
      hasLoadedBook = false
      pendingFileUrl = url
      pendingInitialLocation = location
      DispatchQueue.main.async { [weak self] in
        self?.tryLoadBook()
      }
      return
    }

    if let activeAudiobook = AudiobookSession.shared.host(for: url) {
      addViewControllerAsSubview(host: activeAudiobook)
      return
    }

    // Convert Nitro Locator directly to Readium Locator
    let readiumLocator: RLocator? = location.flatMap { nitroLocatorToReadium($0) }

    // Convert selection actions to typed array
    let actionData: [SelectionActionData]? = selectionActions?.isEmpty == false
      ? selectionActions?.map { SelectionActionData(id: $0.id, label: $0.label) }
      : nil

    readerService.buildViewController(
      url: url,
      bookId: url,
      locator: readiumLocator,
      selectionActions: actionData,
      sender: parentViewController,
      completion: { [weak self] vc in
        guard let self = self else { return }

        if let epubVC = vc as? EPUBViewController {
          epubVC.selectionActionDelegate = self
        }

        self.addViewControllerAsSubview(host: vc)
      },
      onFailure: { [weak self] error in
        let reset = {
          guard let self = self else { return }
          print("[ReadiumNative] Failed to open publication: \(error.localizedDescription)")
          self.hasLoadedBook = false
          self.pendingFileUrl = url
          self.pendingInitialLocation = location
        }
        if Thread.isMainThread {
          reset()
        } else {
          DispatchQueue.main.async(execute: reset)
        }
      }
    )
  }

  // MARK: - Preferences

  private func updatePreferences() {
    guard readerHost != nil else { return }
    guard let navigator = (readerHost as? ReaderViewController)?.navigator as? EPUBNavigatorViewController else { return }
    guard let prefs = preferences else { return }

    let epubPrefs = nitroPreferencesToEPUB(prefs)
    navigator.submitPreferences(epubPrefs)
  }

  // MARK: - Decorations

  private func updateDecorations() {
    guard readerHost != nil else { return }
    guard let navigator = (readerHost as? ReaderViewController)?.navigator as? DecorableNavigator else { return }
    guard let groups = decorations else { return }

    for group in groups {
      let readiumDecorations = group.decorations.compactMap { dec -> RDecoration? in
        return nitroDecorationToReadium(dec)
      }

      navigator.apply(decorations: readiumDecorations, in: group.name)

      if !activeDecorationGroups.contains(group.name) {
        activeDecorationGroups.insert(group.name)

        navigator.observeDecorationInteractions(inGroup: group.name) { [weak self] event in
          guard let self = self else { return }

          let decorationPayload = readiumDecorationToNitro(event.decoration, group: event.group)

          var rect: Rect?
          if let r = event.rect {
            rect = Rect(x: Double(r.origin.x), y: Double(r.origin.y), width: Double(r.size.width), height: Double(r.size.height))
          }

          var point: Point?
          if let p = event.point {
            point = Point(x: Double(p.x), y: Double(p.y))
          }

          let payload = DecorationActivatedEvent(
            decoration: decorationPayload,
            group: event.group,
            rect: rect,
            point: point
          )

          self.onDecorationActivated?(payload)
        }
      }
    }
  }

  // MARK: - Selection Actions

  private func updateSelectionActions() {
    guard let actions = selectionActions, !actions.isEmpty else { return }
    // Selection actions are applied during fragment setup
  }

  // MARK: - View lifecycle

  private func addViewControllerAsSubview(host vc: ReadiumReaderHosting) {
    attachReaderHost(vc)
    attemptEmbedReaderView()
  }

  private func attachReaderHost(_ vc: ReadiumReaderHosting) {
    if readerHost === vc {
      return
    }

    detachEmbeddedReaderView()

    vc.publisher.sink(receiveValue: { [weak self] locator in
      guard let self = self else { return }
      let nitroLocator = readiumLocatorToNitro(locator)
      self.onLocationChange?(nitroLocator)
    })
    .store(in: &subscriptions)

    readerHost = vc

    if let audiobookVC = vc as? AudiobookViewController {
      AudiobookSession.shared.adopt(audiobookVC, url: audiobookVC.bookId)
      audiobookVC.setBookmarks(audiobookBookmarks ?? [])
      audiobookVC.onPlaybackStateChange = { [weak self] state in
        self?.onAudiobookPlaybackStateChange?(state)
        AudiobookSession.shared.receivePlayback(state)
      }
      audiobookVC.onBookmarkChange = { [weak self] event in
        self?.onAudiobookBookmarkChange?(event)
      }
    }

    if preferences != nil { updatePreferences() }
    if decorations != nil { updateDecorations() }
  }

  private func attemptEmbedReaderView() {
    guard let vc = readerHost, !isReaderEmbedded else { return }
    guard hostView.window != nil,
          hostView.superview != nil,
          let containerViewController = parentViewController else {
      print(
        "[ReadiumNative] Reader not embedded yet (window: \(hostView.window != nil), superview: \(hostView.superview != nil), parentVC: \(parentViewController != nil))"
      )
      return
    }

    let readerVC = vc.viewController
    readerVC.willMove(toParent: nil)
    readerVC.view.removeFromSuperview()
    readerVC.removeFromParent()

    containerViewController.addChild(readerVC)
    let rootView = readerVC.view!
    hostView.addSubview(rootView)
    readerVC.didMove(toParent: containerViewController)

    rootView.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      rootView.topAnchor.constraint(equalTo: hostView.topAnchor),
      rootView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor),
      rootView.leftAnchor.constraint(equalTo: hostView.leftAnchor),
      rootView.rightAnchor.constraint(equalTo: hostView.rightAnchor),
    ])

    isReaderEmbedded = true
    notifyPublicationReadyIfNeeded(for: vc)
  }

  private func notifyPublicationReadyIfNeeded(for vc: ReadiumReaderHosting) {
    guard !hasNotifiedPublicationReady else { return }
    hasNotifiedPublicationReady = true

    Task { @MainActor [weak self] in
      guard let self = self else { return }

      let tocResult = await vc.publication.tableOfContents()
      let positionsResult = await vc.publication.positions()

      var tocLinks: [Link] = []
      switch tocResult {
      case .success(let links):
        tocLinks = flattenReadiumLinks(links)
      case .failure:
        tocLinks = []
      }

      var positions: [Locator] = []
      switch positionsResult {
      case .success(let pos):
        positions = pos.map { readiumLocatorToNitro($0) }
      case .failure:
        positions = []
      }

      let metadata = readiumMetadataToNitro(vc.publication.metadata)

      let event = PublicationReadyEvent(
        tableOfContents: tocLinks,
        positions: positions,
        metadata: metadata
      )

      self.onPublicationReady?(event)
    }
  }

  private func detachEmbeddedReaderView() {
    guard let host = readerHost, isReaderEmbedded else { return }

    let vc = host.viewController
    vc.willMove(toParent: nil)
    if vc.view.superview != nil {
      vc.view.removeFromSuperview()
    }
    vc.removeFromParent()
    isReaderEmbedded = false
  }

  // MARK: - Imperative navigation

  func goTo(locator: Locator) {
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let navigator = self.readerHost?.readiumNavigator else { return }
      guard let readiumLocator = nitroLocatorToReadium(locator) else { return }
      _ = await navigator.go(to: readiumLocator, options: .animated)
    }
  }

  func goForward() {
    Task { @MainActor in
      guard let navigator = readerHost?.readiumNavigator else { return }
      _ = await navigator.goForward(options: .animated)
    }
  }

  func goBackward() {
    Task { @MainActor in
      guard let navigator = readerHost?.readiumNavigator else { return }
      _ = await navigator.goBackward(options: .animated)
    }
  }

  func play() {
    if readerHost is AudiobookViewController {
      AudiobookSession.shared.play()
    }
  }

  func pause() {
    if readerHost is AudiobookViewController {
      AudiobookSession.shared.pause()
    }
  }

  func seekTo(position: Double) {
    if readerHost is AudiobookViewController {
      AudiobookSession.shared.seekTo(position)
    }
  }

  func setPlaybackRate(rate: Double) {
    if readerHost is AudiobookViewController {
      AudiobookSession.shared.setPlaybackRate(rate)
    }
  }

  func setVolume(volume: Double) {
    if readerHost is AudiobookViewController {
      AudiobookSession.shared.setVolume(volume)
    }
  }

  func setSleepTimer(seconds: Double?) {
    if readerHost is AudiobookViewController {
      AudiobookSession.shared.setSleepTimer(seconds)
    }
  }

  func destroy() {
    if Thread.isMainThread {
      cleanup()
    } else {
      DispatchQueue.main.async { [weak self] in
        self?.cleanup()
      }
    }
  }

  // Cleanup
  func cleanup() {
    detachEmbeddedReaderView()
    readerHost = nil
    hasLoadedBook = false
    hasNotifiedPublicationReady = false

    for subscription in subscriptions {
      subscription.cancel()
    }
    subscriptions = Set<AnyCancellable>()
    activeDecorationGroups.removeAll()
  }
}

// MARK: - SelectionActionDelegate

extension HybridReadiumView: SelectionActionDelegate {
  func onSelectionAction(actionId: String, locator: RLocator, selectedText: String) {
    let nitroLocator = readiumLocatorToNitro(locator)

    let event = SelectionActionEvent(
      locator: nitroLocator,
      selectedText: selectedText,
      actionId: actionId
    )

    self.onSelectionAction?(event)
  }
}
