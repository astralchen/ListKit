import UIKit
import ListKit

/// 演示 Collection Row 的菜单位置、配置透传、定向预览及完整生命周期。
@MainActor
final class ContextMenuDemoViewController: UIViewController {
    /// 两种预览策略使用独立稳定身份，便于观察回调是否来自正确的行。
    private enum Item: String, CaseIterable, Hashable, Sendable {
        /// 使用源 cell 的系统菜单高亮，不提供独立内容控制器。
        case original = "Original card"
        /// 提供独立内容预览，点击预览后演示提交回调。
        case preview = "Preview & Commit"

        /// 当前演示模式的操作提示。
        var detail: String {
            switch self {
            case .original: "Long press to highlight this card. Tap outside to dismiss."
            case .preview: "Long press, then tap the preview to commit or choose an action."
            }
        }
    }

    /// 页面内单调递增的菜单编号；清空日志不会复用旧编号。
    private var sequence = 0
    /// 按回调发生顺序保存的有界事件日志。
    private var entries: [String] = []
    /// 最近一次生命周期通知及菜单编号。
    private let statusLabel = UILabel()
    /// 独立于源列表刷新的只读日志视图。
    private let logView = UITextView()
    /// 承载两个稳定菜单目标的列表。
    private let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    /// 接管原生菜单路由并将通知分发给 Row DSL。
    private lazy var adapter = CollectionListAdapter<Int>(collectionView: collectionView)

