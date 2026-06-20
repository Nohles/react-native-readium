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
  private let previousChapterBoundaryView = ComicChapterBoundaryView(direction: .previous)
  private let nextChapterBoundaryView = ComicChapterBoundaryView(direction: .next)
  private let links: [RLink]
  private var images: [UIImage?]
  private var loadingImageIndices = Set<Int>()
  private var imageViews: [UIImageView] = []
  private var imageSizeConstraints: [NSLayoutConstraint] = []
  private var boundarySizeConstraints: [NSLayoutConstraint] = []
  private var initialLocator: ReadiumShared.Locator?
  private var currentIndex = 0
  private var preferences: Preferences?
  private var isApplyingProgrammaticScroll = false
  private var isClampingContentOffset = false
  private var lastAppliedBoundaryTarget: String?

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
    applyThemeColors()
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

  private func applyThemeColors() {
    let backgroundColor = preferences?.backgroundColor.flatMap(UIColor.fromCSS) ?? .black
    view.backgroundColor = backgroundColor
    scrollView.backgroundColor = backgroundColor
    stackView.backgroundColor = backgroundColor
    imageViews.forEach { $0.backgroundColor = backgroundColor }
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
        imageView.backgroundColor = preferences?.backgroundColor.flatMap(UIColor.fromCSS) ?? .black
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
      }
      applyThemeColors()
      rebuildArrangedSubviews()
    }

    let startIndex = await MainActor.run {
      let startIndex = initialLocator.flatMap(index(for:)) ?? 0
      navigateToIndex(startIndex, animated: false, emit: false)
      initialLocator = nil
      return startIndex
    }

    await preloadImages(around: startIndex)

    await MainActor.run {
      loadingIndicator.stopAnimating()
      loadingIndicator.removeFromSuperview()
      subject.send(locator(for: currentIndex))
    }
  }

  private func preloadImages(around index: Int) async {
    guard !links.isEmpty else { return }
    let preloadAmount = await MainActor.run { imagePreloadAmount }
    let lowerBound = max(0, index - preloadAmount)
    let upperBound = min(links.count - 1, index + preloadAmount)

    await withTaskGroup(of: Void.self) { group in
      for imageIndex in lowerBound...upperBound {
        group.addTask { [weak self] in
          await self?.loadImageIfNeeded(at: imageIndex)
        }
      }
    }
  }

  private func loadImageIfNeeded(at index: Int) async {
    let shouldLoad = await MainActor.run { () -> Bool in
      guard links.indices.contains(index), images[index] == nil else { return false }
      guard !loadingImageIndices.contains(index) else { return false }
      loadingImageIndices.insert(index)
      return true
    }
    guard shouldLoad else { return }

    let link = links[index]
    let image: UIImage?
    if
      let resource = publication.get(link),
      let data = try? await resource.read().get()
    {
      image = UIImage(data: data)
    } else {
      image = nil
    }

    await MainActor.run {
      loadingImageIndices.remove(index)
      images[index] = image
      if imageViews.indices.contains(index) {
        imageViews[index].image = image
      }
      applyLayoutForCurrentPreferences()
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
      addScrollableSubviews()
    }

    applyLayoutForCurrentPreferences()
  }

  private func addScrollableSubviews() {
    guard !imageViews.isEmpty else { return }

    if shouldShowPreviousChapterBoundary {
      stackView.addArrangedSubview(previousChapterBoundaryView)
    }

    for index in visibleChapterRange {
      stackView.addArrangedSubview(imageViews[index])
    }

    if shouldShowNextChapterBoundary {
      stackView.addArrangedSubview(nextChapterBoundaryView)
    }
  }

  private func addPaginatedSubviews() {
    guard !imageViews.isEmpty else { return }
    let pageIndices = paginatedPageIndices()
    if pageIndices.count > 1 {
      let spread = UIStackView(arrangedSubviews: pageIndices.map { imageViews[$0] })
      spread.axis = .horizontal
      spread.alignment = .center
      spread.distribution = isOriginalSizeMode ? .fill : .fillEqually
      spread.spacing = gap
      spread.translatesAutoresizingMaskIntoConstraints = false
      stackView.addArrangedSubview(spread)
    } else if let pageIndex = pageIndices.first {
      stackView.addArrangedSubview(imageViews[pageIndex])
    }
  }

  private func paginatedPageIndices() -> [Int] {
    guard imageViews.indices.contains(currentIndex) else { return [] }
    guard isDoublePageMode else { return [currentIndex] }

    if isRightToLeft {
      return currentIndex > 0 ? [currentIndex, currentIndex - 1] : [currentIndex]
    }

    return currentIndex + 1 < imageViews.count
      ? [currentIndex, currentIndex + 1]
      : [currentIndex]
  }

  private func applyLayoutForCurrentPreferences() {
    guard isViewLoaded else { return }

    imageSizeConstraints.forEach { $0.isActive = false }
    imageSizeConstraints.removeAll()
    boundarySizeConstraints.forEach { $0.isActive = false }
    boundarySizeConstraints.removeAll()

    stackView.spacing = isPaginatedMode ? 0 : gap
    stackView.axis = isHorizontalScrollMode ? .horizontal : .vertical
    stackView.distribution = .fill
    scrollView.isPagingEnabled = isPaginatedMode
    applyScrollAxisPolicy()

    if isPaginatedMode {
      rebuildPaginatedSubviewsIfNeeded()
    } else {
      rebuildScrollableSubviewsIfNeeded()
    }

    configureChapterBoundaryViews()

    let viewport = scrollView.bounds.size
    guard viewport.width > 0, viewport.height > 0 else { return }

    if isHorizontalScrollMode || isPaginatedMode {
      imageSizeConstraints.append(stackView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
    } else {
      imageSizeConstraints.append(stackView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
    }

    for boundaryView in [previousChapterBoundaryView, nextChapterBoundaryView]
      where boundaryView.superview != nil
    {
      if isHorizontalScrollMode {
        boundarySizeConstraints.append(boundaryView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
        boundarySizeConstraints.append(boundaryView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
      } else {
        boundarySizeConstraints.append(boundaryView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor))
        boundarySizeConstraints.append(boundaryView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
      }
    }

    for (index, imageView) in imageViews.enumerated() where imageView.superview != nil {
      let imageSize = images[index]?.size ?? CGSize(width: viewport.width, height: viewport.height)
      let aspect = imageSize.width > 0 ? imageSize.height / imageSize.width : 1

      let displaySize = displaySize(for: imageSize, viewport: viewport)

      if isHorizontalScrollMode || isPaginatedMode {
        let width = paginatedWidth(for: displaySize.width, viewport: viewport)
        imageSizeConstraints.append(imageView.widthAnchor.constraint(equalToConstant: width))
        if isPaginatedMode, isOriginalSizeMode {
          imageSizeConstraints.append(imageView.heightAnchor.constraint(equalToConstant: displaySize.height))
        } else {
          imageSizeConstraints.append(imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor))
        }
      } else {
        imageSizeConstraints.append(imageView.widthAnchor.constraint(equalToConstant: displaySize.width))
        imageSizeConstraints.append(imageView.heightAnchor.constraint(equalToConstant: max(1, displaySize.width * aspect)))
      }
    }

    NSLayoutConstraint.activate(imageSizeConstraints + boundarySizeConstraints)
    applyPendingBoundaryTargetIfNeeded()
    clampContentOffsetForCurrentMode()
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

    let expected = paginatedPageIndices()

    if visibleTags != expected {
      rebuildArrangedSubviews()
    }
  }

  private func rebuildScrollableSubviewsIfNeeded() {
    let visibleTags = stackView.arrangedSubviews.compactMap { ($0 as? UIImageView)?.tag }
    let expected = Array(visibleChapterRange)

    let hasPreviousBoundary = previousChapterBoundaryView.superview != nil
    let hasNextBoundary = nextChapterBoundaryView.superview != nil

    if visibleTags != expected
      || hasPreviousBoundary != shouldShowPreviousChapterBoundary
      || hasNextBoundary != shouldShowNextChapterBoundary
    {
      rebuildArrangedSubviews()
    }
  }

  private func displaySize(for imageSize: CGSize, viewport: CGSize) -> CGSize {
    let availableWidth = pageWidthLimit(for: viewport)
    let naturalWidth = max(imageSize.width, 1)
    let naturalHeight = max(imageSize.height, 1)
    let aspect = naturalHeight / naturalWidth

    switch preferences?.fit {
    case "page":
      let widthFromHeight = viewport.height / aspect
      let width = min(availableWidth, widthFromHeight)
      return CGSize(width: max(1, width), height: max(1, width * aspect))
    case "width":
      return CGSize(width: max(1, availableWidth), height: max(1, availableWidth * aspect))
    default:
      let baseWidth = shouldStretchSmallPages ? availableWidth : naturalWidth
      let width = isWidthLimitEnabled ? min(baseWidth, availableWidth) : baseWidth
      return CGSize(width: max(1, width), height: max(1, width * aspect))
    }
  }

  private func paginatedWidth(for displayWidth: CGFloat, viewport: CGSize) -> CGFloat {
    guard isDoublePageMode, isPaginatedMode, !isOriginalSizeMode else {
      return displayWidth
    }
    return min(max((viewport.width - gap) / 2, 1), displayWidth)
  }

  private func pageWidthLimit(for viewport: CGSize) -> CGFloat {
    let viewportWidth = max(viewport.width, 1)
    guard preferences?.comicWidthLimitEnabled == true else { return viewportWidth }
    let percent = min(max(preferences?.comicWidthLimitPercent ?? 50, 10), 100)
    return max(1, viewportWidth * CGFloat(percent / 100))
  }

  private func navigateToIndex(_ index: Int, animated: Bool, emit: Bool = true) {
    guard !links.isEmpty else { return }
    currentIndex = min(max(index, 0), links.count - 1)

    if isPaginatedMode {
      rebuildArrangedSubviews()
      scrollView.setContentOffset(paginatedContentOffset(), animated: false)
    } else if imageViews.indices.contains(currentIndex) {
      let targetView = imageViews[currentIndex]
      let rect = targetView.convert(targetView.bounds, to: scrollView)
      let offset = centeredContinuousOffset(for: rect)
      isApplyingProgrammaticScroll = true
      scrollView.setContentOffset(offset, animated: animated)
      if !animated {
        isApplyingProgrammaticScroll = false
      }
    }

    if emit {
      subject.send(locator(for: currentIndex))
    }
    Task { [weak self] in
      await self?.preloadImages(around: self?.currentIndex ?? index)
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
    Task { [weak self] in
      await self?.preloadImages(around: closestIndex)
    }
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

  private var isRightToLeft: Bool {
    preferences?.readingProgression == "rtl"
  }

  private var isOriginalSizeMode: Bool {
    preferences?.fit == "auto"
  }

  private var gap: CGFloat {
    CGFloat(max(preferences?.pageMargins ?? 0, 0) * 16)
  }

  private var shouldStretchSmallPages: Bool {
    preferences?.comicStretchSmallPages ?? false
  }

  private var isWidthLimitEnabled: Bool {
    preferences?.comicWidthLimitEnabled == true
  }

  private var imagePreloadAmount: Int {
    let value = preferences?.comicImagePreloadAmount ?? 5
    return max(0, min(Int(value.rounded()), max(links.count - 1, 0)))
  }

  private var visibleChapterRange: ClosedRange<Int> {
    guard !imageViews.isEmpty else { return 0...0 }
    guard
      let start = preferences?.comicChapterStartIndex,
      let end = preferences?.comicChapterEndIndex
    else {
      return 0...(imageViews.count - 1)
    }

    let lower = min(max(Int(start.rounded()), 0), imageViews.count - 1)
    let upper = min(max(Int(end.rounded()), lower), imageViews.count - 1)
    return lower...upper
  }

  private var shouldShowPreviousChapterBoundary: Bool {
    !isPaginatedMode && visibleChapterRange.lowerBound > 0
  }

  private var shouldShowNextChapterBoundary: Bool {
    !isPaginatedMode && visibleChapterRange.upperBound < max(imageViews.count - 1, 0)
  }

  private func configureChapterBoundaryViews() {
    let backgroundColor = preferences?.backgroundColor.flatMap(UIColor.fromCSS) ?? .black
    let textColor = preferences?.textColor.flatMap(UIColor.fromCSS) ?? .white

    previousChapterBoundaryView.configure(
      title: preferences?.comicPreviousChapterTitle,
      backgroundColor: backgroundColor,
      textColor: textColor
    )
    nextChapterBoundaryView.configure(
      title: preferences?.comicNextChapterTitle,
      backgroundColor: backgroundColor,
      textColor: textColor
    )
  }

  private func applyScrollAxisPolicy() {
    if isPaginatedMode {
      scrollView.alwaysBounceVertical = isOriginalSizeMode
      scrollView.alwaysBounceHorizontal = isOriginalSizeMode
      scrollView.bounces = isOriginalSizeMode
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
      scrollView.showsVerticalScrollIndicator = !isWebtoonMode
      scrollView.showsHorizontalScrollIndicator = false
    }
  }

  private func centeredContinuousOffset(for rect: CGRect) -> CGPoint {
    let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
    let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)

    if isHorizontalScrollMode {
      let targetX = rect.midX - scrollView.bounds.width / 2
      return CGPoint(x: min(max(targetX, 0), maxX), y: 0)
    }

    let targetY = rect.midY - scrollView.bounds.height / 2
    return CGPoint(x: 0, y: min(max(targetY, 0), maxY))
  }

  private func applyPendingBoundaryTargetIfNeeded() {
    guard !isPaginatedMode else { return }
    guard let target = preferences?.comicBoundaryTarget, target != "none" else {
      lastAppliedBoundaryTarget = nil
      return
    }
    guard target != lastAppliedBoundaryTarget else { return }

    let boundaryView: UIView?
    switch target {
    case "previous":
      boundaryView = shouldShowPreviousChapterBoundary ? previousChapterBoundaryView : nil
    case "next":
      boundaryView = shouldShowNextChapterBoundary ? nextChapterBoundaryView : nil
    default:
      boundaryView = nil
    }

    guard let boundaryView, boundaryView.superview != nil else { return }
    view.layoutIfNeeded()
    let rect = boundaryView.convert(boundaryView.bounds, to: scrollView)
    let offset = centeredContinuousOffset(for: rect)
    lastAppliedBoundaryTarget = target
    isApplyingProgrammaticScroll = true
    scrollView.setContentOffset(offset, animated: true)
  }

  private func clampContentOffsetForCurrentMode() {
    guard !isClampingContentOffset else { return }

    let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
    let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
    let current = scrollView.contentOffset
    let clamped: CGPoint

    if isPaginatedMode {
      clamped = isOriginalSizeMode
        ? CGPoint(x: min(max(current.x, 0), maxX), y: min(max(current.y, 0), maxY))
        : .zero
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

  private func paginatedContentOffset() -> CGPoint {
    guard isOriginalSizeMode else { return .zero }
    let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
    let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
    return CGPoint(
      x: min(max(scrollView.contentOffset.x, 0), maxX),
      y: min(max(scrollView.contentOffset.y, 0), maxY)
    )
  }
}

private final class ComicChapterBoundaryView: UIView {
  enum Direction {
    case previous
    case next
  }

  private let eyebrowLabel = UILabel()
  private let titleLabel = UILabel()
  private let hintLabel = UILabel()
  private let direction: Direction

  init(direction: Direction) {
    self.direction = direction
    super.init(frame: .zero)
    translatesAutoresizingMaskIntoConstraints = false
    setup()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(title: String?, backgroundColor: UIColor, textColor: UIColor) {
    self.backgroundColor = backgroundColor
    eyebrowLabel.textColor = textColor.withAlphaComponent(0.65)
    titleLabel.textColor = textColor
    hintLabel.textColor = textColor.withAlphaComponent(0.72)

    if let chapterTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines),
      !chapterTitle.isEmpty
    {
      titleLabel.text = chapterTitle
    } else {
      titleLabel.text = direction == .previous ? "Previous chapter" : "Next chapter"
    }
  }

  private func setup() {
    let contentStack = UIStackView(arrangedSubviews: [
      eyebrowLabel,
      titleLabel,
      hintLabel,
    ])
    contentStack.axis = .vertical
    contentStack.alignment = .center
    contentStack.spacing = 12
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentStack)

    eyebrowLabel.font = .preferredFont(forTextStyle: .subheadline)
    eyebrowLabel.adjustsFontForContentSizeCategory = true
    eyebrowLabel.textAlignment = .center
    eyebrowLabel.text = direction == .previous
      ? "Start of chapter"
      : "End of chapter"

    titleLabel.font = .preferredFont(forTextStyle: .title2)
    titleLabel.adjustsFontForContentSizeCategory = true
    titleLabel.font = .systemFont(ofSize: titleLabel.font.pointSize, weight: .semibold)
    titleLabel.textAlignment = .center
    titleLabel.numberOfLines = 3

    hintLabel.font = .preferredFont(forTextStyle: .footnote)
    hintLabel.adjustsFontForContentSizeCategory = true
    hintLabel.textAlignment = .center
    hintLabel.numberOfLines = 2
    hintLabel.text = direction == .previous
      ? "Go back again to enter the previous chapter"
      : "Go forward again to enter the next chapter"

    NSLayoutConstraint.activate([
      contentStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 32),
      contentStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -32),
      contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
      contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
    ])
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
