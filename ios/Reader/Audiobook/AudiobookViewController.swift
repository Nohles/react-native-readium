import Combine
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

final class AudiobookViewController: UIViewController, PublicationReaderViewController, Loggable {
  weak var moduleDelegate: ReaderFormatModuleDelegate?
  var onPlaybackStateChange: ((AudiobookPlaybackState) -> Void)?

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
  private var skipBackwardInterval = 10.0
  private var skipForwardInterval = 10.0
  private var continuousPlay = true
  private var sleepTimerMode: SleepTimerMode = .off
  private var sleepTimer: Timer?

  private let backgroundColor = UIColor(red: 0.957, green: 0.945, blue: 0.925, alpha: 1)
  private let borderColor = UIColor(red: 0.63, green: 0.60, blue: 0.50, alpha: 1)

  private let coverImageView = UIImageView()
  private let placeholderLabel = UILabel()
  private let titleLabel = UILabel()
  private let subtitleLabel = UILabel()
  private let playButton = UIButton(type: .system)
  private let chapterLabel = UILabel()
  private let timelineSlider = ChapterSlider()
  private let elapsedLabel = UILabel()
  private let remainingLabel = UILabel()
  private let rateCaptionLabel = UILabel()

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
    audioNavigator.pause()
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = backgroundColor
    buildUI()
    loadCover()
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