    /// 使用系统布局组合示例卡片和可滚动日志，避免菜单回调期间更新列表 snapshot。
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Context Menu APIs"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        let clear = UIBarButtonItem(title: "Clear Log", primaryAction: UIAction { [weak self] _ in
            self?.entries.removeAll()
            self?.logView.text = "Long press a card to begin."
        })
        clear.accessibilityIdentifier = "context-menu-clear-log"
        navigationItem.rightBarButtonItem = clear

        let instruction = UILabel()
        instruction.text = "Explore location, configuration, previews and lifecycle callbacks. Coordinates are in the collection view."
        instruction.font = .preferredFont(forTextStyle: .subheadline)
        instruction.textColor = .secondaryLabel
        instruction.numberOfLines = 0
        instruction.adjustsFontForContentSizeCategory = true

        collectionView.backgroundColor = .clear
        collectionView.accessibilityIdentifier = "context-menu-demo-collection"
        collectionView.setCollectionViewLayout(adapter.makeCompositionalLayout(), animated: false)

        statusLabel.text = "Idle"
        statusLabel.font = .preferredFont(forTextStyle: .headline)
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "context-menu-demo-status"
        statusLabel.adjustsFontForContentSizeCategory = true

        logView.text = "Long press a card to begin."
        logView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logView.backgroundColor = .secondarySystemGroupedBackground
        logView.textColor = .label
        logView.isEditable = false
        logView.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        logView.layer.cornerRadius = 12
        logView.accessibilityIdentifier = "context-menu-demo-log"
        let stack = UIStackView(arrangedSubviews: [instruction, collectionView, statusLabel, logView])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -12),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32),
            collectionView.heightAnchor.constraint(equalToConstant: 232),
            logView.heightAnchor.constraint(equalToConstant: 220)
        ])
        adapter.apply(transaction: .disabled) { makeSections() }
    }

    /// 每个闭包均消费新 API 提供的参数；页面弱捕获，菜单动画不会保活已退出的页面。
    private func makeSections() -> [ListSection<Int>] {
        [ListSection(0) {
            for item in Item.allCases {
                Row(item, model: item, cell: UICollectionViewListCell.self) { cell, item, _ in
                    var content = cell.defaultContentConfiguration()
                    content.text = item.rawValue
                    content.secondaryText = item.detail
                    content.secondaryTextProperties.numberOfLines = 0
                    content.image = UIImage(systemName: item == .original ? "hand.point.up.left" : "rectangle.on.rectangle")
                    cell.contentConfiguration = content
                    cell.accessibilityIdentifier = item == .original ? "context-menu-original" : "context-menu-preview"
                }
                .contextMenu { [weak self] context, point in
                    self?.makeConfiguration(item: item, context: context, point: point)
                }
                .contextMenuPreview(highlighting: { [weak self] context, configuration in
                    self?.targetedPreview(context: context, configuration: configuration, phase: "highlightPreview")
                }, dismissal: { [weak self] context, configuration in
                    self?.targetedPreview(context: context, configuration: configuration, phase: "dismissalPreview")
                })
                .onContextMenuWillDisplay { [weak self] _, configuration, animator in
                    guard let self else { return }
                    let id = self.identifier(configuration)
                    self.record("willDisplay · \(id) · animator: \(animator != nil)")
                    self.statusLabel.text = "Presenting · \(id)"
                    self.statusLabel.alpha = 0.5
                    let animations: () -> Void = { [weak self] in self?.statusLabel.alpha = 1 }
                    let completion: () -> Void = { [weak self] in
                        self?.record("displayCompleted · \(id)")
                        self?.statusLabel.text = "Visible · \(id)"
                    }
                    if let animator {
                        animator.addAnimations(animations)
                        animator.addCompletion(completion)
                    } else {
                        animations()
                        completion()
                    }
                }
                .onContextMenuWillEnd { [weak self] _, configuration, animator in
                    guard let self else { return }
                    let id = self.identifier(configuration)
                    self.record("willEnd · \(id) · animator: \(animator != nil)")
                    self.statusLabel.text = "Ending · \(id)"
                    let completion: () -> Void = { [weak self] in
                        self?.record("endCompleted · \(id)")
                        self?.statusLabel.text = "Ended · \(id)"
                    }
                    if let animator { animator.addCompletion(completion) } else { completion() }
                }
                .onContextMenuCommit { [weak self] context, configuration, animator in
                    guard let self else { return }
                    let id = self.identifier(configuration)
                    self.record("commit · \(id) · row: \(context.item(as: Item.self)?.rawValue ?? "unknown")")
                    animator.preferredCommitStyle = .dismiss
                    animator.addCompletion { [weak self] in
                        self?.record("commitCompleted · \(id)")
                        self?.statusLabel.text = "Committed · \(id)"
                    }
                }
            }
        } layout: {
            UIKitListLayout(appearance: .insetGrouped, headerTopPadding: 0)
        }]
    }

    /// 将触发位置与唯一菜单编号带入内容预览，菜单行为和所有回调共享同一个 configuration。
    private func makeConfiguration(item: Item, context: ListContext, point: CGPoint) -> UIContextMenuConfiguration {
        sequence += 1
        let id = "\(item.rawValue) #\(sequence)"
        let location = String(format: "x: %.1f, y: %.1f", point.x, point.y)
        record("configuration · \(id) · \(location) · item: \(context.indexPath.item)")
        let previewProvider: UIContextMenuContentPreviewProvider? = item == .preview ? {
            let controller = UIViewController()
            controller.preferredContentSize = CGSize(width: 300, height: 180)
            controller.view.backgroundColor = .secondarySystemBackground
            let label = UILabel()
            label.text = "\(id)\n\n\(location)\nTap this preview to commit."
            label.font = .preferredFont(forTextStyle: .body)
            label.textAlignment = .center
            label.numberOfLines = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            controller.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor, constant: 20),
                label.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -20),
                label.centerYAnchor.constraint(equalTo: controller.view.centerYAnchor)
            ])
            return controller
        } : nil
        return UIContextMenuConfiguration(identifier: id as NSString, previewProvider: previewProvider) { [weak self] _ in
            UIMenu(children: [UIAction(title: "Record Action", image: UIImage(systemName: "checkmark.circle")) { [weak self] _ in
                self?.record("actionSelected · \(id)")
            }])
        }
    }

    /// 仅对仍在窗口内的当前 cell 提供预览，并记录 configuration 在各阶段的关联身份。
    private func targetedPreview(context: ListContext, configuration: UIContextMenuConfiguration, phase: String) -> UITargetedPreview? {
        record("\(phase) · \(identifier(configuration)) · item: \(context.indexPath.item)")
        guard let collection = context.collectionViewIfAvailable,
              let cell = collection.cellForItem(at: context.indexPath), cell.window != nil else { return nil }
        return UITargetedPreview(view: cell)
    }

    /// 读取业务配置标识，直观显示同一菜单在各个 API 间的传递过程。
    private func identifier(_ configuration: UIContextMenuConfiguration) -> String {
        configuration.identifier as? String ?? "unknown"
    }

    /// 日志最多保留 60 条；只更新独立文本视图，不在菜单过渡期间重建源 cell。
    private func record(_ event: String) {
        entries.append(event)
        if entries.count > 60 { entries.removeFirst(entries.count - 60) }
        logView.text = entries.joined(separator: "\n")
        logView.scrollRangeToVisible(NSRange(location: logView.text.utf16.count, length: 0))
    }
}
