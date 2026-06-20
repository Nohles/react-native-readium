import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Common surface for EPUB and audiobook reader view controllers.
protocol ReadiumReaderHosting: AnyObject {
  var publication: Publication { get }
  var publisher: AnyPublisher<ReadiumShared.Locator, Never> { get }
  var viewController: UIViewController { get }

  func goTo(_ locator: ReadiumShared.Locator) async
  func goForward() async
  func goBackward() async
}

extension ReaderViewController: ReadiumReaderHosting {
  var viewController: UIViewController { self }
}

extension AudioViewController: ReadiumReaderHosting {
  var viewController: UIViewController { self }
}

extension AudiobookViewController: ReadiumReaderHosting {
  var viewController: UIViewController { self }
}
