import Foundation
import ReadiumShared
import UIKit

final class AudiobookModule: ReaderFormatModule {

  weak var delegate: ReaderFormatModuleDelegate?

  init(delegate: ReaderFormatModuleDelegate?) {
    self.delegate = delegate
  }

  func supports(_ publication: Publication) -> Bool {
    publication.conforms(to: .audiobook)
      || publication.metadata.conformsTo.contains(.audiobook)
      || publication.readingOrder.allSatisfy { $0.mediaType?.isAudio == true }
  }

  func makeReaderViewController(
    for publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String,
    selectionActions: [SelectionActionData]?
  ) throws -> ReadiumReaderHosting {
    let audiobookViewController = AudiobookViewController(
      publication: publication,
      locator: locator,
      bookId: bookId
    )
    audiobookViewController.moduleDelegate = delegate
    return audiobookViewController
  }
}
