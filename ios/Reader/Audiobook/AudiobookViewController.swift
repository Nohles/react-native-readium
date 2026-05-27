import Combine
import AVFoundation
import AVKit
import MediaPlayer
import ReadiumNavigator
import ReadiumShared
import UIKit

private struct AudiobookChapter {
  let link: ReadiumShared.Link
  let title: String
  let href: String
  let depth: Int
  let time: Double
}

private enum SleepTimerMode {
  case off
  case seconds(Double, startedAt: Date)
  case endOfChapter(Double)
}

private enum AudiobookScreenMode: Int {
  case nowPlaying
  case chapters
  case bookmarks
}

final class AudiobookViewController: UIViewController, PublicationReaderViewController, Loggable {
  weak var moduleDelegate: ReaderFormatModuleDelegate?
  var onPlaybackStateChange: ((AudiobookPlaybackState) -> Void)?
  var onBookmarkChange: ((AudiobookBookmarkChangeEvent) -> Void)?

  let publication: Publication
  let bookId: String
  let audioNavigator: AudioNavigator

  private let subject = PassthroughSubject<ReadiumShared.Locator, Never>()
  lazy var publisher = subject.eraseToAnyPublisher()

  private var chapters: [AudiobookChapter] = []
  private var readingOrderOffsets: [String: Double] = [:]
  private var readingOrderLinks: [ReadiumShared.Link] = []
  private var duration: Double = 0
  private var currentPosition: Double = 0
  private var currentResourceIndex: Int = 0
  private var currentResourceTime: Double = 0
  private var isPlaying = false
  private var playbackRate = 1.0
  private var volume = 1.0
  private var skipBackwardInterval = 15.0
  private var skipForwardInterval = 30.0
  private var continuousPlay = true
  private var sleepTimerMode: SleepTimerMode = .off
  private var sleepTimer: Timer?
  private var nowPlayingArtwork: MPMediaItemArtwork?
  private var bookmarks: [AudiobookBookmark] = []
  private var screenMode: AudiobookScreenMode = .nowPlaying

