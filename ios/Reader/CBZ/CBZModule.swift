import ReadiumShared

/// CBZ publications render their reading order as native images so continuous
/// comic modes can scroll a whole chapter instead of one spine item at a time.
final class CBZModule: ReaderFormatModule {
  weak var delegate: ReaderFormatModuleDelegate?

  init(delegate: ReaderFormatModuleDelegate?) {
    self.delegate = delegate
  }

  func supports(_ publication: Publication) -> Bool {
    publication.conforms(to: .divina)
      || publication.metadata.conformsTo.contains(.divina)
      || publication.readingOrder.allSatisfy {
        $0.mediaType?.isBitmap == true || $0.mediaType?.matches(.cbz) == true
      }
  }

  func makeReaderViewController(
    for publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String,
    selectionActions: [SelectionActionData]?
  ) throws -> ReadiumReaderHosting {
    let viewController = ComicImageViewController(
      publication: publication,
      locator: locator,
      bookId: bookId
    )
    return viewController
  }
}
