import Combine
import SafariServices
import UIKit
import ReadiumNavigator
import ReadiumShared

final class AudioViewController: UIViewController, AudioNavigatorDelegate, Loggable {

  weak var moduleDelegate: ReaderFormatModuleDelegate?

  let navigator: Navigator
  let publication: Publication
  let bookId: String

  private let audioNavigator: AudioNavigator
  private let subject = PassthroughSubject<ReadiumShared.Locator, Never>()
  lazy var publisher = subject.eraseToAnyPublisher()

  private let coverImageView = UIImageView()
  private let titleLabel = UILabel()
  private let authorLabel = UILabel()
  private let timeLabel = UILabel()
  private let progressSlider = UISlider()
  private let playPauseButton = UIButton(type: .system)
  private let previousButton = UIButton(type: .system)
  private let nextButton = UIButton(type: .system)
  private let rewindButton = UIButton(type: .system)
  private let forwardButton = UIButton(type: .system)
  private var isScrubbing = false

  init(
    publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String
  ) throws {
    self.publication = publication
    self.bookId = bookId

    let navigator = AudioNavigator(
      publication: publication,
      initialLocation: locator
    )
    self.audioNavigator = navigator
    self.navigator = navigator

    super.init(nibName: nil, bundle: nil)

    navigator.delegate = self
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()

    view.backgroundColor = .systemBackground
    configureUI()
    loadCover()
    updatePlaybackUI(info: audioNavigator.playbackInfo)
  }

  override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    audioNavigator.play()
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    audioNavigator.pause()
  }

  private func configureUI() {
    titleLabel.font = .preferredFont(forTextStyle: .title2)
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 0
    titleLabel.text = publication.metadata.title

    authorLabel.font = .preferredFont(forTextStyle: .body)
    authorLabel.textAlignment = .center
    authorLabel.textColor = .secondaryLabel
    authorLabel.numberOfLines = 0
    authorLabel.text = publication.metadata.authors.map(\.name).joined(separator: ", ")

    coverImageView.contentMode = .scaleAspectFit
    coverImageView.backgroundColor = .secondarySystemBackground
    coverImageView.layer.cornerRadius = 8
    coverImageView.clipsToBounds = true

    timeLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
    timeLabel.textAlignment = .center
    timeLabel.textColor = .secondaryLabel

    progressSlider.addTarget(self, action: #selector(sliderEditingChanged), for: .valueChanged)
    progressSlider.addTarget(self, action: #selector(sliderEditingEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

    configureControl(playPauseButton, systemName: "pause.fill", action: #selector(togglePlayPause))
    configureControl(previousButton, systemName: "backward.fill", action: #selector(playPrevious))
    configureControl(nextButton, systemName: "forward.fill", action: #selector(playNext))
    configureControl(rewindButton, systemName: "gobackward.10", action: #selector(rewind))
    configureControl(forwardButton, systemName: "goforward.30", action: #selector(fastForward))

    let controls = UIStackView(arrangedSubviews: [rewindButton, previousButton, playPauseButton, nextButton, forwardButton])
    controls.axis = .horizontal
    controls.alignment = .center
    controls.distribution = .equalSpacing

    let stack = UIStackView(arrangedSubviews: [
      coverImageView,
      titleLabel,
      authorLabel,
      progressSlider,
      timeLabel,
      controls,
    ])
    stack.axis = .vertical
    stack.spacing = 16
    stack.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(stack)

    NSLayoutConstraint.activate([
      stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
      stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
      stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
      coverImageView.heightAnchor.constraint(equalToConstant: 220),
    ])
  }

  private func configureControl(_ button: UIButton, systemName: String, action: Selector) {
    let config = UIImage.SymbolConfiguration(pointSize: 28, weight: .medium)
    button.setImage(UIImage(systemName: systemName, withConfiguration: config), for: .normal)
    button.addTarget(self, action: action, for: .touchUpInside)
  }

  private func loadCover() {
    Task {
      let image = try? await publication.cover().get()
      await MainActor.run {
        coverImageView.image = image
      }
    }
  }

  private func updatePlaybackUI(info: MediaPlaybackInfo) {
    previousButton.isEnabled = audioNavigator.canGoBackward
    nextButton.isEnabled = audioNavigator.canGoForward

    let playImage = info.state == .paused ? "play.fill" : "pause.fill"
    configureControl(playPauseButton, systemName: playImage, action: #selector(togglePlayPause))

    if let duration = info.duration, duration > 0 {
      if !isScrubbing {
        progressSlider.value = Float(info.time / duration)
      }
      timeLabel.text = "\(formatTime(info.time)) / \(formatTime(duration))"
    } else {
      timeLabel.text = formatTime(info.time)
    }
  }

  private func formatTime(_ time: Double) -> String {
    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .positional
    formatter.zeroFormattingBehavior = .pad
    formatter.allowedUnits = time > 3600 ? [.hour, .minute, .second] : [.minute, .second]
    return formatter.string(from: time) ?? "00:00"
  }

  @objc private func togglePlayPause() {
    audioNavigator.playPause()
  }

  @objc private func playPrevious() {
    Task { await audioNavigator.goBackward() }
  }

  @objc private func playNext() {
    Task { await audioNavigator.goForward() }
  }

  @MainActor
  func goTo(_ locator: ReadiumShared.Locator) async {
    _ = await audioNavigator.go(to: locator, options: .animated)
  }

  @MainActor
  func goForward() async {
    _ = await audioNavigator.goForward(options: .animated)
  }

  @MainActor
  func goBackward() async {
    _ = await audioNavigator.goBackward(options: .animated)
  }

  @objc private func rewind() {
    Task { await audioNavigator.seek(by: -10) }
  }

  @objc private func fastForward() {
    Task { await audioNavigator.seek(by: 30) }
  }

  @objc private func sliderEditingChanged() {
    isScrubbing = true
  }

  @objc private func sliderEditingEnded() {
    isScrubbing = false
    guard let duration = audioNavigator.playbackInfo.duration else { return }
    let time = Double(progressSlider.value) * duration
    Task { await audioNavigator.seek(to: time) }
  }

  // MARK: - AudioNavigatorDelegate

  func navigator(_ navigator: AudioNavigator, playbackDidChange info: MediaPlaybackInfo) {
    updatePlaybackUI(info: info)
  }

  func navigator(_ navigator: Navigator, locationDidChange locator: ReadiumShared.Locator) {
    subject.send(locator)
  }

  func navigator(_ navigator: Navigator, presentExternalURL url: URL) {
    guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
    present(SFSafariViewController(url: url), animated: true)
  }

  func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
    moduleDelegate?.presentError(error, from: self)
  }
}
