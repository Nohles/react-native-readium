import Foundation
import UIKit
import ReadiumShared

final class EPUBModule: ReaderFormatModule {

    weak var delegate: ReaderFormatModuleDelegate?

    init(delegate: ReaderFormatModuleDelegate?) {
        self.delegate = delegate
    }

    func supports(_ publication: Publication) -> Bool {
      publication.conforms(to: .epub)
        || publication.readingOrder.allAreHTML
    }

    func makeReaderViewController(
      for publication: Publication,
      locator: ReadiumShared.Locator?,
      bookId: String,
      selectionActions: [SelectionActionData]?
    ) throws -> ReadiumReaderHosting {
        try makeReaderViewController(
          for: publication,
          locator: locator,
          bookId: bookId,
          selectionActions: selectionActions,
          customFonts: nil
        )
    }

    func makeReaderViewController(
      for publication: Publication,
      locator: ReadiumShared.Locator?,
      bookId: String,
      selectionActions: [SelectionActionData]?,
      customFonts: [CustomFont]?
    ) throws -> ReadiumReaderHosting {
        let epubViewController = try EPUBViewController(
            publication: publication,
            locator: locator,
            bookId: bookId,
            selectionActions: selectionActions,
            customFonts: customFonts
        )
        epubViewController.moduleDelegate = delegate
        return epubViewController
    }

}
