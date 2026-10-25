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
  /// Decoded images; only pages in `ComicPagePlanner.decodeWindow` hold one.
  private var images: [UIImage?]
  /// Intrinsic pixel size per page, known from the image header before decoding.
  private var pageSizes: [CGSize?]
  private var imageViews: [UIImageView] = []
  /// Stack-to-scroll-view constraints for the current mode.
  private var imageSizeConstraints: [NSLayoutConstraint] = []
  /// Per-page width/height constraints, kept and updated in place so a page
  /// learning its size re-lays out that page only.
  private var pageConstraints: [Int: (width: NSLayoutConstraint, height: NSLayoutConstraint)] = [:]
  private var initialLocator: ReadiumShared.Locator?
  private var currentIndex = 0
  private var preferences: Preferences?
  private var isApplyingProgrammaticScroll = false
  private var isClampingContentOffset = false
  /// Reading direction of the last page change, in index space (+1 forward).
  private var loadDirection = 1
  private var warmer: ComicPageWarmer?
  private var decodingIndices = Set<Int>()
  private var inFlightData: [Int: Task<Data?, Never>] = [:]
  private var pendingSizeIndices = Set<Int>()
  private var isSizeFlushScheduled = false

  /// Chapter boundary pages; attached around the pages in scroll modes only.
  private var boundaryContent: [ComicBoundaryKind: ComicBoundaryContent] = [:]
  private var boundaryViews: [ComicBoundaryKind: ComicBoundaryPageView] = [:]
  private var activeBoundary: ComicBoundaryKind?

  /// Taps on the page, in this reader's coordinate space. Android's
  /// ComicReaderFragment emits the same event from its own touch stream.
  var onTap: ((CGPoint) -> Void)?
  /// The boundary page that fills the viewport, or nil when a comic page does.
  var onBoundaryChange: ((ComicBoundaryKind?) -> Void)?
  /// A boundary page button was pressed.
  var onBoundaryAction: ((ComicBoundaryKind, String) -> Void)?

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
    self.pageSizes = Array(repeating: nil, count: links.count)
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
  }

  /// Sets the chapter boundary pages. Adding or removing one keeps the
  /// current page where it is on screen.
  func setBoundaryPages(previous: ComicBoundaryContent?, next: ComicBoundaryContent?) {
    var content: [ComicBoundaryKind: ComicBoundaryContent] = [:]
    content[.previous] = previous
    content[.next] = next
    guard content != boundaryContent else { return }
    let presenceChanged = Set(content.keys) != Set(boundaryContent.keys)
    boundaryContent = content
    guard isViewLoaded, !imageViews.isEmpty else { return }
    guard presenceChanged, !isPaginatedMode else {
      configureBoundaryViews()
      return
    }
    let anchor = scrollAnchor()
    rebuildArrangedSubviews()
    applyLayoutForCurrentPreferences()
    scrollView.layoutIfNeeded()
    if let anchor {
      restoreScrollAnchor(anchor)
    }
    updateActiveBoundary()
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
    if currentIndex >= links.count - 1, let boundary = attachedBoundaryView(.next) {
      scrollToBoundary(boundary)
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
    if currentIndex <= 0, let boundary = attachedBoundaryView(.previous) {
      scrollToBoundary(boundary)
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
    scrollView.showsVerticalScrollIndicator = false
    scrollView.showsHorizontalScrollIndicator = false
    view.addSubview(scrollView)

    // This reader is a bare UIViewController over a UIScrollView, not a
    // Readium VisualNavigator, so it never gets the shared `.tap` observer that
    // ReaderViewController installs. Without this, a host has no way to receive
    // comic taps on iOS — the app's tap zones and tap-to-toggle-chrome have no
    // native path here. Android classifies taps in ComicReaderFragment instead,
    // so the two readers reach the same behaviour by different means.
    let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    tapRecognizer.cancelsTouchesInView = false
    tapRecognizer.delegate = self
    scrollView.addGestureRecognizer(tapRecognizer)

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

  /// Tap in the reader's own coordinate space, matching the `Point` that
  /// `ReadiumView.onTap` receives from a VisualNavigator tap.
  @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended else { return }
    onTap?(recognizer.location(in: scrollView))
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
    await MainActor.run {
      currentIndex = startIndex
      warmer = ComicPageWarmer { [weak self] index in
        guard let self else { throw CancellationError() }
        try await self.warmPage(index)
      }
    }
    // The first page goes first; navigating below plans everything else.
    await decodePage(startIndex)

    await MainActor.run {
      loadingIndicator.stopAnimating()
      loadingIndicator.removeFromSuperview()
      navigateToIndex(startIndex, animated: false)
      initialLocator = nil
    }
  }

  // MARK: - Page loading
  //
  // Every page is downloaded in reading order by `ComicPageWarmer` (streamed
  // pages land in `ComicPageDiskCache`); each download reads the page's pixel
  // size from its header so placeholders match the page before it is decoded;
  // only pages inside `ComicPagePlanner.decodeWindow` hold a decoded image.
  // Mirrors Android's ComicReaderFragment.

  /// Moves the cursor and re-plans downloads and decoded pages around it.
  @MainActor
  private func setCurrentIndex(_ index: Int) {
    if index != currentIndex {
      loadDirection = index > currentIndex ? 1 : -1
    }
    currentIndex = index
    refreshPageLoading()
  }

  @MainActor
  private func refreshPageLoading() {
    guard !links.isEmpty, !imageViews.isEmpty else { return }
    warmer?.plan(
      ComicPagePlanner.warmupOrder(pageCount: links.count, cursor: currentIndex, direction: loadDirection)
    )
    let window = currentDecodeWindow
    for index in images.indices where images[index] != nil && !window.contains(index) {
      images[index] = nil
      imageViews[index].image = nil
    }
    // Decode nearest-first so the visible page never waits behind its neighbours.
    for index in window.sorted(by: { abs($0 - currentIndex) < abs($1 - currentIndex) }) {
      Task { await decodePage(index) }
    }
  }

  private var currentDecodeWindow: Set<Int> {
    ComicPagePlanner.decodeWindow(
      pageCount: links.count,
      cursor: currentIndex,
      direction: loadDirection,
      paginated: isPaginatedMode,
      doublePage: isDoublePageMode
    )
  }

  /// Warmup task: fetch (and disk-cache) the page and learn its size from the header.
  @MainActor
  private func warmPage(_ index: Int) async throws {
    guard let data = await pageData(index) else {
      throw CocoaError(.fileReadUnknown)
    }
    let size = await Task.detached(priority: .utility) { ComicPageImage.pixelSize(of: data) }.value
    if let size {
      setPageSize(size, at: index)
    }
  }

  @MainActor
  private func decodePage(_ index: Int) async {
    guard images.indices.contains(index), images[index] == nil, !decodingIndices.contains(index) else { return }
    decodingIndices.insert(index)
    defer { decodingIndices.remove(index) }

    guard let data = await pageData(index) else { return }
    if pageSizes[index] == nil {
      let size = await Task.detached(priority: .userInitiated) { ComicPageImage.pixelSize(of: data) }.value
      if let size { setPageSize(size, at: index) }
    }
    guard let naturalSize = pageSizes[index] else { return }

    let viewport = scrollView.bounds.size.width > 0 ? scrollView.bounds.size : view.bounds.size
    let displaySize = displayedImageSize(for: naturalSize, viewport: viewport)
    let maxPixelSize = max(displaySize.width, displaySize.height) * traitCollection.displayScale
    let image = await Task.detached(priority: .userInitiated) {
      ComicPageImage.decode(data, maxPixelSize: maxPixelSize)
    }.value

    guard let image, currentDecodeWindow.contains(index) else { return }
    images[index] = image
    imageViews[index].image = image
  }

  /// Page bytes, shared between the warmer and the decoder so a page is never
  /// fetched twice at once. Streamed pages are served from (and written to)
  /// the disk cache; local publications read straight from the publication.
  @MainActor
  private func pageData(_ index: Int) async -> Data? {
    if let pending = inFlightData[index] {
      return await pending.value
    }
    let publication = publication
    let link = links[index]
    let task = Task.detached(priority: .userInitiated) { () -> Data? in
      guard let resource = publication.get(link) else { return nil }
      let cacheKey = resource.sourceURL.flatMap { ComicPageDiskCache.key(for: $0.url) }
      let cache = cacheKey == nil ? nil : ComicPageDiskCache.shared
      if let cacheKey, let cached = cache?.read(cacheKey) {
        return cached
      }
      guard let data = try? await resource.read().get() else { return nil }
      if let cacheKey {
        cache?.write(data, for: cacheKey)
      }
      return data
    }
    inFlightData[index] = task
    let data = await task.value
    if inFlightData[index] == task {
      inFlightData[index] = nil
    }
    return data
  }

  @MainActor
  private func setPageSize(_ size: CGSize, at index: Int) {
    guard pageSizes.indices.contains(index), pageSizes[index] != size else { return }
    pageSizes[index] = size
    pendingSizeIndices.insert(index)
    guard !isSizeFlushScheduled else { return }
    isSizeFlushScheduled = true
    // Coalesce the sizes learned in one run-loop turn into a single layout pass.
    Task { @MainActor [weak self] in
      self?.flushPageSizes()
    }
  }

  /// Re-sizes pages whose size became known, holding the current page in place
  /// so content above it cannot shift the reader.
  private func flushPageSizes() {
    isSizeFlushScheduled = false
    let indices = pendingSizeIndices
    pendingSizeIndices.removeAll()
    let viewport = scrollView.bounds.size
    guard isViewLoaded, viewport.width > 0, viewport.height > 0 else { return }

    let anchor = scrollAnchor()
    for index in indices where imageViews.indices.contains(index) && imageViews[index].superview != nil {
      let naturalSize = pageSizes[index] ?? viewport
      setPageConstraints(index, size: displayedImageSize(for: naturalSize, viewport: viewport))
    }
    guard let anchor else { return }
    scrollView.layoutIfNeeded()
    restoreScrollAnchor(anchor)
  }

  private func scrollAnchor() -> (index: Int, offset: CGFloat)? {
    guard !isPaginatedMode, !isApplyingProgrammaticScroll, imageViews.indices.contains(currentIndex) else {
      return nil
    }
    let anchorView = imageViews[currentIndex]
    guard anchorView.superview != nil else { return nil }
    return (currentIndex, anchorPosition(of: anchorView))
  }

  private func restoreScrollAnchor(_ anchor: (index: Int, offset: CGFloat)) {
    let drift = anchorPosition(of: imageViews[anchor.index]) - anchor.offset
    guard abs(drift) >= 0.5 else { return }
    var offset = scrollView.contentOffset
    if isHorizontalScrollMode {
      offset.x = max(offset.x + drift, 0)
    } else {
      offset.y = max(offset.y + drift, 0)
    }
    // Assigning (rather than setContentOffset(_:animated:)) keeps any
    // in-flight deceleration going from the corrected position.
    scrollView.contentOffset = offset
  }

  private func anchorPosition(of view: UIView) -> CGFloat {
    let frame = view.convert(view.bounds, to: scrollView)
    return isHorizontalScrollMode
      ? frame.minX - scrollView.contentOffset.x
      : frame.minY - scrollView.contentOffset.y
  }

  private func setPageConstraints(_ index: Int, size: CGSize) {
    if let constraints = pageConstraints[index] {
      if constraints.width.constant != size.width { constraints.width.constant = size.width }
      if constraints.height.constant != size.height { constraints.height.constant = size.height }
      return
    }
    let imageView = imageViews[index]
    let width = imageView.widthAnchor.constraint(equalToConstant: size.width)
    let height = imageView.heightAnchor.constraint(equalToConstant: size.height)
    NSLayoutConstraint.activate([width, height])
    pageConstraints[index] = (width, height)
  }

  private func rebuildArrangedSubviews() {
    clearImageSizeConstraints()
    removeArrangedSubviews(from: stackView)

    if isPaginatedMode {
      addPaginatedSubviews()
    } else {
      addBoundarySubview(.previous)
      imageViews.forEach { stackView.addArrangedSubview($0) }
      addBoundarySubview(.next)
    }
  }

  // MARK: - Chapter boundary pages

  private func addBoundarySubview(_ kind: ComicBoundaryKind) {
    guard let content = boundaryContent[kind] else { return }
    let boundary: ComicBoundaryPageView
    if let existing = boundaryViews[kind] {
      boundary = existing
    } else {
      boundary = ComicBoundaryPageView()
      boundary.onAction = { [weak self] actionId in
        self?.onBoundaryAction?(kind, actionId)
      }
      boundaryViews[kind] = boundary
    }
    boundary.configure(content, textColor: readerTextColor, backgroundColor: readerBackgroundColor)
    stackView.addArrangedSubview(boundary)
    // A boundary page fills the viewport, like the web reader's.
    NSLayoutConstraint.activate([
      boundary.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
      boundary.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
    ])
  }

  private func attachedBoundaryView(_ kind: ComicBoundaryKind) -> ComicBoundaryPageView? {
    guard !isPaginatedMode, let boundary = boundaryViews[kind], boundary.superview === stackView else {
      return nil
    }
    return boundary
  }

  private func configureBoundaryViews() {
    for (kind, boundary) in boundaryViews {
      guard let content = boundaryContent[kind] else { continue }
      boundary.configure(content, textColor: readerTextColor, backgroundColor: readerBackgroundColor)
    }
  }

  private func scrollToBoundary(_ boundary: UIView) {
    scrollView.layoutIfNeeded()
    let frame = boundary.convert(boundary.bounds, to: scrollView)
    let maxX = max(scrollView.contentSize.width - scrollView.bounds.width, 0)
    let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
    let offset = isHorizontalScrollMode
      ? CGPoint(x: min(max(frame.minX, 0), maxX), y: 0)
      : CGPoint(x: 0, y: min(max(frame.minY, 0), maxY))
    // An unchanged offset ends no animation, which would leave the flag set.
    guard offset != scrollView.contentOffset else { return }
    isApplyingProgrammaticScroll = true
    scrollView.setContentOffset(offset, animated: true)
  }

  /// Offsets that keep boundary pages out of view, so programmatic page
  /// navigation lands on comic pages and only an explicit move past the first
  /// or last page reveals a boundary.
  private func pageOffsetRange() -> ClosedRange<CGFloat> {
    let horizontal = isHorizontalScrollMode
    var lower: CGFloat = 0
    var upper = CGFloat.greatestFiniteMagnitude
    if attachedBoundaryView(.previous) != nil, let first = imageViews.first {
      let frame = first.convert(first.bounds, to: scrollView)
      lower = horizontal ? frame.minX : frame.minY
    }
    if attachedBoundaryView(.next) != nil, let last = imageViews.last {
      let frame = last.convert(last.bounds, to: scrollView)
      upper = horizontal
        ? frame.maxX - scrollView.bounds.width
        : frame.maxY - scrollView.bounds.height
    }
    return lower...max(upper, lower)
  }

  /// Same rule as the web reader: a boundary page is active when the scroll
  /// sits at that end and the page covers the viewport center.
  private func updateActiveBoundary() {
    let active = currentActiveBoundary()
    guard active != activeBoundary else { return }
    activeBoundary = active
    onBoundaryChange?(active)
  }

  private func currentActiveBoundary() -> ComicBoundaryKind? {
    let horizontal = isHorizontalScrollMode
    let offset = horizontal ? scrollView.contentOffset.x : scrollView.contentOffset.y
    let viewportLength = horizontal ? scrollView.bounds.width : scrollView.bounds.height
    let contentLength = horizontal ? scrollView.contentSize.width : scrollView.contentSize.height
    guard viewportLength > 0 else { return nil }
    let center = offset + viewportLength / 2
    let edgeTolerance: CGFloat = 2
    for kind in [ComicBoundaryKind.previous, .next] {
      guard let boundary = attachedBoundaryView(kind) else { continue }
      if kind == .previous && offset > edgeTolerance { continue }
      if kind == .next && offset + viewportLength < contentLength - edgeTolerance { continue }
      let frame = boundary.convert(boundary.bounds, to: scrollView)
      let start = horizontal ? frame.minX : frame.minY
      let end = horizontal ? frame.maxX : frame.maxY
      if start <= center && end >= center { return kind }
    }
    return nil
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

    NSLayoutConstraint.activate(imageSizeConstraints)

    // Pages whose size is not known yet reserve the viewport.
    for (index, imageView) in imageViews.enumerated() where imageView.superview != nil {
      let naturalSize = pageSizes[index] ?? viewport
      setPageConstraints(index, size: displayedImageSize(for: naturalSize, viewport: viewport))
    }
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
    setCurrentIndex(min(max(index, 0), links.count - 1))

    if isPaginatedMode {
      rebuildArrangedSubviews()
      applyLayoutForCurrentPreferences()
      scrollView.setContentOffset(.zero, animated: false)
    } else if imageViews.indices.contains(currentIndex) {
      scrollView.layoutIfNeeded()
      let targetView = imageViews[currentIndex]
      let rect = targetView.convert(targetView.bounds, to: scrollView)
      let range = pageOffsetRange()
      let offset: CGPoint
      if isHorizontalScrollMode {
        let x = max(rect.midX - scrollView.bounds.width / 2, 0)
        offset = CGPoint(x: min(max(x, range.lowerBound), range.upperBound), y: 0)
      } else {
        let y = max(rect.midY - scrollView.bounds.height / 2, 0)
        offset = CGPoint(x: 0, y: min(max(y, range.lowerBound), range.upperBound))
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
    if isPaginatedMode || !animated {
      updateActiveBoundary()
    }
  }

  /// Probe point at the viewport center along the scroll axis; nearest page
  /// center wins. Page centers are monotonic along the axis, so the distance to
  /// the probe is unimodal in the page index: walk from the current page toward
  /// the probe instead of measuring every page on every scroll event.
  private func updateCurrentIndexFromScrollPosition() {
    guard !isPaginatedMode, !links.isEmpty, imageViews.indices.contains(currentIndex) else { return }

    let probe = isHorizontalScrollMode
      ? scrollView.contentOffset.x + scrollView.bounds.width / 2
      : scrollView.contentOffset.y + scrollView.bounds.height / 2

    func distance(_ index: Int) -> CGFloat? {
      guard imageViews.indices.contains(index) else { return nil }
      let imageView = imageViews[index]
      guard imageView.superview != nil else { return nil }
      let frame = imageView.convert(imageView.bounds, to: scrollView)
      return abs((isHorizontalScrollMode ? frame.midX : frame.midY) - probe)
    }

    var closestIndex = currentIndex
    guard var closestDistance = distance(closestIndex) else { return }
    for step in [1, -1] {
      var candidate = closestIndex + step
      while let candidateDistance = distance(candidate), candidateDistance < closestDistance {
        closestIndex = candidate
        closestDistance = candidateDistance
        candidate += step
      }
    }

    guard closestIndex != currentIndex else { return }
    setCurrentIndex(closestIndex)
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

  private var readerBackgroundColor: UIColor {
    UIColor(readerHex: preferences?.backgroundColor) ?? .black
  }

  private var readerTextColor: UIColor {
    UIColor(readerHex: preferences?.textColor) ?? .white
  }

  private func applyTheme() {
    let color = readerBackgroundColor
    view.backgroundColor = color
    scrollView.backgroundColor = color
    stackView.backgroundColor = color
    imageViews.forEach { $0.backgroundColor = color }
    configureBoundaryViews()
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
      return
    }

    scrollView.bounces = true
    if isHorizontalScrollMode {
      scrollView.alwaysBounceVertical = false
      scrollView.alwaysBounceHorizontal = true
    } else {
      scrollView.alwaysBounceVertical = true
      scrollView.alwaysBounceHorizontal = false
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
    updateActiveBoundary()
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

extension ComicImageViewController: UIGestureRecognizerDelegate {
  /// Boundary page buttons handle their own touches; they are not tap zones.
  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
    var view = touch.view
    while let current = view, current !== scrollView {
      if current is UIControl { return false }
      view = current.superview
    }
    return true
  }
}