  private let backgroundColor = UIColor(red: 0.075, green: 0.078, blue: 0.086, alpha: 1)
  private let panelColor = UIColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 0.72)
  private let foregroundColor = UIColor.white
  private let secondaryColor = UIColor(red: 0.66, green: 0.66, blue: 0.70, alpha: 1)
  private let accentColor = UIColor(red: 0.72, green: 0.53, blue: 0.38, alpha: 1)

  private let coverImageView = UIImageView()
  private let placeholderLabel = UILabel()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let playButton = UIButton(type: .system)
  private let chapterLabel = UILabel()
  private let timelineSlider = ChapterSlider()
  private let elapsedLabel = UILabel()
  private let remainingCenterLabel = UILabel()
  private let remainingLabel = UILabel()
  private let rateCaptionLabel = UILabel()
  private let modeStack = UIStackView()
  private var modeButtons: [UIButton] = []
  private let nowPlayingContainer = UIView()
  private let nowPlayingStack = UIStackView()
  private let progressStack = UIStackView()
  private let listTableView = UITableView(frame: .zero, style: .plain)
  private var listBottomToControlsConstraint: NSLayoutConstraint?
  private var progressCollapsedHeightConstraint: NSLayoutConstraint?
  private let bookmarkButton = UIButton(type: .system)

  init(publication: Publication, locator: ReadiumShared.Locator?, bookId: String) {
    self.publication = publication
    self.bookId = bookId
    self.audioNavigator = AudioNavigator(publication: publication, initialLocation: locator)
    super.init(nibName: nil, bundle: nil)
    audioNavigator.delegate = self
    configurePublicationData()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  deinit {
    sleepTimer?.invalidate()
    MPRemoteCommandCenter.shared().playCommand.removeTarget(self)
    MPRemoteCommandCenter.shared().pauseCommand.removeTarget(self)
    MPRemoteCommandCenter.shared().togglePlayPauseCommand.removeTarget(self)
    MPRemoteCommandCenter.shared().skipBackwardCommand.removeTarget(self)
    MPRemoteCommandCenter.shared().skipForwardCommand.removeTarget(self)
    MPRemoteCommandCenter.shared().previousTrackCommand.removeTarget(self)
    MPRemoteCommandCenter.shared().nextTrackCommand.removeTarget(self)
    MPRemoteCommandCenter.shared().changePlaybackPositionCommand.removeTarget(self)
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    audioNavigator.pause()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = backgroundColor
    buildUI()
    loadCover()
    configureSystemAudio()
    configureRemoteCommandCenter()
    updatePlaybackUI()
    emitPlaybackState()
  }

  @MainActor
  func goTo(_ locator: ReadiumShared.Locator) async {
    _ = await audioNavigator.go(to: locator, options: .animated)
  }

  @MainActor
  func goForward() async {
    seekToNextChapter()
  }

  @MainActor
  func goBackward() async {
    seekToPreviousChapter()
  }

  func play() {
    activateAudioSession()
    audioNavigator.play()
  }

  func pause() {
    audioNavigator.pause()
  }

  func seekTo(position: Double) {
    seekToAbsoluteTime(position)
  }

  func setPlaybackRate(_ rate: Double) {
    let nearestRate = [0.75, 1.0, 1.25, 1.5, 2.0].min(by: { abs($0 - rate) < abs($1 - rate) }) ?? 1.0
    playbackRate = nearestRate
    audioNavigator.submitPreferences(AudioPreferences(volume: volume, speed: playbackRate))
    updatePlaybackUI()
    emitPlaybackState()
  }

  func setVolume(_ value: Double) {
    volume = min(max(value, 0), 1)
    audioNavigator.submitPreferences(AudioPreferences(volume: volume, speed: playbackRate))
    emitPlaybackState()
  }

  func setSleepTimer(seconds: Double?) {
    sleepTimer?.invalidate()
    sleepTimer = nil

    guard let seconds = seconds, seconds > 0 else {
      sleepTimerMode = .off
      emitPlaybackState()
      return
    }

    sleepTimerMode = .seconds(seconds, startedAt: Date())
    sleepTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
      self?.pause()
      self?.sleepTimerMode = .off
      self?.emitPlaybackState()
    }
    emitPlaybackState()
  }

  func setBookmarks(_ bookmarks: [AudiobookBookmark]) {
    self.bookmarks = bookmarks
    listTableView.reloadData()
    updateBookmarkButton()
  }

  private func buildUI() {
    view.backgroundColor = backgroundColor
    coverImageView.contentMode = .scaleAspectFill
    coverImageView.clipsToBounds = true
    coverImageView.layer.cornerRadius = 12
    coverImageView.contentAlignment = .center
    coverImageView.backgroundColor = panelColor

    placeholderLabel.font = .boldSystemFont(ofSize: 42)
    placeholderLabel.textAlignment = .center
    placeholderLabel.textColor = secondaryColor
    coverImageView.addSubview(placeholderLabel)
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

    if let serifDescriptor = UIFontDescriptor.preferredFontDescriptor(withTextStyle: .title3).withDesign(.serif) {
      let boldDescriptor = serifDescriptor.withSymbolicTraits(.traitBold) ?? serifDescriptor
      titleLabel.font = UIFont(descriptor: boldDescriptor, size: 20)
    } else {
      titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)
    }
    titleLabel.textColor = foregroundColor
    titleLabel.textAlignment = .left
    titleLabel.numberOfLines = 3
    titleLabel.adjustsFontSizeToFitWidth = true
    titleLabel.minimumScaleFactor = 0.85
    titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    titleLabel.text = publication.metadata.title

    subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
    subtitleLabel.textColor = secondaryColor
    subtitleLabel.textAlignment = .left
    subtitleLabel.numberOfLines = 2
    configureSubtitleLabel()

    configureModeButton("Now Playing", image: "play.circle.fill", mode: .nowPlaying)
    configureModeButton("Chapters", image: "list.bullet", mode: .chapters)
    configureModeButton("Bookmarks", image: "bookmark", mode: .bookmarks)
    modeStack.axis = .horizontal
    modeStack.spacing = 8
    modeStack.alignment = .center
    modeStack.distribution = .fill
    view.addSubview(modeStack)
    modeStack.translatesAutoresizingMaskIntoConstraints = false

    let overflow = iconButton("ellipsis.circle.fill", action: #selector(settingsTapped), pointSize: 23, size: 38)
    let titleStack = UIStackView(arrangedSubviews: [titleLabel, overflow])
    titleStack.axis = .horizontal
    titleStack.alignment = .top
    titleStack.spacing = 10

    chapterLabel.font = .preferredFont(forTextStyle: .subheadline)
    chapterLabel.textColor = secondaryColor
    chapterLabel.textAlignment = .left

    timelineSlider.minimumValue = 0
    timelineSlider.maximumValue = Float(max(duration, 1))
    timelineSlider.tintColor = accentColor
    timelineSlider.markerColor = accentColor
    timelineSlider.addTarget(self, action: #selector(timelineChanged), for: .valueChanged)

    elapsedLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
    elapsedLabel.textColor = secondaryColor
    elapsedLabel.text = "0:00"
    remainingCenterLabel.font = .systemFont(ofSize: 13, weight: .regular)
    remainingCenterLabel.textColor = secondaryColor
    remainingCenterLabel.textAlignment = .center
    remainingLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .regular)
    remainingLabel.textColor = foregroundColor
    remainingLabel.textAlignment = .right
    let timeRow = UIStackView(arrangedSubviews: [elapsedLabel, remainingCenterLabel, remainingLabel])
    timeRow.axis = .horizontal
    timeRow.distribution = .fillEqually
    timeRow.alignment = .center

    progressStack.axis = .vertical
    progressStack.spacing = 8
    progressStack.alignment = .fill
    progressStack.addArrangedSubview(chapterLabel)
    progressStack.addArrangedSubview(timelineSlider)
    progressStack.addArrangedSubview(timeRow)
    view.addSubview(progressStack)
    progressStack.translatesAutoresizingMaskIntoConstraints = false

    nowPlayingStack.axis = .vertical
    nowPlayingStack.spacing = 10
    nowPlayingStack.alignment = .leading
    nowPlayingStack.addArrangedSubview(coverImageView)
    nowPlayingStack.setCustomSpacing(14, after: coverImageView)
  
    nowPlayingStack.addArrangedSubview(titleStack)
    nowPlayingStack.setCustomSpacing(4, after: titleStack)
    nowPlayingStack.addArrangedSubview(subtitleLabel)
    nowPlayingContainer.addSubview(nowPlayingStack)
    nowPlayingStack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(nowPlayingContainer)
    nowPlayingContainer.translatesAutoresizingMaskIntoConstraints = false

    titleStack.widthAnchor.constraint(equalTo: nowPlayingStack.widthAnchor).isActive = true
    subtitleLabel.widthAnchor.constraint(equalTo: nowPlayingStack.widthAnchor).isActive = true

    listTableView.backgroundColor = panelColor
    listTableView.layer.cornerRadius = 28
    listTableView.clipsToBounds = true
    listTableView.separatorColor = UIColor.white.withAlphaComponent(0.10)
    listTableView.separatorInset = UIEdgeInsets(top: 0, left: 22, bottom: 0, right: 22)
    listTableView.dataSource = self
    listTableView.delegate = self
    listTableView.allowsSelection = true
    listTableView.register(UITableViewCell.self, forCellReuseIdentifier: "row")
    listTableView.isHidden = true
    view.insertSubview(listTableView, aboveSubview: nowPlayingContainer)
    listTableView.translatesAutoresizingMaskIntoConstraints = false

    let previousButton = iconButton("backward.end.fill", action: #selector(previousChapterTapped), pointSize: 26, size: 48)
    let rewindButton = iconButton("gobackward.15", action: #selector(rewindTapped), pointSize: 35, size: 58)
    configurePlayButton()
    let forwardButton = iconButton("goforward.30", action: #selector(forwardTapped), pointSize: 35, size: 58)
    let nextButton = iconButton("forward.end.fill", action: #selector(nextChapterTapped), pointSize: 26, size: 48)

    let controls = UIStackView(arrangedSubviews: [previousButton, rewindButton, playButton, forwardButton, nextButton])
    controls.axis = .horizontal
    controls.alignment = .center
    controls.distribution = .equalSpacing
    view.addSubview(controls)
    controls.translatesAutoresizingMaskIntoConstraints = false

    let rateButton = utilityButton("dial.medium", action: #selector(rateTapped))
    rateCaptionLabel.font = .systemFont(ofSize: 16, weight: .semibold)
    rateCaptionLabel.textColor = foregroundColor
    rateCaptionLabel.textAlignment = .center
    let rateStack = UIStackView(arrangedSubviews: [rateButton, rateCaptionLabel])
    rateStack.axis = .horizontal
    rateStack.spacing = 4
    rateStack.alignment = .center
    let infoButton = utilityButton("info.circle", action: #selector(infoTapped))
    let routePicker = AVRoutePickerView()
    routePicker.tintColor = foregroundColor
    routePicker.activeTintColor = accentColor
    let sleepButton = utilityButton("moon.zzz", action: #selector(sleepTapped))
    bookmarkButton.setImage(UIImage(systemName: "bookmark"), for: .normal)
    bookmarkButton.tintColor = foregroundColor
    bookmarkButton.addTarget(self, action: #selector(bookmarkTapped), for: .touchUpInside)
    constrainButton(bookmarkButton, size: 44)
    let utilityStack = UIStackView(arrangedSubviews: [rateStack, infoButton, routePicker, sleepButton, bookmarkButton])
    utilityStack.axis = .horizontal
    utilityStack.alignment = .center
    utilityStack.distribution = .equalSpacing
    let utilityPanel = makeGlassPanel(containing: utilityStack, radius: 30)
    view.addSubview(utilityPanel)
    utilityPanel.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      modeStack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 10),
      modeStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 16),
      modeStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -16),
      modeStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      progressStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      progressStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      progressStack.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -20),
      nowPlayingContainer.topAnchor.constraint(equalTo: modeStack.bottomAnchor, constant: 12),
      nowPlayingContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      nowPlayingContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      nowPlayingContainer.bottomAnchor.constraint(equalTo: progressStack.topAnchor, constant: -8),
      nowPlayingStack.topAnchor.constraint(equalTo: nowPlayingContainer.topAnchor),
      nowPlayingStack.leadingAnchor.constraint(equalTo: nowPlayingContainer.leadingAnchor),
      nowPlayingStack.trailingAnchor.constraint(equalTo: nowPlayingContainer.trailingAnchor),
      coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor),
      placeholderLabel.centerXAnchor.constraint(equalTo: coverImageView.centerXAnchor),
      placeholderLabel.centerYAnchor.constraint(equalTo: coverImageView.centerYAnchor),
      listTableView.topAnchor.constraint(equalTo: modeStack.bottomAnchor, constant: 16),
      listTableView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
      listTableView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
      controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 26),
      controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26),
      controls.bottomAnchor.constraint(equalTo: utilityPanel.topAnchor, constant: -34),
      utilityPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
      utilityPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -22),
      utilityPanel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -18),
      utilityPanel.heightAnchor.constraint(equalToConstant: 62),
      routePicker.widthAnchor.constraint(equalToConstant: 44),
      routePicker.heightAnchor.constraint(equalToConstant: 44)
    ])

    let coverWidth = coverImageView.widthAnchor.constraint(equalTo: nowPlayingStack.widthAnchor)
    coverWidth.priority = .defaultHigh
    coverWidth.isActive = true
    coverImageView.widthAnchor.constraint(lessThanOrEqualTo: view.heightAnchor, multiplier: 0.36).isActive = true

    listBottomToControlsConstraint = listTableView.bottomAnchor.constraint(equalTo: controls.topAnchor, constant: -20)
    listBottomToControlsConstraint?.isActive = true
    progressCollapsedHeightConstraint = progressStack.heightAnchor.constraint(equalToConstant: 0)
    progressCollapsedHeightConstraint?.priority = .required

    updateModeUI()
  }

  private func configureSubtitleLabel() {
    let publicationTitle = publication.metadata.title ?? ""
    let author = publication.metadata.authors.map(\.name).joined(separator: ", ")
    if !author.isEmpty {
      subtitleLabel.text = "By \(author)"
      subtitleLabel.isHidden = false
    } else if let subtitle = publication.metadata.subtitle,
              !subtitle.isEmpty,
              subtitle != publicationTitle {
      subtitleLabel.text = subtitle
      subtitleLabel.isHidden = false
    } else {
      subtitleLabel.text = nil
      subtitleLabel.isHidden = true
    }
  }

  private func configureModeButton(_ title: String, image: String, mode: AudiobookScreenMode) {
    var configuration = UIButton.Configuration.plain()
    configuration.title = title
    configuration.image = UIImage(systemName: image)
    configuration.imagePlacement = .leading
    configuration.imagePadding = 4
    configuration.titleLineBreakMode = .byTruncatingTail
    configuration.cornerStyle = .capsule
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 5, leading: 11, bottom: 5, trailing: 11)
    configuration.background.cornerRadius = 18
    configuration.background.backgroundColor = UIColor.white.withAlphaComponent(0.10)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = .systemFont(ofSize: 12, weight: .semibold)
      return outgoing
    }
    configuration.subtitleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
      var outgoing = incoming
      outgoing.font = .systemFont(ofSize: 11, weight: .medium)
      return outgoing
    }
    let button = UIButton(configuration: configuration)
    button.tag = mode.rawValue
    button.accessibilityLabel = title
    button.setContentHuggingPriority(.required, for: .horizontal)
    button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
    button.addTarget(self, action: #selector(modeTapped(_:)), for: .touchUpInside)
    modeButtons.append(button)
    modeStack.addArrangedSubview(button)
  }

  private func makeGlassPanel(
    containing content: UIView,
    radius: CGFloat,
    contentInsets: NSDirectionalEdgeInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
  ) -> UIVisualEffectView {
    let effect: UIVisualEffect
    if #available(iOS 26.0, *) {
      let glass = UIGlassEffect(style: .regular)
      glass.tintColor = UIColor.black.withAlphaComponent(0.22)
      effect = glass
    } else {
      effect = UIBlurEffect(style: .systemThinMaterialDark)
    }
    let panel = UIVisualEffectView(effect: effect)
    panel.layer.cornerRadius = radius
    panel.clipsToBounds = true
    panel.contentView.addSubview(content)
    content.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      content.leadingAnchor.constraint(equalTo: panel.contentView.leadingAnchor, constant: contentInsets.leading),
      content.trailingAnchor.constraint(equalTo: panel.contentView.trailingAnchor, constant: -contentInsets.trailing),
      content.topAnchor.constraint(equalTo: panel.contentView.topAnchor, constant: contentInsets.top),
      content.bottomAnchor.constraint(equalTo: panel.contentView.bottomAnchor, constant: -contentInsets.bottom)
    ])
    return panel
  }

  private func utilityButton(_ systemName: String, action: Selector) -> UIButton {
    iconButton(systemName, action: action, pointSize: 24, size: 44)
  }

  private func configurePlayButton() {
    playButton.tintColor = foregroundColor
    playButton.imageView?.contentMode = .scaleAspectFit
    playButton.setPreferredSymbolConfiguration(.init(pointSize: 44, weight: .bold), forImageIn: .normal)
    playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
    constrainButton(playButton, size: 72)
  }

  private func iconButton(
    _ systemName: String,
    action: Selector,
    pointSize: CGFloat = 26,
    size: CGFloat = 44
  ) -> UIButton {
    let button = UIButton(type: .system)
    button.tintColor = foregroundColor
    button.imageView?.contentMode = .scaleAspectFit
    button.setImage(UIImage(systemName: systemName), for: .normal)
    button.setPreferredSymbolConfiguration(.init(pointSize: pointSize, weight: .bold), forImageIn: .normal)
    button.addTarget(self, action: action, for: .touchUpInside)
    constrainButton(button, size: size)
    return button
  }

  private func constrainButton(_ button: UIButton, size: CGFloat) {
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: size),
      button.heightAnchor.constraint(equalToConstant: size)
    ])
  }

  private func bottomButton(_ systemName: String, title: String?, action: Selector) -> UIButton {
    let button = iconButton(systemName, action: action, pointSize: 28, size: 54)
    if let title = title {
      button.setTitle(title, for: .normal)
    }
    return button
  }

  private func configurePublicationData() {
    readingOrderLinks = publication.readingOrder
    var offset = 0.0
    for link in readingOrderLinks {
      storeReadingOrderOffset(for: link.href, offset: offset)
      offset += link.duration ?? 0
    }
    if let metadataDuration = publication.metadata.duration, metadataDuration > 0 {
      duration = metadataDuration
    } else if let navigatorDuration = audioNavigator.totalDuration, navigatorDuration > 0 {
      duration = navigatorDuration
    } else {
      duration = offset
    }

    Task { [weak self] in
      guard let self else { return }
      let result = await publication.tableOfContents()
      await MainActor.run {
        switch result {
        case .success(let links):
          self.chapters = self.flattenChapters(links)
          self.timelineSlider.markers = self.chapters.compactMap {
            guard self.duration > 0 else { return nil }
            return Float($0.time / self.duration)
          }
        case .failure:
          self.chapters = []
          self.timelineSlider.markers = []
        }
        self.updatePlaybackUI()
      }
    }
  }

  private func flattenChapters(_ links: [ReadiumShared.Link], depth: Int = 0) -> [AudiobookChapter] {
    links.flatMap { link -> [AudiobookChapter] in
      let href = link.href
      let time = absoluteTime(forHref: href)
      let chapter = AudiobookChapter(
        link: link,
        title: link.title ?? "Untitled",
        href: href,
        depth: depth,
        time: time
      )
      return [chapter] + flattenChapters(link.children, depth: depth + 1)
    }
  }

  private func loadCover() {
    placeholderLabel.text = initials(from: publication.metadata.title ?? "Audiobook")
    guard let cover = publication.links.first(where: { link in
      link.rels.contains { "\($0)" == "cover" }
    }) else {
      return
    }

    let url = cover.url().url

    URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        self?.placeholderLabel.text = nil
        self?.coverImageView.image = image
        self?.nowPlayingArtwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self?.updateNowPlayingInfo()
      }
    }.resume()
  }

  private func configureSystemAudio() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [])
    } catch {
      log(.error, "Failed to configure audiobook audio session: \(error)")
    }
  }

  private func activateAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      log(.error, "Failed to activate audiobook audio session: \(error)")
    }
  }

  private func configureRemoteCommandCenter() {
    let commandCenter = MPRemoteCommandCenter.shared()

    commandCenter.playCommand.isEnabled = true
    commandCenter.playCommand.addTarget(self, action: #selector(remotePlay(_:)))

    commandCenter.pauseCommand.isEnabled = true
    commandCenter.pauseCommand.addTarget(self, action: #selector(remotePause(_:)))

    commandCenter.togglePlayPauseCommand.isEnabled = true
    commandCenter.togglePlayPauseCommand.addTarget(self, action: #selector(remoteTogglePlayPause(_:)))

    commandCenter.skipBackwardCommand.isEnabled = true
    commandCenter.skipBackwardCommand.preferredIntervals = [NSNumber(value: skipBackwardInterval)]
    commandCenter.skipBackwardCommand.addTarget(self, action: #selector(remoteSkipBackward(_:)))

    commandCenter.skipForwardCommand.isEnabled = true
    commandCenter.skipForwardCommand.preferredIntervals = [NSNumber(value: skipForwardInterval)]
    commandCenter.skipForwardCommand.addTarget(self, action: #selector(remoteSkipForward(_:)))

    commandCenter.previousTrackCommand.isEnabled = true
    commandCenter.previousTrackCommand.addTarget(self, action: #selector(remotePreviousChapter(_:)))

    commandCenter.nextTrackCommand.isEnabled = true
    commandCenter.nextTrackCommand.addTarget(self, action: #selector(remoteNextChapter(_:)))

    commandCenter.changePlaybackPositionCommand.isEnabled = true
    commandCenter.changePlaybackPositionCommand.addTarget(self, action: #selector(remoteChangePlaybackPosition(_:)))
  }

  private func seekToChapter(_ chapter: AudiobookChapter) {
    let localTime = fragmentTime(chapter.href)
    Task { @MainActor in
      let moved = await self.audioNavigator.go(to: chapter.link, options: .animated)
      if moved {
        if localTime > 0 {
          await self.audioNavigator.seek(to: localTime)
        }
      } else {
        self.seekToAbsoluteTime(chapter.time)
      }
    }
  }

  private func seekToAbsoluteTime(_ absoluteTime: Double) {
    let clamped = min(max(absoluteTime, 0), max(duration, 0))
    guard let (resourceIndex, localTime) = resourceIndexAndLocalTime(forAbsoluteTime: clamped) else { return }
    Task { @MainActor in
      let info = self.audioNavigator.playbackInfo
      if resourceIndex == info.resourceIndex, info.state != .loading {
        await self.audioNavigator.seek(to: localTime)
        return
      }
      guard self.readingOrderLinks.indices.contains(resourceIndex) else { return }
      let moved = await self.audioNavigator.go(
        to: self.readingOrderLinks[resourceIndex],
        options: .animated
      )
      if moved, localTime > 0 {
        await self.audioNavigator.seek(to: localTime)
      }
    }
  }

  private func resourceIndexAndLocalTime(forAbsoluteTime absoluteTime: Double) -> (Int, Double)? {
    guard !readingOrderLinks.isEmpty else { return nil }
    var running = 0.0
    for (index, link) in readingOrderLinks.enumerated() {
      let linkDuration = link.duration ?? 0
      if absoluteTime <= running + linkDuration || index == readingOrderLinks.count - 1 {
        return (index, max(0, absoluteTime - running))
      }
      running += linkDuration
    }
    return nil
  }

  private func locator(forAbsoluteTime absoluteTime: Double) -> ReadiumShared.Locator? {
    guard !readingOrderLinks.isEmpty else { return nil }
    var running = 0.0
    for (index, link) in readingOrderLinks.enumerated() {
      let linkDuration = link.duration ?? 0
      if absoluteTime <= running + linkDuration || index == readingOrderLinks.count - 1 {
        let localTime = max(0, absoluteTime - running)
        return ReadiumShared.Locator(
          href: link.url(),
          mediaType: link.mediaType ?? MediaType("audio/*")!,
          title: link.title,
          locations: .init(fragments: ["t=\(localTime)"])
        )
      }
      running += linkDuration
    }
    return nil
  }

  private func updatePlaybackInfo(_ info: MediaPlaybackInfo) {
    currentResourceIndex = info.resourceIndex
    currentResourceTime = info.time
    currentPosition = absoluteTime(resourceIndex: info.resourceIndex, time: info.time)
    isPlaying = info.state == .playing
    duration = publication.metadata.duration ?? audioNavigator.totalDuration ?? max(duration, currentPosition + (info.duration ?? 0))
    updatePlaybackUI()
    updateNowPlayingInfo()
    evaluateSleepTimer()
    emitPlaybackState()
  }

  private func updatePlaybackUI() {
    timelineSlider.maximumValue = Float(max(duration, 1))
    timelineSlider.value = Float(min(currentPosition, duration))
    elapsedLabel.text = formatTime(currentPosition)
    let remainingSeconds = max(0, duration - currentPosition)
    remainingLabel.text = "-\(formatTime(remainingSeconds))"
    remainingCenterLabel.text = formatRemainingSummary(remainingSeconds)
    rateCaptionLabel.text = formatRate(playbackRate)
    let chapterTitle = currentChapter()?.title
    let publicationTitle = publication.metadata.title ?? ""
    let chapterIndex = chapters.lastIndex(where: { $0.time <= currentPosition + 0.25 }).map { $0 + 1 } ?? 1
    if let chapterTitle, !chapterTitle.isEmpty, chapterTitle != publicationTitle {
      if chapters.count > 1 {
        chapterLabel.text = "Chapter \(chapterIndex) - \(chapterTitle)"
      } else {
        chapterLabel.text = chapterTitle
      }
      chapterLabel.isHidden = false
    } else if chapters.isEmpty {
      chapterLabel.isHidden = true
    } else {
      chapterLabel.text = "Chapter \(chapterIndex) of \(chapters.count)"
      chapterLabel.isHidden = false
    }
    let imageName = isPlaying ? "pause.fill" : "play.fill"
    playButton.setImage(UIImage(systemName: imageName), for: .normal)
    updateBookmarkButton()
    if !listTableView.isHidden {
      listTableView.reloadData()
    }
    updateChapterModeSubtitle()
  }

  private func updateChapterModeSubtitle() {
    guard let button = modeButtons.first(where: { $0.tag == AudiobookScreenMode.chapters.rawValue }) else { return }
    var configuration = button.configuration
    if chapters.isEmpty {
      configuration?.subtitle = nil
    } else {
      let chapterIndex = chapters.lastIndex(where: { $0.time <= currentPosition + 0.25 }).map { $0 + 1 } ?? 1
      configuration?.subtitle = "\(chapterIndex) of \(chapters.count)"
    }
    button.configuration = configuration
  }

  private func updateNowPlayingInfo() {
    var info: [String: Any] = [
      MPMediaItemPropertyTitle: publication.metadata.title ?? "Audiobook",
      MPMediaItemPropertyPlaybackDuration: duration,
      MPNowPlayingInfoPropertyElapsedPlaybackTime: currentPosition,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? playbackRate : 0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: playbackRate,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue
    ]

    let authors = publication.metadata.authors.map(\.name).joined(separator: ", ")
    if !authors.isEmpty {
      info[MPMediaItemPropertyArtist] = authors
    }

    if let chapterTitle = currentChapter()?.title {
      info[MPMediaItemPropertyAlbumTitle] = chapterTitle
    }

    if let artwork = nowPlayingArtwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
  }

  private func emitPlaybackState() {
    let remaining = sleepTimerRemaining()
    let currentLink = readingOrderLinks.indices.contains(currentResourceIndex) ? readingOrderLinks[currentResourceIndex] : nil
    let state = AudiobookPlaybackState(
      isPlaying: isPlaying,
      position: currentPosition,
      duration: duration,
      rate: playbackRate,
      volume: volume,
      currentHref: currentLink?.href,
      currentTitle: currentChapter()?.title ?? currentLink?.title,
      sleepTimerRemaining: remaining
    )
    onPlaybackStateChange?(state)
  }

  private func evaluateSleepTimer() {
    switch sleepTimerMode {
    case .endOfChapter(let targetTime) where currentPosition >= targetTime:
      pause()
      sleepTimerMode = .off
    default:
      break
    }
  }

  private func sleepTimerRemaining() -> Double? {
    switch sleepTimerMode {
    case .off:
      return nil
    case .seconds(let seconds, let startedAt):
      return max(0, seconds - Date().timeIntervalSince(startedAt))
    case .endOfChapter(let targetTime):
      return max(0, targetTime - currentPosition)
    }
  }

  private func currentChapter() -> AudiobookChapter? {
    chapters.last(where: { $0.time <= currentPosition + 0.25 })
  }

  private func seekToPreviousChapter() {
    guard !chapters.isEmpty else {
      Task { @MainActor in _ = await audioNavigator.goBackward(options: .animated) }
      return
    }
    let current = currentChapter()
    let target: AudiobookChapter?
    if let current, currentPosition - current.time > 3 {
      target = current
    } else {
      target = chapters.last(where: { $0.time < (current?.time ?? currentPosition) - 0.25 })
    }
    seekToAbsoluteTime(target?.time ?? 0)
  }

  private func seekToNextChapter() {
    guard let next = chapters.first(where: { $0.time > currentPosition + 0.25 }) else { return }
    seekToAbsoluteTime(next.time)
  }

  private func absoluteTime(resourceIndex: Int, time: Double) -> Double {
    guard readingOrderLinks.indices.contains(resourceIndex) else { return time }
    let link = readingOrderLinks[resourceIndex]
    return (readingOrderOffset(for: link.href) ?? 0) + time
  }

  private func absoluteTime(forHref href: String) -> Double {
    (readingOrderOffset(for: href) ?? 0) + fragmentTime(href)
  }

  private func storeReadingOrderOffset(for href: String, offset: Double) {
    for key in resourceKeys(for: href) {
      readingOrderOffsets[key] = offset
    }
  }

  private func readingOrderOffset(for href: String) -> Double? {
    for key in resourceKeys(for: href) {
      if let offset = readingOrderOffsets[key] {
        return offset
      }
    }
    return nil
  }

  private func resourceKeys(for href: String) -> [String] {
    let resourcePath = normalizeHref(href).resourcePath
    var keys = [resourcePath, baseHref(href)]
    if let filename = resourcePath.split(separator: "/").last.map(String.init) {
      keys.append(filename)
    }
    return Array(Set(keys))
  }

  private func baseHref(_ href: String) -> String {
    href.components(separatedBy: "#").first ?? href
  }

  private func fragmentTime(_ href: String) -> Double {
    guard let fragment = href.components(separatedBy: "#").dropFirst().first else { return 0 }
    guard fragment.hasPrefix("t=") else { return 0 }
    let value = fragment.dropFirst(2).split(separator: ",").first.map(String.init) ?? ""
    return Double(value) ?? 0
  }

  private func formatRemainingSummary(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds > 0 else { return "" }
    let totalSeconds = Int(seconds.rounded())
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    if hours > 0 {
      return "\(hours)h \(minutes)m remaining"
    }
    if minutes > 0 {
      return "\(minutes)m remaining"
    }
    return "\(max(1, totalSeconds))s remaining"
  }

  private func formatTime(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let totalSeconds = max(0, Int(seconds.rounded()))
    let hours = totalSeconds / 3600
    let minutes = (totalSeconds % 3600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  private func formatRate(_ rate: Double) -> String {
    rate == floor(rate) ? "\(Int(rate))x" : "\(rate)x"
  }

  private func initials(from title: String) -> String {
    let parts = title.split(separator: " ")
    return parts.prefix(2).compactMap { $0.first }.map(String.init).joined()
  }

  private func bookmarkTime(_ bookmark: AudiobookBookmark) -> Double {
    bookmark.position
  }

  private func bookmarkAtCurrentPosition() -> AudiobookBookmark? {
    bookmarks.first { abs(bookmarkTime($0) - currentPosition) < 1 }
  }

  private func updateBookmarkButton() {
    let selected = bookmarkAtCurrentPosition() != nil
    bookmarkButton.setImage(UIImage(systemName: selected ? "bookmark.fill" : "bookmark"), for: .normal)
    bookmarkButton.tintColor = selected ? accentColor : foregroundColor
    bookmarkButton.accessibilityLabel = selected ? "Edit current bookmark" : "Add bookmark"
  }

  private func updateModeUI() {
    let showingNowPlaying = screenMode == .nowPlaying
    nowPlayingContainer.isHidden = !showingNowPlaying
    nowPlayingContainer.isUserInteractionEnabled = showingNowPlaying
    progressStack.isHidden = !showingNowPlaying
    progressStack.isUserInteractionEnabled = showingNowPlaying
    progressCollapsedHeightConstraint?.isActive = !showingNowPlaying
    listTableView.isHidden = showingNowPlaying
    listTableView.isUserInteractionEnabled = !showingNowPlaying
    for button in modeButtons {
      var configuration = button.configuration
      let selected = button.tag == screenMode.rawValue
      configuration?.baseForegroundColor = foregroundColor
      configuration?.background.backgroundColor = selected
        ? accentColor
        : UIColor.white.withAlphaComponent(0.08)
      button.configuration = configuration
    }
    updateChapterModeSubtitle()
    listTableView.reloadData()
  }

  @objc private func modeTapped(_ sender: UIButton) {
    guard let mode = AudiobookScreenMode(rawValue: sender.tag) else { return }
    screenMode = mode
    updateModeUI()
  }

  @objc private func closeTapped() {
    pause()
  }

  @objc private func settingsTapped() {
    let vc = AudioSettingsViewController(
      selectedTheme: "Dark",
      skipBackward: skipBackwardInterval,
      skipForward: skipForwardInterval,
      continuousPlay: continuousPlay
    ) { [weak self] settings in
      guard let self else { return }
      self.skipBackwardInterval = settings.skipBackward
      self.skipForwardInterval = settings.skipForward
      self.continuousPlay = settings.continuousPlay
      MPRemoteCommandCenter.shared().skipBackwardCommand.preferredIntervals = [NSNumber(value: settings.skipBackward)]
      MPRemoteCommandCenter.shared().skipForwardCommand.preferredIntervals = [NSNumber(value: settings.skipForward)]
    }
    presentSheet(vc)
  }

  @objc private func playPauseTapped() {
    isPlaying ? pause() : play()
  }

  @objc private func rewindTapped() {
    seekToAbsoluteTime(currentPosition - skipBackwardInterval)
  }

  @objc private func forwardTapped() {
    seekToAbsoluteTime(currentPosition + skipForwardInterval)
  }

  @objc private func previousChapterTapped() {
    seekToPreviousChapter()
  }

  @objc private func nextChapterTapped() {
    seekToNextChapter()
  }

  @objc private func timelineChanged() {
    seekToAbsoluteTime(Double(timelineSlider.value))
  }

  @objc private func rateTapped() {
    let vc = OptionsSheetViewController(title: "Playback Rate", options: ["0.75x", "1x", "1.25x", "1.5x", "2x"]) { [weak self] option in
      self?.setPlaybackRate(Double(option.replacingOccurrences(of: "x", with: "")) ?? 1)
    }
    presentSheet(vc)
  }

  @objc private func infoTapped() {
    let authors = publication.metadata.authors.map(\.name).joined(separator: ", ")
    let message = [
      authors.isEmpty ? nil : "By \(authors)",
      publication.metadata.subtitle,
      duration > 0 ? "Duration \(formatTime(duration))" : nil
    ].compactMap { $0 }.joined(separator: "\n")
    let vc = UIAlertController(title: publication.metadata.title ?? "Audiobook", message: message, preferredStyle: .actionSheet)
    vc.addAction(UIAlertAction(title: "Done", style: .cancel))
    present(vc, animated: true)
  }

  @objc private func sleepTapped() {
    let vc = OptionsSheetViewController(title: "Sleep Timer", options: ["Off", "5 min", "10 min", "15 min", "30 min", "End of chapter"]) { [weak self] option in
      guard let self else { return }
      switch option {
      case "5 min": self.setSleepTimer(seconds: 300)
      case "10 min": self.setSleepTimer(seconds: 600)
      case "15 min": self.setSleepTimer(seconds: 900)
      case "30 min": self.setSleepTimer(seconds: 1800)
      case "End of chapter":
        if let next = self.chapters.first(where: { $0.time > self.currentPosition + 0.25 }) {
          self.sleepTimerMode = .endOfChapter(next.time)
          self.emitPlaybackState()
        }
      default:
        self.setSleepTimer(seconds: nil)
      }
    }
    presentSheet(vc)
  }

  @objc private func bookmarkTapped() {
    if let existing = bookmarkAtCurrentPosition() {
      presentBookmarkEditor(existing)
      return
    }
    guard let readiumLocator = locator(forAbsoluteTime: currentPosition) else { return }
    let bookmark = AudiobookBookmark(id: UUID().uuidString, locator: readiumLocatorToNitro(readiumLocator), position: currentPosition, note: nil)
    bookmarks.append(bookmark)
    onBookmarkChange?(AudiobookBookmarkChangeEvent(type: "add", bookmark: bookmark))
    updateBookmarkButton()
    listTableView.reloadData()
    presentBookmarkEditor(bookmark)
  }

  private func presentBookmarkEditor(_ bookmark: AudiobookBookmark) {
    let alert = UIAlertController(title: "Bookmark Note", message: currentChapter()?.title, preferredStyle: .alert)
    alert.addTextField { field in
      field.text = bookmark.note
      field.placeholder = "Add a note (optional)"
    }
    alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
    alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak self, weak alert] _ in
      guard let self else { return }
      let note = alert?.textFields?.first?.text ?? ""
      let updated = AudiobookBookmark(id: bookmark.id, locator: bookmark.locator, position: bookmark.position, note: note)
      if let index = self.bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
        self.bookmarks[index] = updated
      }
      self.onBookmarkChange?(AudiobookBookmarkChangeEvent(type: "update", bookmark: updated))
      self.listTableView.reloadData()
    })
    present(alert, animated: true)
  }

  private func presentSheet(_ vc: UIViewController) {
    vc.modalPresentationStyle = .pageSheet
    if let sheet = vc.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
    }
    present(vc, animated: true)
  }

  @objc private func remotePlay(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    play()
    return .success
  }

  @objc private func remotePause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    pause()
    return .success
  }

  @objc private func remoteTogglePlayPause(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    isPlaying ? pause() : play()
    return .success
  }

  @objc private func remoteSkipBackward(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    seekToAbsoluteTime(currentPosition - skipBackwardInterval)
    return .success
  }

  @objc private func remoteSkipForward(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    seekToAbsoluteTime(currentPosition + skipForwardInterval)
    return .success
  }

  @objc private func remotePreviousChapter(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    seekToPreviousChapter()
    return .success
  }

  @objc private func remoteNextChapter(_ event: MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus {
    seekToNextChapter()
    return .success
  }

  @objc private func remoteChangePlaybackPosition(_ event: MPChangePlaybackPositionCommandEvent) -> MPRemoteCommandHandlerStatus {
    seekToAbsoluteTime(event.positionTime)
    return .success
  }
}

extension AudiobookViewController: AudioNavigatorDelegate {
  func navigator(_ navigator: Navigator, locationDidChange locator: ReadiumShared.Locator) {
    subject.send(locator)
  }

  func navigator(_ navigator: Navigator, presentExternalURL url: URL) {}

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    log(.error, "Audiobook navigator error: \(error)")
    moduleDelegate?.presentError(error, from: self)
  }

  func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    updatePlaybackInfo(info)
  }

  func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
    continuousPlay
  }
}

extension AudiobookViewController: UITableViewDataSource, UITableViewDelegate {
  func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    switch screenMode {
    case .chapters:
      return max(chapters.count, 1)
    case .bookmarks:
      return max(bookmarks.count, 1)
    case .nowPlaying:
      return 0
    }
  }

  func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
    screenMode == .bookmarks ? 76 : 68
  }

  func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.backgroundColor = .clear
    cell.textLabel?.textColor = foregroundColor
    cell.textLabel?.font = .preferredFont(forTextStyle: .body)
    cell.textLabel?.numberOfLines = 2
    cell.detailTextLabel?.textColor = secondaryColor
    cell.detailTextLabel?.font = .preferredFont(forTextStyle: .subheadline)
    cell.selectionStyle = screenMode == .chapters ? .default : .none

    if screenMode == .chapters {
      guard !chapters.isEmpty else {
        cell.textLabel?.text = "No chapters available"
        cell.textLabel?.textColor = secondaryColor
        return cell
      }
      let chapter = chapters[indexPath.row]
      let isCurrent = currentChapter()?.href == chapter.href
      let isComplete = chapter.time < (currentChapter()?.time ?? 0)
      let nextTime = indexPath.row + 1 < chapters.count ? chapters[indexPath.row + 1].time : duration
      cell.textLabel?.text = String(repeating: "  ", count: chapter.depth) + chapter.title
      cell.detailTextLabel?.text = formatTime(max(0, nextTime - chapter.time))
      cell.backgroundColor = isCurrent ? accentColor.withAlphaComponent(0.38) : .clear
      if isComplete {
        cell.accessoryView = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        cell.accessoryView?.tintColor = .systemBlue
      }
      return cell
    }

    guard !bookmarks.isEmpty else {
      cell.textLabel?.text = "No bookmarks yet"
      cell.detailTextLabel?.text = "Tap the bookmark button to save this position."
      cell.textLabel?.textColor = secondaryColor
      return cell
    }
    let bookmark = bookmarks[indexPath.row]
    let time = bookmarkTime(bookmark)
    let chapter = chapters.last(where: { $0.time <= time + 0.25 })?.title ?? "Saved position"
    cell.textLabel?.text = chapter
    let note = (bookmark.note ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    cell.detailTextLabel?.text = note.isEmpty ? formatTime(time) : "\(formatTime(time))  \(note)"
    cell.backgroundColor = abs(time - currentPosition) < 1 ? accentColor.withAlphaComponent(0.38) : .clear
    return cell
  }

  func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    tableView.deselectRow(at: indexPath, animated: true)
    switch screenMode {
    case .chapters where chapters.indices.contains(indexPath.row):
      seekToChapter(chapters[indexPath.row])
      screenMode = .nowPlaying
      updateModeUI()
    case .bookmarks where bookmarks.indices.contains(indexPath.row):
      seekToAbsoluteTime(bookmarkTime(bookmarks[indexPath.row]))
      screenMode = .nowPlaying
      updateModeUI()
    default:
      break
    }
  }

  func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
    guard screenMode == .bookmarks, bookmarks.indices.contains(indexPath.row) else { return nil }
    let bookmark = bookmarks[indexPath.row]
    let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, done in
      self?.presentBookmarkEditor(bookmark)
      done(true)
    }
    edit.backgroundColor = accentColor
    let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, done in
      guard let self else { return }
      self.bookmarks.removeAll { $0.id == bookmark.id }
      self.onBookmarkChange?(AudiobookBookmarkChangeEvent(type: "remove", bookmark: bookmark))
      self.listTableView.reloadData()
      self.updateBookmarkButton()
      done(true)
    }
    return UISwipeActionsConfiguration(actions: [delete, edit])
  }
}

