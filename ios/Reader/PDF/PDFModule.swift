import ReadiumShared

final class PDFModule: ReaderFormatModule {
  weak var delegate: ReaderFormatModuleDelegate?

  init(delegate: ReaderFormatModuleDelegate?) {
    self.delegate = delegate
  }

  func supports(_ publication: Publication) -> Bool {
    publication.conforms(to: .pdf)
  }

  func makeReaderViewController(
    for publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String,
    selectionActions: [SelectionActionData]?
  ) throws -> ReadiumReaderHosting {
    let viewController = try PDFViewController(
      publication: publication,
      locator: locator,
      bookId: bookId
    )
    viewController.moduleDelegate = delegate
    return viewController
  }
}
