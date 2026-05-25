import ReadiumNavigator
import ReadiumShared

final class PDFViewController: ReaderViewController {
  init(
    publication: Publication,
    locator: ReadiumShared.Locator?,
    bookId: String
  ) throws {
    let navigator = try PDFNavigatorViewController(
      publication: publication,
      initialLocation: locator
    )
    super.init(navigator: navigator, publication: publication, bookId: bookId)
    navigator.delegate = self
  }
}

extension PDFViewController: PDFNavigatorDelegate {}
