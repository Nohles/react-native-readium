import Combine
import Foundation
import ReadiumShared
import UIKit

protocol PublicationReaderViewController: AnyObject {
  var publication: Publication { get }
  var bookId: String { get }
  var publisher: AnyPublisher<ReadiumShared.Locator, Never> { get }

  func goTo(_ locator: ReadiumShared.Locator) async
  func goForward() async
  func goBackward() async
}

typealias PublicationReaderViewControllerType = UIViewController & PublicationReaderViewController
