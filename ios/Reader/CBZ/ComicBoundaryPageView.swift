import UIKit

enum ComicBoundaryKind: String {
  case previous
  case next
}

/// Host-provided strings for one chapter boundary page. Mirrors the
/// `ComicBoundaryPage` Nitro struct without tying the reader to bridge types.
struct ComicBoundaryContent: Equatable {
  struct Action: Equatable {
    let id: String
    let label: String
    let secondary: Bool
  }

  var finishedLabel: String?
  var finishedTitle: String?
  var label: String?
  var title: String?
  var actions: [Action]
}

/// Full-viewport page shown before the first or after the last comic page in
/// scroll modes, laid out like the web reader's chapter boundary page: an
/// optional "Finished" section above a section with the adjacent chapter (or
/// the end-of-series message) and its actions.
final class ComicBoundaryPageView: UIView {
  /// Called with the action id when one of the page's buttons is pressed.
  var onAction: ((String) -> Void)?

  private let contentStack = UIStackView()
  private var content: ComicBoundaryContent?
  private var textColor: UIColor = .white
  private var pageBackgroundColor: UIColor = .black

  private static let maxContentWidth: CGFloat = 360
  private static let pagePadding: CGFloat = 32

  override init(frame: CGRect) {
    super.init(frame: frame)
    translatesAutoresizingMaskIntoConstraints = false

    contentStack.axis = .vertical
    contentStack.spacing = 48
    contentStack.translatesAutoresizingMaskIntoConstraints = false
    addSubview(contentStack)

    let preferredWidth = contentStack.widthAnchor.constraint(equalToConstant: Self.maxContentWidth)
    preferredWidth.priority = .defaultHigh
    NSLayoutConstraint.activate([
      contentStack.centerXAnchor.constraint(equalTo: centerXAnchor),
      contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
      contentStack.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor, constant: -Self.pagePadding * 2),
      contentStack.heightAnchor.constraint(lessThanOrEqualTo: heightAnchor, constant: -Self.pagePadding * 2),
      preferredWidth,
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func configure(_ content: ComicBoundaryContent, textColor: UIColor, backgroundColor: UIColor) {
    let themeChanged = textColor != self.textColor || backgroundColor != pageBackgroundColor
    self.textColor = textColor
    pageBackgroundColor = backgroundColor
    self.backgroundColor = backgroundColor
    guard content != self.content || themeChanged else { return }
    self.content = content
    rebuild()
  }

  private func rebuild() {
    contentStack.arrangedSubviews.forEach {
      contentStack.removeArrangedSubview($0)
      $0.removeFromSuperview()
    }
    guard let content else { return }

    if content.finishedLabel != nil || content.finishedTitle != nil {
      contentStack.addArrangedSubview(
        section(label: content.finishedLabel, title: content.finishedTitle, actions: [])
      )
    }
    if content.label != nil || content.title != nil || !content.actions.isEmpty {
      contentStack.addArrangedSubview(
        section(label: content.label, title: content.title, actions: content.actions)
      )
    }
  }

  private func section(label: String?, title: String?, actions: [ComicBoundaryContent.Action]) -> UIView {
    let stack = UIStackView()
    stack.axis = .vertical
    stack.spacing = 12
    stack.alignment = .fill

    if let label {
      stack.addArrangedSubview(textLabel(label, size: 18, weight: .bold))
    }
    if let title {
      stack.addArrangedSubview(textLabel(title, size: 22, weight: .bold))
    }
    for action in actions {
      stack.addArrangedSubview(button(for: action))
    }
    return stack
  }

  private func textLabel(_ text: String, size: CGFloat, weight: UIFont.Weight) -> UILabel {
    let label = UILabel()
    label.text = text
    label.numberOfLines = 0
    label.textColor = textColor
    label.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: size, weight: weight))
    label.adjustsFontForContentSizeCategory = true
    label.accessibilityTraits.insert(.header)
    return label
  }

  private func button(for action: ComicBoundaryContent.Action) -> UIButton {
    var configuration = action.secondary ? UIButton.Configuration.bordered() : UIButton.Configuration.filled()
    configuration.title = action.label
    configuration.cornerStyle = .fixed
    configuration.background.cornerRadius = 8
    configuration.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16)
    configuration.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
      var attributes = attributes
      attributes.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: .systemFont(ofSize: 15, weight: .semibold))
      return attributes
    }
    if action.secondary {
      configuration.baseForegroundColor = textColor
      configuration.background.backgroundColor = textColor.withAlphaComponent(0.04)
      configuration.background.strokeColor = textColor.withAlphaComponent(0.14)
      configuration.background.strokeWidth = 1
    } else {
      configuration.baseForegroundColor = pageBackgroundColor
      configuration.baseBackgroundColor = textColor
    }

    let button = UIButton(
      configuration: configuration,
      primaryAction: UIAction { [weak self] _ in
        self?.onAction?(action.id)
      }
    )
    button.accessibilityLabel = action.label
    return button
  }
}
