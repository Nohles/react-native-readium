import ReadiumShared

/// CBZ publications use Readium's EPUB navigator path as recommended in 3.9.
final class CBZModule: ReaderFormatModule {
  weak var delegate: ReaderFormatModuleDelegate?

  init(delegate: ReaderFormatModuleDelegate?) {
    self.delegate = delegate
  }

  func supports(_ publication: Publication) -> Bool {
    publication.conforms(to: .divina)
  }

  func makeReaderViewController(
    for publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String,
    selectionActions: [SelectionActionData]?
  ) throws -> ReadiumReaderHosting {
    let viewController = try EPUBViewController(
      publication: publication,
      locator: locator,
      bookId: bookId,
      selectionActions: nil
    )
    viewController.moduleDelegate = delegate
    return viewController
  }
}
