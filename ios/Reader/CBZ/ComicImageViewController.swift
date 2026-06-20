import Combine
import ReadiumShared
import UIKit

final class ComicImageViewController: UIViewController, ReadiumReaderHosting {
  let publication: Publication
  let bookId: String
  var viewController: UIViewController { self }

  private let subject = PassthroughSubject<ReadiumShared.Locator, Never>()
  lazy var publisher = subject.eraseToAnyPublisher()

  private let scrollView = UIScrollView()
  private let stackView = UIStackView()
  private let loadingIndicator = UIActivityIndicatorView(style: .large)
  private let links: [RLink]
  private var images: [UIImage?]
  private var imageViews: [UIImageView] = []
  private var imageSizeConstraints: [NSLayoutConstraint] = []
  private var initialLocator: ReadiumShared.Locator?
  private var currentIndex = 0
  private var preferences: Preferences?
  private var isApplyingProgrammaticScroll = false

  init(
    publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String
  ) {
    self.publication = publication
    self.bookId = bookId
    self.initialLocator = locator
    let bitmapLinks = publication.readingOrder.filter { $0.mediaType?.isBitmap == true }
    self.links = bitmapLinks.isEmpty ? publication.readingOrder : bitmapLinks
    self.images = Array(repeating: nil, count: links.count)
    super.init(nibName: nil, bundle: nil)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureScrollView()
    configureLoadingIndicator()
    Task { await loadImages() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    applyLayoutForCurrentPreferences()
  }

  func updatePreferences(_ preferences: Preferences) {
    self.preferences = preferences
    guard isViewLoaded else { return }
    applyLayoutForCurrentPreferences()
    navigateToIndex(currentIndex, animated: false, emit: false)
  }

  func positions() -> [ReadiumShared.Locator] {
    links.indices.map { locator(for: $0) }
  }

  @MainActor
  func goTo(_ locator: ReadiumShared.Locator) async {
    let index = index(for: locator) ?? currentIndex
    navigateToIndex(index, animated: true)
  }

  @MainActor
  func goForward() async {
    let step = isDoublePageMode ? 2 : 1
    navigateToIndex(min(currentIndex + step, max(links.count - 1, 0)), animated: true)
  }

  @MainActor
  func goBackward() async {
    let step = isDoublePageMode ? 2 : 1
    navigateToIndex(max(currentIndex - step, 0), animated: true)
  }

  private func configureScrollView() {
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.delegate = self
    scrollView.alwaysBounceVertical = true
    scrollView.alwaysBounceHorizontal = true
    view.addSubview(scrollView)

    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.alignment = .center
    scrollView.addSubview(stackView)

    NSLayoutConstraint.activate([
      scrollView.topAnchor.constraint(equalTo: view.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      stackView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
      stackView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
      stackView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
      stackView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
    ])
  }

  private func configureLoadingIndicator() {
    loadingIndicator.translatesAutoresizingMaskIntoConstraints = false
    loadingIndicator.color = .white
    loadingIndicator.startAnimating()
    view.addSubview(loadingIndicator)
    NSLayoutConstraint.activate([
      loadingIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
      loadingIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
    ])
  }

  private func loadImages() async {
    await MainActor.run {
      imageViews = links.enumerated().map { index, _ in
        let imageView = UIImageView()
        imageView.tag = index
        imageView.contentMode = .scaleAspectFit
        imageView.clipsToBounds = true
        imageView.backgroundColor = .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
      }
      rebuildArrangedSubviews()
    }

    for (index, link) in links.enumerated() {
      guard
        let resource = publication.get(link),
        let data = try? await resource.read().get(),
        let image = UIImage(data: data)
      else {
        continue
      }

      await MainActor.run {
        images[index] = image
        imageViews[index].image = image
        applyLayoutForCurrentPreferences()
      }
    }

    await MainActor.run {
      loadingIndicator.stopAnimating()
      loadingIndicator.removeFromSuperview()
      let startIndex = initialLocator.flatMap(index(for:)) ?? 0
      navigateToIndex(startIndex, animated: false)
      initialLocator = nil
    }
  }

  private func rebuildArrangedSubviews() {
    stackView.arrangedSubviews.forEach {
      stackView.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }

    if isPaginatedMode {
      addPaginatedSubviews()
    } else {
      imageViews.forEach { stackView.addArrangedSubview($0) }
    }

    applyLayoutForCurrentPreferences()
  }

  private func addPaginatedSubviews() {
    guard !imageViews.isEmpty else { return }
    if isDoublePageMode, currentIndex + 1 < imageViews.count {
      let spread = UIStackView(arrangedSubviews: [imageViews[currentIndex], imageViews[currentIndex + 1]])
      spread.axis = .horizontal
      spread.alignment = .center
      spread.distribution = .fillEqually
      spread.spacing = gap
      spread.translatesAutoresizingMaskIntoConstraints = false
      stackView.addArrangedSubview(spread)
    } else {
      stackView.addArrangedSubview(imageViews[currentIndex])
    }
  }

  private func applyLayoutForCurrentPreferences() {
    guard isViewLoaded else { return }

    imageSizeConstraints.forEach { $0.isActive = false }
    imageSizeConstraints.removeAll()

    stackView.spacing = isPaginatedMode ? 0 : gap
    stackView.axis = isHorizontalScrollMode ? .horizontal : .vertical
    stackView.distribution = .fill
    scrollView.isPagingEnabled = isPaginatedMode
    scrollView.showsVerticalScrollIndicator = !isHorizontalScrollMode
    scrollView.showsHorizontalScrollIndicator = isHorizontalScrollMode

    if isPaginatedMode {
      rebuildPaginatedSubviewsIfNeeded()
    }

    let viewport = scrollView.bounds.size
    guard viewport.width > 0, viewport.height > 0 else { return }

    if isHorizontalScrollMode || isPaginatedMode {
      imageSizeConstraints.append(stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
    } else {
      imageSizeConstraints.append(stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
    }

    for (index, imageView) in imageViews.enumerated() where imageView.superview != nil {
      let imageSize = images[index]?.size ?? CGSize(width: viewport.width, height: viewport.height)
      let aspect = imageSize.width > 0 ? imageSize.height / imageSize.width : 1

      if isHorizontalScrollMode || isPaginatedMode {
        let width = isDoublePageMode && isPaginatedMode ? max((viewport.width - gap) / 2, 1) : viewport.width
        imageSizeConstraints.append(imageView.widthAnchor.constraint(equalToConstant: width))
        imageSizeConstraints.append(imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
      } else {
        imageSizeConstraints.append(imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
        imageSizeConstraints.append(imageView.heightAnchor.constraint(equalToConstant: verticalImageHeight(for: imageSize, aspect: aspect, viewport: viewport)))
      }
    }

    NSLayoutConstraint.activate(imageSizeConstraints)
  }

  private func rebuildPaginatedSubviewsIfNeeded() {
    let visibleTags = stackView.arrangedSubviews.flatMap { view -> [Int] in
      if let imageView = view as? UIImageView {
        return [imageView.tag]
      }
      if let spread = view as? UIStackView {
        return spread.arrangedSubviews.compactMap { ($0 as? UIImageView)?.tag }
      }
      return []
    }

    let expected = isDoublePageMode && currentIndex + 1 < imageViews.count
      ? [currentIndex, currentIndex + 1]
      : [currentIndex]

    if visibleTags != expected {
      rebuildArrangedSubviews()
    }
  }

  private func verticalImageHeight(for imageSize: CGSize, aspect: CGFloat, viewport: CGSize) -> CGFloat {
    switch preferences?.fit {
    case "page":
      return min(viewport.height, viewport.width * aspect)
    case "width":
      return viewport.width * aspect
    default:
      return max(1, viewport.width * aspect)
    }
  }

  private func navigateToIndex(_ index: Int, animated: Bool, emit: Bool = true) {
    guard !links.isEmpty else { return }
    currentIndex = min(max(index, 0), links.count - 1)

    if isPaginatedMode {
      rebuildArrangedSubviews()
      scrollView.setContentOffset(.zero, animated: false)
    } else if imageViews.indices.contains(currentIndex) {
      let targetView = imageViews[currentIndex]
      let rect = targetView.convert(targetView.bounds, to: scrollView)
      let offset: CGPoint
      if isHorizontalScrollMode {
        offset = CGPoint(x: max(rect.minX, 0), y: 0)
      } else {
        offset = CGPoint(x: 0, y: max(rect.minY, 0))
      }
      isApplyingProgrammaticScroll = true
      scrollView.setContentOffset(offset, animated: animated)
      if !animated {
        isApplyingProgrammaticScroll = false
      }
    }

    if emit {
      subject.send(locator(for: currentIndex))
    }
  }

  private func updateCurrentIndexFromScrollPosition() {
    guard !isPaginatedMode, !links.isEmpty else { return }

    let probe = isHorizontalScrollMode
      ? CGPoint(x: scrollView.contentOffset.x + scrollView.bounds.width / 2, y: scrollView.bounds.height / 2)
      : CGPoint(x: scrollView.bounds.width / 2, y: scrollView.contentOffset.y + scrollView.bounds.height / 2)

    var closestIndex = currentIndex
    var closestDistance = CGFloat.greatestFiniteMagnitude

    for imageView in imageViews {
      let frame = imageView.convert(imageView.bounds, to: scrollView)
      let center = isHorizontalScrollMode ? frame.midX : frame.midY
      let target = isHorizontalScrollMode ? probe.x : probe.y
      let distance = abs(center - target)
      if distance < closestDistance {
        closestDistance = distance
        closestIndex = imageView.tag
      }
    }

    guard closestIndex != currentIndex else { return }
    currentIndex = closestIndex
    subject.send(locator(for: closestIndex))
  }

  private func index(for locator: ReadiumShared.Locator) -> Int? {
    if let position = locator.locations.position, position > 0 {
      return min(position - 1, max(links.count - 1, 0))
    }

    return links.firstIndex { link in
      link.url().normalized.string == locator.href.normalized.string
        || link.url().string == locator.href.string
        || link.href == locator.href.string
    }
  }

  private func locator(for index: Int) -> ReadiumShared.Locator {
    let link = links[index]
    let total = max(links.count, 1)
    let totalProgression = total > 1 ? Double(index) / Double(total - 1) : 0
    return ReadiumShared.Locator(
      href: link.url(),
      mediaType: link.mediaType ?? MediaType("image/jpeg")!,
      title: link.title,
      locations: .init(
        progression: 0,
        totalProgression: totalProgression,
        position: index + 1
      )
    )
  }

  private var isPaginatedMode: Bool {
    !(preferences?.scroll ?? false)
  }

  private var isDoublePageMode: Bool {
    preferences?.spread == "always"
  }

  private var isHorizontalScrollMode: Bool {
    preferences?.comicReadingMode == "continuousHorizontal"
  }

  private var gap: CGFloat {
    CGFloat(max(preferences?.pageMargins ?? 0, 0) * 16)
  }
}

extension ComicImageViewController: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    guard !isApplyingProgrammaticScroll else { return }
    updateCurrentIndexFromScrollPosition()
  }

  func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
    isApplyingProgrammaticScroll = false
    updateCurrentIndexFromScrollPosition()
  }

  func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
    isApplyingProgrammaticScroll = false
  }
}
