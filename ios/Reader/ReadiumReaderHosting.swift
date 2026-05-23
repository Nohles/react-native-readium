import Combine
import Foundation
import ReadiumNavigator
import ReadiumShared
import UIKit

/// Common surface for EPUB and audiobook reader view controllers.
protocol ReadiumReaderHosting: AnyObject {
  var readiumNavigator: Navigator { get }
  var publication: Publication { get }
  var publisher: AnyPublisher<ReadiumShared.Locator, Never> { get }
  var viewController: UIViewController { get }
}

extension ReaderViewController: ReadiumReaderHosting {
  var readiumNavigator: Navigator { navigator }
  var viewController: UIViewController { self }
}

extension AudioViewController: ReadiumReaderHosting {
  var readiumNavigator: Navigator { navigator }
  var viewController: UIViewController { self }
}