private final class ChapterSlider: UISlider {
  var markers: [Float] = [] {
    didSet { setNeedsDisplay() }
  }
  var markerColor = UIColor.black {
    didSet { setNeedsDisplay() }
  }

  override func draw(_ rect: CGRect) {
    super.draw(rect)
    guard let context = UIGraphicsGetCurrentContext() else { return }
    context.setStrokeColor(markerColor.cgColor)
    context.setLineWidth(1)
    let track = trackRect(forBounds: bounds)
    for marker in markers {
      let x = track.minX + CGFloat(marker) * track.width
      context.move(to: CGPoint(x: x, y: track.midY - 8))
      context.addLine(to: CGPoint(x: x, y: track.midY + 8))
      context.strokePath()
    }
  }
}

private struct AudioSettingsSelection {
  let theme: String
  let skipBackward: Double
  let skipForward: Double
  let continuousPlay: Bool
}

private final class AudioSettingsViewController: UIViewController {
  private let onChange: (AudioSettingsSelection) -> Void
  private var theme: String
  private var skipBackward: Double
  private var skipForward: Double
  private var continuousPlay: Bool

  init(selectedTheme: String, skipBackward: Double, skipForward: Double, continuousPlay: Bool, onChange: @escaping (AudioSettingsSelection) -> Void) {
    self.theme = selectedTheme
    self.skipBackward = skipBackward
    self.skipForward = skipForward
    self.continuousPlay = continuousPlay
    self.onChange = onChange
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = UIColor(red: 0.075, green: 0.078, blue: 0.086, alpha: 1)

    let title = UILabel()
    title.text = "Audio Settings"
    title.font = .boldSystemFont(ofSize: 32)
    title.textColor = .white
    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark"), for: .normal)
    close.tintColor = .white
    close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

    let header = UIStackView(arrangedSubviews: [title, UIView(), close])
    header.axis = .horizontal
    header.alignment = .center

    let stack = UIStackView(arrangedSubviews: [
      header,
      section("Skip backward interval", buttons(["5 sec", "15 sec", "30 sec"], selected: "\(Int(skipBackward)) sec") { [weak self] value in self?.skipBackward = Double(value.split(separator: " ").first ?? "15") ?? 15; self?.emit() }),
      section("Skip forward interval", buttons(["10 sec", "30 sec", "60 sec"], selected: "\(Int(skipForward)) sec") { [weak self] value in self?.skipForward = Double(value.split(separator: " ").first ?? "30") ?? 30; self?.emit() }),
      toggleRow()
    ])
    stack.axis = .vertical
    stack.spacing = 34
    view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
    ])
  }

  private func section(_ title: String, _ content: UIView) -> UIView {
    let label = UILabel()
    label.text = title
    label.font = .boldSystemFont(ofSize: 24)
    label.textColor = .white
    let stack = UIStackView(arrangedSubviews: [label, content])
    stack.axis = .vertical
    stack.spacing = 18
    return stack
  }

  private func buttons(_ values: [String], selected: String, onTap: @escaping (String) -> Void) -> UIView {
    let stack = UIStackView()
    stack.axis = .horizontal
    stack.spacing = 18
    stack.distribution = .fillEqually
    for value in values {
      let button = UIButton(type: .system)
      button.setTitle(value, for: .normal)
      button.titleLabel?.font = .systemFont(ofSize: 22)
      button.tintColor = .white
      button.layer.cornerRadius = 6
      button.layer.borderWidth = value == selected ? 2 : 1
      button.layer.borderColor = UIColor(red: 0.72, green: 0.53, blue: 0.38, alpha: 1).cgColor
      button.backgroundColor = value == selected
        ? UIColor(red: 0.72, green: 0.53, blue: 0.38, alpha: 1)
        : UIColor.white.withAlphaComponent(0.04)
      button.addAction(UIAction { _ in onTap(value) }, for: .touchUpInside)
      stack.addArrangedSubview(button)
      button.heightAnchor.constraint(equalToConstant: 62).isActive = true
    }
    return stack
  }

  private func toggleRow() -> UIView {
    let label = UILabel()
    label.text = "Continuous play"
    label.font = .systemFont(ofSize: 24)
    label.textColor = .white
    let toggle = UISwitch()
    toggle.isOn = continuousPlay
    toggle.addAction(UIAction { [weak self] action in
      guard let toggle = action.sender as? UISwitch else { return }
      self?.continuousPlay = toggle.isOn
      self?.emit()
    }, for: .valueChanged)
    let stack = UIStackView(arrangedSubviews: [toggle, label])
    stack.axis = .horizontal
    stack.alignment = .center
    stack.spacing = 16
    return section("Autoplay", stack)
  }

  private func emit() {
    onChange(.init(theme: theme, skipBackward: skipBackward, skipForward: skipForward, continuousPlay: continuousPlay))
  }

  @objc private func closeTapped() {
    dismiss(animated: true)
  }
}

private final class OptionsSheetViewController: UITableViewController {
  private let options: [String]
  private let onSelect: (String) -> Void

  init(title: String, options: [String], onSelect: @escaping (String) -> Void) {
    self.options = options
    self.onSelect = onSelect
    super.init(style: .insetGrouped)
    self.title = title
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    options.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
    cell.textLabel?.text = options[indexPath.row]
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    onSelect(options[indexPath.row])
    dismiss(animated: true)
  }
}