  private func buildUI() {
    let backButton = iconButton("chevron.left", action: #selector(closeTapped))
    let settingsButton = iconButton("slider.horizontal.3", action: #selector(settingsTapped))

    view.addSubview(backButton)
    view.addSubview(settingsButton)
    backButton.translatesAutoresizingMaskIntoConstraints = false
    settingsButton.translatesAutoresizingMaskIntoConstraints = false

    coverImageView.contentMode = .scaleAspectFill
    coverImageView.clipsToBounds = true
    coverImageView.layer.cornerRadius = 4
    coverImageView.layer.borderWidth = 1
    coverImageView.layer.borderColor = UIColor(red: 0.42, green: 0.09, blue: 0.11, alpha: 1).cgColor
    coverImageView.backgroundColor = UIColor(red: 0.86, green: 0.83, blue: 0.72, alpha: 1)

    placeholderLabel.font = .boldSystemFont(ofSize: 42)
    placeholderLabel.textAlignment = .center
    placeholderLabel.textColor = .darkGray
    coverImageView.addSubview(placeholderLabel)
    placeholderLabel.translatesAutoresizingMaskIntoConstraints = false

    titleLabel.font = .boldSystemFont(ofSize: 20)
    titleLabel.textAlignment = .center
    titleLabel.text = publication.metadata.title

    subtitleLabel.font = .systemFont(ofSize: 18)
    subtitleLabel.textAlignment = .center
    subtitleLabel.numberOfLines = 2
    subtitleLabel.text = publication.metadata.subtitle

    let previousButton = iconButton("backward.end.fill", action: #selector(previousChapterTapped))
    let rewindButton = iconButton("gobackward.10", action: #selector(rewindTapped))
    configurePlayButton()
    let forwardButton = iconButton("goforward.10", action: #selector(forwardTapped))
    let nextButton = iconButton("forward.end.fill", action: #selector(nextChapterTapped))

    let controls = UIStackView(arrangedSubviews: [previousButton, rewindButton, playButton, forwardButton, nextButton])
    controls.axis = .horizontal
    controls.spacing = 28
    controls.alignment = .center
    controls.distribution = .equalCentering

    chapterLabel.font = .systemFont(ofSize: 18)
    chapterLabel.textAlignment = .center

    timelineSlider.minimumValue = 0
    timelineSlider.maximumValue = Float(max(duration, 1))
    timelineSlider.tintColor = .black
    timelineSlider.markerColor = .black
    timelineSlider.addTarget(self, action: #selector(timelineChanged), for: .valueChanged)

    elapsedLabel.font = .systemFont(ofSize: 16)
    elapsedLabel.text = "0:00"
    remainingLabel.font = .systemFont(ofSize: 16)
    remainingLabel.textAlignment = .right

    let timeRow = UIStackView(arrangedSubviews: [elapsedLabel, remainingLabel])
    timeRow.axis = .horizontal
    timeRow.distribution = .fillEqually

    let volumeButton = bottomButton("speaker.wave.2.fill", title: nil, action: #selector(volumeTapped))
    let rateButton = bottomButton("speedometer", title: nil, action: #selector(rateTapped))
    rateCaptionLabel.font = .boldSystemFont(ofSize: 12)
    rateCaptionLabel.textAlignment = .center
    let rateStack = UIStackView(arrangedSubviews: [rateButton, rateCaptionLabel])
    rateStack.axis = .vertical
    rateStack.spacing = 0
    let tocButton = bottomButton("list.bullet", title: nil, action: #selector(tocTapped))
    let sleepButton = bottomButton("alarm.fill", title: nil, action: #selector(sleepTapped))
    let bottomControls = UIStackView(arrangedSubviews: [volumeButton, rateStack, tocButton, sleepButton])
    bottomControls.axis = .horizontal
    bottomControls.spacing = 34
    bottomControls.alignment = .center
    bottomControls.distribution = .equalCentering

    let mainStack = UIStackView(arrangedSubviews: [
      coverImageView,
      titleLabel,
      subtitleLabel,
      controls,
      chapterLabel,
      timelineSlider,
      timeRow,
      bottomControls
    ])
    mainStack.axis = .vertical
    mainStack.alignment = .center
    mainStack.spacing = 18
    view.addSubview(mainStack)
    mainStack.translatesAutoresizingMaskIntoConstraints = false

    NSLayoutConstraint.activate([
      backButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      backButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
      settingsButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
      settingsButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

      mainStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      mainStack.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 90),
      mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 44),
      mainStack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -44),

      coverImageView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.40),
      coverImageView.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
      coverImageView.heightAnchor.constraint(equalTo: coverImageView.widthAnchor),
      placeholderLabel.centerXAnchor.constraint(equalTo: coverImageView.centerXAnchor),
      placeholderLabel.centerYAnchor.constraint(equalTo: coverImageView.centerYAnchor),

      controls.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -160),
      timelineSlider.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.78),
      timeRow.widthAnchor.constraint(equalTo: timelineSlider.widthAnchor),
      bottomControls.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, constant: -260)
    ])
  }

  private func configurePlayButton() {
    playButton.tintColor = .black
    playButton.setPreferredSymbolConfiguration(.init(pointSize: 34, weight: .bold), forImageIn: .normal)
    playButton.addTarget(self, action: #selector(playPauseTapped), for: .touchUpInside)
  }

  private func iconButton(_ systemName: String, action: Selector) -> UIButton {
    let button = UIButton(type: .system)
    button.tintColor = .black
    button.setImage(UIImage(systemName: systemName), for: .normal)
    button.setPreferredSymbolConfiguration(.init(pointSize: 26, weight: .bold), forImageIn: .normal)
    button.addTarget(self, action: action, for: .touchUpInside)
    return button
  }

  private func bottomButton(_ systemName: String, title: String?, action: Selector) -> UIButton {
    let button = iconButton(systemName, action: action)
    if let title = title {
      button.setTitle(title, for: .normal)
    }
    return button
  }

  private func configurePublicationData() {
    readingOrderLinks = publication.readingOrder
    var offset = 0.0
    for link in readingOrderLinks {
      readingOrderOffsets[baseHref(link.href)] = offset
      offset += link.duration ?? 0
    }
    duration = publication.metadata.duration ?? audioNavigator.totalDuration ?? offset

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
      }
    }.resume()
  }

  private func seekToAbsoluteTime(_ absoluteTime: Double) {
    let clamped = min(max(absoluteTime, 0), max(duration, 0))
    guard let target = locator(forAbsoluteTime: clamped) else { return }
    Task { @MainActor in
      _ = await audioNavigator.go(to: target, options: .animated)
    }
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
    evaluateSleepTimer()
    emitPlaybackState()
  }

  private func updatePlaybackUI() {
    timelineSlider.maximumValue = Float(max(duration, 1))
    timelineSlider.value = Float(min(currentPosition, duration))
    elapsedLabel.text = formatTime(currentPosition)
    remainingLabel.text = formatTime(duration)
    rateCaptionLabel.text = formatRate(playbackRate)
    chapterLabel.text = currentChapter()?.title ?? publication.metadata.title
    let imageName = isPlaying ? "pause.fill" : "play.fill"
    playButton.setImage(UIImage(systemName: imageName), for: .normal)
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
    return (readingOrderOffsets[baseHref(link.href)] ?? 0) + time
  }

  private func absoluteTime(forHref href: String) -> Double {
    (readingOrderOffsets[baseHref(href)] ?? 0) + fragmentTime(href)
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

  @objc private func closeTapped() {
    pause()
  }

  @objc private func settingsTapped() {
    let vc = AudioSettingsViewController(
      selectedTheme: traitCollection.userInterfaceStyle == .dark ? "Dark" : "Auto",
      skipBackward: skipBackwardInterval,
      skipForward: skipForwardInterval,
      continuousPlay: continuousPlay
    ) { [weak self] settings in
      guard let self else { return }
      self.skipBackwardInterval = settings.skipBackward
      self.skipForwardInterval = settings.skipForward
      self.continuousPlay = settings.continuousPlay
      self.applyTheme(settings.theme)
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

  @objc private func volumeTapped() {
    let vc = SliderSheetViewController(title: "Volume", value: Float(volume), range: 0...1) { [weak self] value in
      self?.setVolume(Double(value))
    }
    presentSheet(vc)
  }

  @objc private func rateTapped() {
    let vc = OptionsSheetViewController(title: "Playback Rate", options: ["0.75x", "1x", "1.25x", "1.5x", "2x"]) { [weak self] option in
      self?.setPlaybackRate(Double(option.replacingOccurrences(of: "x", with: "")) ?? 1)
    }
    presentSheet(vc)
  }

  @objc private func tocTapped() {
    let vc = TableOfContentsViewController(chapters: chapters, currentPosition: currentPosition) { [weak self] chapter in
      self?.seekToAbsoluteTime(chapter.time)
    }
    presentSheet(vc)
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

  private func applyTheme(_ theme: String) {
    let dark = theme == "Dark" || (theme == "Auto" && traitCollection.userInterfaceStyle == .dark)
    view.backgroundColor = dark ? .black : backgroundColor
    let foreground: UIColor = dark ? .white : .black
    [titleLabel, subtitleLabel, chapterLabel, elapsedLabel, remainingLabel, rateCaptionLabel].forEach { $0.textColor = foreground }
    timelineSlider.tintColor = foreground
    timelineSlider.markerColor = foreground
  }

  private func presentSheet(_ vc: UIViewController) {
    vc.modalPresentationStyle = .pageSheet
    if let sheet = vc.sheetPresentationController {
      sheet.detents = [.medium(), .large()]
      sheet.prefersGrabberVisible = true
    }
    present(vc, animated: true)
  }
}

extension AudiobookViewController: AudioNavigatorDelegate {
  func navigator(_ navigator: Navigator, locationDidChange locator: ReadiumShared.Locator) {
    subject.send(locator)
  }

  func navigator(_ navigator: Navigator, presentExternalURL url: URL) {}

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    moduleDelegate?.presentError(error, from: self)
  }

  func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    updatePlaybackInfo(info)
  }

  func navigator(_ navigator: AudioNavigator, shouldPlayNextResource info: MediaPlaybackInfo) -> Bool {
    continuousPlay
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
    view.backgroundColor = UIColor(red: 0.957, green: 0.945, blue: 0.925, alpha: 1)

    let title = UILabel()
    title.text = "Audio Settings"
    title.font = .boldSystemFont(ofSize: 32)
    let close = UIButton(type: .system)
    close.setImage(UIImage(systemName: "xmark"), for: .normal)
    close.tintColor = .black
    close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

    let header = UIStackView(arrangedSubviews: [title, UIView(), close])
    header.axis = .horizontal
    header.alignment = .center

    let stack = UIStackView(arrangedSubviews: [
      header,
      section("Themes", buttons(["Auto", "Light", "Dark"], selected: theme) { [weak self] value in self?.theme = value; self?.emit() }),
      section("Skip backward interval", buttons(["5 sec", "10 sec", "30 sec"], selected: "\(Int(skipBackward)) sec") { [weak self] value in self?.skipBackward = Double(value.split(separator: " ").first ?? "10") ?? 10; self?.emit() }),
      section("Skip forward interval", buttons(["5 sec", "10 sec", "30 sec"], selected: "\(Int(skipForward)) sec") { [weak self] value in self?.skipForward = Double(value.split(separator: " ").first ?? "10") ?? 10; self?.emit() }),
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
      button.tintColor = .black
      button.layer.cornerRadius = 6
      button.layer.borderWidth = value == selected ? 2 : 1
      button.layer.borderColor = UIColor(red: 0.63, green: 0.60, blue: 0.50, alpha: 1).cgColor
      if value == "Dark" {
        button.backgroundColor = .black
        button.tintColor = .white
      }
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

private final class SliderSheetViewController: UIViewController {
  private let titleText: String
  private let value: Float
  private let range: ClosedRange<Float>
  private let onChange: (Float) -> Void

  init(title: String, value: Float, range: ClosedRange<Float>, onChange: @escaping (Float) -> Void) {
    self.titleText = title
    self.value = value
    self.range = range
    self.onChange = onChange
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .systemBackground
    let label = UILabel()
    label.text = titleText
    label.font = .boldSystemFont(ofSize: 24)
    let slider = UISlider()
    slider.minimumValue = range.lowerBound
    slider.maximumValue = range.upperBound
    slider.value = value
    slider.addAction(UIAction { [weak self] action in
      guard let slider = action.sender as? UISlider else { return }
      self?.onChange(slider.value)
    }, for: .valueChanged)
    let stack = UIStackView(arrangedSubviews: [label, slider])
    stack.axis = .vertical
    stack.spacing = 24
    view.addSubview(stack)
    stack.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
      stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
      stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32)
    ])
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

private final class TableOfContentsViewController: UITableViewController {
  private let chapters: [AudiobookChapter]
  private let currentPosition: Double
  private let onSelect: (AudiobookChapter) -> Void

  init(chapters: [AudiobookChapter], currentPosition: Double, onSelect: @escaping (AudiobookChapter) -> Void) {
    self.chapters = chapters
    self.currentPosition = currentPosition
    self.onSelect = onSelect
    super.init(style: .plain)
    title = "Table of Contents"
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

  override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    chapters.count
  }

  override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let chapter = chapters[indexPath.row]
    let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
    cell.textLabel?.text = String(repeating: "  ", count: chapter.depth) + chapter.title
    cell.detailTextLabel?.text = formatTime(chapter.time)
    if chapter.time <= currentPosition && (indexPath.row == chapters.count - 1 || chapters[indexPath.row + 1].time > currentPosition) {
      cell.accessoryType = .checkmark
    }
    return cell
  }

  override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
    onSelect(chapters[indexPath.row])
    dismiss(animated: true)
  }

  private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}
