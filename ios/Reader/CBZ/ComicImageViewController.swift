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
  private var isClampingContentOffset = false
  private var loadingIndices = Set<Int>()

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
    applyTheme()
    configureScrollView()
    configureLoadingIndicator()
    Task { await loadImages() }
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    applyLayoutForCurrentPreferences()
  }

  func updatePreferences(_ preferences: Preferences) {
    let changedPagination = self.preferences?.scroll != preferences.scroll
    self.preferences = preferences
    guard isViewLoaded else { return }
    applyTheme()
    if changedPagination {
      rebuildArrangedSubviews()
    }
    applyLayoutForCurrentPreferences()
    navigateToIndex(currentIndex, animated: false, emit: false)
    Task { await loadImages(around: currentIndex) }
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
    if isWebtoonMode {
      scrollWebtoon(forward: true)
      return
    }
    let step = isDoublePageMode ? 2 : 1
    navigateToIndex(min(currentIndex + step, max(links.count - 1, 0)), animated: true)
  }

  @MainActor
  func goBackward() async {
    if isWebtoonMode {
      scrollWebtoon(forward: false)
      return
    }
    let step = isDoublePageMode ? 2 : 1
    navigateToIndex(max(currentIndex - step, 0), animated: true)
  }

  private func configureScrollView() {
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.delegate = self
    scrollView.contentInsetAdjustmentBehavior = .never
    scrollView.isDirectionalLockEnabled = true
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
        imageView.backgroundColor = self.readerBackgroundColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
      }
      rebuildArrangedSubviews()
      applyLayoutForCurrentPreferences()
    }

    let startIndex = initialLocator.flatMap(index(for:)) ?? 0
    await loadImages(around: startIndex)

    await MainActor.run {
      loadingIndicator.stopAnimating()
      loadingIndicator.removeFromSuperview()
      navigateToIndex(startIndex, animated: false)
      initialLocator = nil
    }
  }

  @MainActor
  private func loadImages(around index: Int) async {
    guard !links.isEmpty else { return }
    let amount = isPaginatedMode
      ? max(isDoublePageMode ? 1 : 0, imagePreloadAmount)
      : imagePreloadAmount
    let lowerBound = max(0, index - amount)
    let upperBound = min(links.count - 1, index + amount + (isDoublePageMode ? 1 : 0))

    for index in lowerBound...upperBound {
      guard images[index] == nil, !loadingIndices.contains(index) else { continue }
      loadingIndices.insert(index)
      let link = links[index]
      guard
        let resource = publication.get(link),
        let data = try? await resource.read().get(),
        let image = UIImage(data: data)
      else {
        loadingIndices.remove(index)
        continue
      }

      images[index] = image
      loadingIndices.remove(index)
      imageViews[index].image = image
      applyLayoutForCurrentPreferences()
    }
  }

  private func rebuildArrangedSubviews() {
    clearImageSizeConstraints()
    removeArrangedSubviews(from: stackView)

    if isPaginatedMode {
      addPaginatedSubviews()
    } else {
      imageViews.forEach { stackView.addArrangedSubview($0) }
    }
  }

  private func addPaginatedSubviews() {
    guard !imageViews.isEmpty else { return }
    for index in visiblePageIndices {
      stackView.addArrangedSubview(imageViews[index])
    }
  }

  private func removeArrangedSubviews(from stack: UIStackView) {
    for arrangedSubview in stack.arrangedSubviews {
      if let nestedStack = arrangedSubview as? UIStackView {
        removeArrangedSubviews(from: nestedStack)
      }
      stack.removeArrangedSubview(arrangedSubview)
      arrangedSubview.removeFromSuperview()
    }
  }

  private func clearImageSizeConstraints() {
    NSLayoutConstraint.deactivate(imageSizeConstraints)
    imageSizeConstraints.removeAll()
  }

  private func applyLayoutForCurrentPreferences() {
    guard isViewLoaded else { return }

    clearImageSizeConstraints()

    stackView.spacing = gap
    stackView.axis = isPaginatedMode || isHorizontalScrollMode ? .horizontal : .vertical
    stackView.distribution = isPaginatedMode ? .equalCentering : .fill
    scrollView.isPagingEnabled = isPaginatedMode
    applyTheme()
    applyScrollAxisPolicy()

    if isPaginatedMode {
      rebuildPaginatedSubviewsIfNeeded()
    }

    let viewport = scrollView.bounds.size
    guard viewport.width > 0, viewport.height > 0 else { return }

    if isPaginatedMode {
      imageSizeConstraints.append(stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
      imageSizeConstraints.append(stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
    } else if isHorizontalScrollMode {
      imageSizeConstraints.append(stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
    } else {
      imageSizeConstraints.append(stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
    }

    for (index, imageView) in imageViews.enumerated() where imageView.superview != nil {
      let naturalSize = images[index]?.size ?? viewport
      let displaySize = displayedImageSize(for: naturalSize, viewport: viewport)
      imageSizeConstraints.append(imageView.widthAnchor.constraint(equalToConstant: displaySize.width))
      imageSizeConstraints.append(imageView.heightAnchor.constraint(equalToConstant: displaySize.height))
    }

    NSLayoutConstraint.activate(imageSizeConstraints)
    clampContentOffsetForCurrentMode()
  }

  private func rebuildPaginatedSubviewsIfNeeded() {
    let visibleTags = stackView.arrangedSubviews.compactMap { ($0 as? UIImageView)?.tag }

    let expected = visiblePageIndices

    if visibleTags != expected {
      rebuildArrangedSubviews()
    }
  }

  private func navigateToIndex(_ index: Int, animated: Bool, emit: Bool = true) {
    guard !links.isEmpty else { return }
    currentIndex = min(max(index, 0), links.count - 1)
    Task { await loadImages(around: currentIndex) }

    if isPaginatedMode {
      rebuildArrangedSubviews()
      applyLayoutForCurrentPreferences()
      scrollView.setContentOffset(.zero, animated: false)
    } else if imageViews.indices.contains(currentIndex) {
      let targetView = imageViews[currentIndex]
      let rect = targetView.convert(targetView.bounds, to: scrollView)
      let offset: CGPoint
      if isHorizontalScrollMode {
        offset = CGPoint(x: max(rect.midX - scrollView.bounds.width / 2, 0), y: 0)
      } else {
        offset = CGPoint(x: 0, y: max(rect.midY - scrollView.bounds.height / 2, 0))
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
    Task { await loadImages(around: closestIndex) }
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

  private var isWebtoonMode: Bool {
    preferences?.comicReadingMode == "webtoon"
  }

  private var isRTL: Bool {
    preferences?.readingProgression == "rtl"
  }

  private var visiblePageIndices: [Int] {
    guard imageViews.indices.contains(currentIndex) else { return [] }
    guard isDoublePageMode else { return [currentIndex] }
    if isRTL {
      return currentIndex > 0 ? [currentIndex, currentIndex - 1] : [currentIndex]
    }
    return currentIndex + 1 < imageViews.count
      ? [currentIndex, currentIndex + 1]
      : [currentIndex]
  }

  private var gap: CGFloat {
    CGFloat(max(preferences?.pageMargins ?? 0, 0) * 16)
  }

  private var imagePreloadAmount: Int {
    Int(min(max(preferences?.comicImagePreloadAmount ?? 5, 0), 10))
  }

  private var readerBackgroundColor: UIColor {
    UIColor(readerHex: preferences?.backgroundColor) ?? .black
  }

  private func applyTheme() {
    let color = readerBackgroundColor
    view.backgroundColor = color
    scrollView.backgroundColor = color
    stackView.backgroundColor = color
    imageViews.forEach { $0.backgroundColor = color }
  }

  private func displayedImageSize(for naturalSize: CGSize, viewport: CGSize) -> CGSize {
    let naturalWidth = max(naturalSize.width, 1)
    let naturalHeight = max(naturalSize.height, 1)
    let pageWidth = isDoublePageMode && isPaginatedMode
      ? max((viewport.width - gap) / 2, 1)
      : viewport.width
    let scaleType = preferences?.comicScaleType ?? "originalSize"
    let widthLimitApplies = scaleType == "fitWidth" || scaleType == "fitScreen"
    let widthPercent = CGFloat(min(max(preferences?.comicWidthLimitPercent ?? 50, 10), 100) / 100)
    let availableWidth = max(
      1,
      pageWidth * ((preferences?.comicWidthLimitEnabled == true && widthLimitApplies) ? widthPercent : 1)
    )
    let capHeight = isPaginatedMode || isHorizontalScrollMode
    let widthScale = availableWidth / naturalWidth
    let heightScale = viewport.height / naturalHeight
    let scale: CGFloat

    switch scaleType {
    case "fitWidth":
      scale = capHeight ? min(widthScale, heightScale) : widthScale
    case "fitHeight":
      scale = min(heightScale, widthScale)
    case "fitScreen":
      scale = min(widthScale, heightScale)
    default:
      var originalScale = min(1, widthScale)
      if capHeight {
        originalScale = min(originalScale, heightScale)
      }
      scale = originalScale
    }

    let canStretch = preferences?.comicStretchSmallPages == true && scaleType != "originalSize"
    let widthDriven = scaleType == "fitWidth" || scaleType == "fitScreen"
    let effectiveScale = canStretch || widthDriven
      ? scale
      : min(scale, 1)
    return CGSize(
      width: max(1, naturalWidth * effectiveScale),
      height: max(1, naturalHeight * effectiveScale)
    )
  }

  private func scrollWebtoon(forward: Bool) {
    let amount = CGFloat(min(max(preferences?.comicScrollAmountPercent ?? 95, 10), 100) / 100)
    let delta = scrollView.bounds.height * amount * (forward ? 1 : -1)
    let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
    let targetY = min(max(scrollView.contentOffset.y + delta, 0), maxY)
    isApplyingProgrammaticScroll = true
    scrollView.setContentOffset(CGPoint(x: 0, y: targetY), animated: true)
  }

  private func applyScrollAxisPolicy() {
    if isPaginatedMode {
      scrollView.alwaysBounceVertical = false
      scrollView.alwaysBounceHorizontal = false
      scrollView.bounces = false
      scrollView.showsVerticalScrollIndicator = false
      scrollView.showsHorizontalScrollIndicator = false
      return
    }

    scrollView.bounces = true
    if isHorizontalScrollMode {
      scrollView.alwaysBounceVertical = false
      scrollView.alwaysBounceHorizontal = true
      scrollView.showsVerticalScrollIndicator = false
      scrollView.showsHorizontalScrollIndicator = true
    } else {
      scrollView.alwaysBounceVertical = true
      scrollView.alwaysBounceHorizontal = false
      scrollView.showsVerticalScrollIndicator = true
      scrollView.showsHorizontalScrollIndicator = false
    }
  }

  private func clampContentOffsetForCurrentMode() {
    guard !isClampingContentOffset else { return }

    let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
    let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
    let current = scrollView.contentOffset
    let clamped: CGPoint

    if isPaginatedMode {
      clamped = .zero
    } else if isHorizontalScrollMode {
      clamped = CGPoint(x: min(max(current.x, 0), maxX), y: 0)
    } else {
      clamped = CGPoint(x: 0, y: min(max(current.y, 0), maxY))
    }

    guard current != clamped else { return }
    isClampingContentOffset = true
    scrollView.setContentOffset(clamped, animated: false)
    isClampingContentOffset = false
  }
}

private extension UIColor {
  convenience init?(readerHex value: String?) {
    guard let value else { return nil }
    let hex = value.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    guard hex.count == 6, let raw = UInt64(hex, radix: 16) else { return nil }
    self.init(
      red: CGFloat((raw >> 16) & 0xFF) / 255,
      green: CGFloat((raw >> 8) & 0xFF) / 255,
      blue: CGFloat(raw & 0xFF) / 255,
      alpha: 1
    )
  }
}

extension ComicImageViewController: UIScrollViewDelegate {
  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    clampContentOffsetForCurrentMode()
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
