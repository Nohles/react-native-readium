import Foundation
import ReadiumShared

final class AudioModule: ReaderFormatModule {

  weak var delegate: ReaderFormatModuleDelegate?

  init(delegate: ReaderFormatModuleDelegate?) {
    self.delegate = delegate
  }

  func supports(_ publication: Publication) -> Bool {
    publication.conforms(to: .audiobook)
  }

  func makeReaderViewController(
    for publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String,
    selectionActions: [SelectionActionData]?
  ) throws -> ReadiumReaderHosting {
    guard publication.metadata.identifier != nil else {
      throw ReaderError.epubNotValid
    }

    let audioViewController = try AudioViewController(
      publication: publication,
      locator: locator,
      bookId: bookId
    )
    audioViewController.moduleDelegate = delegate
    return audioViewController
  }
}
