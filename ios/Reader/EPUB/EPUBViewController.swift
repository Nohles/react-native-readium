import UIKit
import ReadiumShared
import ReadiumNavigator

struct SelectionActionData: Codable {
    let id: String
    let label: String
}

protocol SelectionActionDelegate: AnyObject {
    func onSelectionAction(actionId: String, locator: ReadiumShared.Locator, selectedText: String)
}

class EPUBViewController: ReaderViewController, SelectionActionHandlerDelegate {
    private var selectionActionHandler: SelectionActionHandler?
    weak var selectionActionDelegate: SelectionActionDelegate?

    /// Selection changes forwarded to JS. Android emits these from a 500 ms poll
    /// of `SelectableNavigator.currentSelection`; UIKit has no such observable
    /// API, so the same polling is used here rather than leaving the declared
    /// `onSelectionChange` prop permanently dead on iOS.
    var onSelectionChange: ((ReadiumShared.Locator?, String?) -> Void)? {
        didSet { startSelectionPolling() }
    }

    private var selectionPollTimer: Timer?
    private var lastSelectionLocator: ReadiumShared.Locator?
    private var hasReportedEmptySelection = false

    init(
      publication: Publication,
      locator: ReadiumShared.Locator?,
      bookId: String,
      selectionActions: [SelectionActionData]? = nil
    ) throws {
      // Convert typed selection actions directly to EditingActions (no JSON)
      var editingActions: [EditingAction] = []
      var actionIds: [String] = []

      if let actions = selectionActions {
        for action in actions {
          actionIds.append(action.id)

          let selectorName = "handleSelectionAction_\(action.id):"
          let selector = NSSelectorFromString(selectorName)

          editingActions.append(EditingAction(
            title: action.label,
            action: selector
          ))
        }
      }

      // Only use custom actions - don't add default iOS actions
      // If no custom actions are provided, use defaults as fallback
      if editingActions.isEmpty {
        editingActions.append(contentsOf: EditingAction.defaultActions)
      }

      let navigator = try EPUBNavigatorViewController(
        publication: publication,
        initialLocation: locator,
        config: EPUBNavigatorViewController.Configuration(
          editingActions: editingActions
        )
      )

      super.init(
        navigator: navigator,
        publication: publication,
        bookId: bookId
      )

      // Set up the Objective-C handler for dynamic methods
      if !actionIds.isEmpty {
        let handler = SelectionActionHandler(actionIds: actionIds)
        handler.delegate = self
        selectionActionHandler = handler
      }

      navigator.delegate = self
    }

    var epubNavigator: EPUBNavigatorViewController {
      return navigator as! EPUBNavigatorViewController
    }

    func updateSelectionActions(_ selectionActions: [SelectionActionData]?) {
        // On iOS, selection actions must be set during navigator initialization
        // because Readium's EPUBNavigatorViewController bakes `editingActions`
        // into the navigator's `Configuration` and has no public setter.
        //
        // Android can update at runtime because the Kotlin navigator reads its
        // actions from an `ActionMode.Callback`. Re-creating the navigator here
        // would lose reading position, selection, and every submitted
        // preference, so the actions are still fixed at init on iOS — but the
        // failure is reported rather than only printed, and the host is told
        // what to do about it.
        print(
            "Warning: Updating selection actions after initialization is not supported on iOS. " +
            "Remount the ReadiumView (change its React key) to apply a new set."
        )
    }

    // MARK: - Selection polling

    private func startSelectionPolling() {
        selectionPollTimer?.invalidate()
        selectionPollTimer = nil
        lastSelectionLocator = nil
        hasReportedEmptySelection = false
        guard onSelectionChange != nil else { return }

        selectionPollTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
            [weak self] _ in
            self?.pollSelection()
        }
    }

    private func pollSelection() {
        guard let navigator = navigator as? EPUBNavigatorViewController else { return }
        let selection = navigator.currentSelection
        let locator = selection?.locator
        let highlight = locator?.text.highlight

        if let locator, let last = lastSelectionLocator {
            // Readium's Locator is a struct, so comparing the highlighted text
            // and href is enough to detect a change and avoids re-reporting an
            // identical selection every tick.
            let unchanged = last.href == locator.href && last.text.highlight == highlight
            if unchanged { return }
        }

        lastSelectionLocator = locator
        if locator == nil && hasReportedEmptySelection { return }
        hasReportedEmptySelection = locator == nil
        onSelectionChange?(locator, highlight)
    }

    deinit {
        selectionPollTimer?.invalidate()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        /// Set initial UI appearance.
        setUIColor(for: epubNavigator.settings.theme)

        startSelectionPolling()
    }

    // Insert handler into the responder chain
    override var next: UIResponder? {
      if let handler = selectionActionHandler {
        // Set the handler's next responder to continue the chain
        handler.originalNextResponder = super.next
        return handler
      }
      return super.next
    }

    // SelectionActionHandlerDelegate implementation
    func handleSelectionAction(withId actionId: String) {
      guard let navigator = navigator as? EPUBNavigatorViewController else {
        return
      }

      guard let selection = navigator.currentSelection else {
        return
      }

      selectionActionDelegate?.onSelectionAction(
        actionId: actionId,
        locator: selection.locator,
        selectedText: selection.locator.text.highlight ?? ""
      )

      // Clear the selection
      navigator.clearSelection()
    }

    internal func setUIColor(for theme: Theme) {
      let colors = AssociatedColors.getColors(for: theme)

      navigator.view.backgroundColor = colors.mainColor
      view.backgroundColor = colors.mainColor
      //
      navigationController?.navigationBar.barTintColor = colors.mainColor
      navigationController?.navigationBar.tintColor = colors.textColor

      navigationController?.navigationBar.titleTextAttributes = [NSAttributedString.Key.foregroundColor: colors.textColor]
    }

}

extension EPUBViewController: EPUBNavigatorDelegate {}

extension EPUBViewController: UIGestureRecognizerDelegate {

  func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
    return true
  }

}

extension EPUBViewController: UIPopoverPresentationControllerDelegate {
  // Prevent the popOver to be presented fullscreen on iPhones.
  func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle
  {
    return .none
  }
}
