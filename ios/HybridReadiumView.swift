import Combine
import Foundation
import NitroModules
import ReadiumShared
import ReadiumStreamer
import UIKit
import ReadiumNavigator

class HybridReadiumView: HybridReadiumViewSpec {

  // MARK: - HybridReadiumViewSpec conformance

  var view: UIView { hostView }

  var file: ReadiumFile? = nil {
    didSet {
      guard let file = file else { return }
      pendingFileUrl = file.url
      pendingInitialLocation = file.initialLocation
      tryLoadBook()
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

  var onLocationChange: ((Locator) -> Void)? = nil
  var onPublicationReady: ((PublicationReadyEvent) -> Void)? = nil
  var onDecorationActivated: ((DecorationActivatedEvent) -> Void)? = nil
  var onSelectionChange: ((SelectionEvent) -> Void)? = nil
  var onSelectionAction: ((SelectionActionEvent) -> Void)? = nil
  var onAudiobookPlaybackStateChange: ((AudiobookPlaybackState) -> Void)? = nil

  // MARK: - Private state

  private let hostView = UIView()
  private var readerService = ReaderService()
  private var readerHost: ReadiumReaderHosting?
  private var subscriptions = Set<AnyCancellable>()
  private var pendingFileUrl: String?
  private var pendingInitialLocation: Locator?
  private var hasLoadedBook = false
  private var selectionActionsReceived = false
  private var activeDecorationGroups = Set<String>()

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

    hasLoadedBook = true
    let initialLoc = pendingInitialLocation
    pendingFileUrl = nil
    pendingInitialLocation = nil

    loadBook(url: url, location: initialLoc)
  }

  private func loadBook(url: String, location: Locator?) {
    guard let rootViewController = parentViewController else { return }

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
      sender: rootViewController,
      completion: { [weak self] vc in
        guard let self = self else { return }

        if let epubVC = vc as? EPUBViewController {
          epubVC.selectionActionDelegate = self
        }

        self.addViewControllerAsSubview(host: vc)
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
    vc.publisher.sink(receiveValue: { [weak self] locator in
      guard let self = self else { return }
      let nitroLocator = readiumLocatorToNitro(locator)
      self.onLocationChange?(nitroLocator)
    })
    .store(in: &subscriptions)

    readerHost = vc

    if let audiobookVC = vc as? AudiobookViewController {
      AudiobookSession.shared.adopt(audiobookVC, url: audiobookVC.bookId)
      audiobookVC.onPlaybackStateChange = { [weak self] state in
        self?.onAudiobookPlaybackStateChange?(state)
        AudiobookSession.shared.receivePlayback(state)
      }
    }

    // Apply pending state
    if preferences != nil { updatePreferences() }
    if decorations != nil { updateDecorations() }

    let readerVC = vc.viewController

    guard
      readerHost != nil,
      hostView.superview?.frame != nil,
      let containerViewController = parentViewController
    else { return }

    readerVC.willMove(toParent: nil)
    readerVC.view.removeFromSuperview()
    readerVC.removeFromParent()
    readerVC.view.frame = hostView.superview!.frame
    containerViewController.addChild(readerVC)
    let rootView = readerVC.view!
    hostView.addSubview(rootView)
    readerVC.didMove(toParent: containerViewController)

    rootView.translatesAutoresizingMaskIntoConstraints = false
    rootView.topAnchor.constraint(equalTo: hostView.topAnchor).isActive = true
    rootView.bottomAnchor.constraint(equalTo: hostView.bottomAnchor).isActive = true
    rootView.leftAnchor.constraint(equalTo: hostView.leftAnchor).isActive = true
    rootView.rightAnchor.constraint(equalTo: hostView.rightAnchor).isActive = true

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
    guard let host = readerHost else { return }
    readerHost = nil

    let vc = host.viewController
    vc.willMove(toParent: nil)
    if vc.view.superview != nil {
      vc.view.removeFromSuperview()
    }
    vc.removeFromParent()

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
