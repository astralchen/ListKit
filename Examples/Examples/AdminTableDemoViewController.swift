import UIKit
import ListKit

@MainActor
final class AdminTableDemoViewController: LiveRoomDesignScreenViewController {
    private lazy var tableView: UITableView = {
        let tableView: UITableView = ProcessInfo.processInfo.arguments.contains("-AdminTableSelectionProbe")
            ? AdminTableSelectionProbeView(frame: .zero, style: .insetGrouped)
            : UITableView(frame: .zero, style: .insetGrouped)
        tableView.separatorStyle = .none
        tableView.sectionHeaderHeight = UITableView.automaticDimension
        tableView.accessibilityIdentifier = "admin-table-demo-table"
        if #available(iOS 15.0, *) {
            tableView.sectionHeaderTopPadding = 0
        }
        return tableView
    }()
    private lazy var tableAdapter = TableListAdapter<AdminSection>(tableView: tableView)
    private let tableSummaryDetailLabel = UILabel()

    override func loadView() {
        view = tableView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeaderLayout()
    }

    override func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTableHeaderLayout()
    }

    override func configureNavigation() {
        applyNavigationText(
            title: "Admin Table",
            inlineSubtitle: "\(viewModel.pendingModerationCount) active",
            largeSubtitle: "Selection, swipe actions, context menus, and reordering"
        )
        editButtonItem.accessibilityIdentifier = "admin-table-reorder"
        navigationItem.rightBarButtonItem = editButtonItem
        if let probe = tableView as? AdminTableSelectionProbeView, probe.holdsRefreshes {
            let resume = UIBarButtonItem(title: "Resume refresh", primaryAction: UIAction { [weak probe] _ in
                probe?.releaseHeldRender()
            })
            resume.accessibilityIdentifier = "admin-table-resume-render"
            navigationItem.leftBarButtonItem = resume
        }
    }

    override func buildContent() {
        tableView.allowsSelectionDuringEditing = true
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.dragInteractionEnabled = true
        tableView.tableHeaderView = makeTableHeader()
        configureEvents()
    }

    override func render(
        transaction: ListTransaction = .automatic,
        applicationMode: ListSnapshotApplicationMode = .differences
    ) {
        configureNavigation()
        tableSummaryDetailLabel.text = tableSummaryText
        let probe = tableView as? AdminTableSelectionProbeView
        let generation = probe?.beginRequest()
        scheduleRender { [weak self, weak tableAdapter, weak probe] in
            guard let self, let tableAdapter else { return }
            if let generation {
                await probe?.waitForRelease(generation: generation)
            }
            guard !Task.isCancelled else { return }
            let options = ListApplyOptions(
                transaction: transaction,
                applicationMode: applicationMode
            )
            let result = await tableAdapter.apply(options: options) {
                self.viewModel.tableSections
            }
            guard !Task.isCancelled else { return }
            self.viewModel.recordTableApply(result)
            if result.animation.completionState == .completed, let generation {
                probe?.complete(generation: generation)
            }
        }
    }

    private var tableSummaryText: String {
        "\(viewModel.pendingModerationCount) active · swipe, focus, reorder"
    }

    private func makeTableHeader() -> UIView {
        let header = UIView()
        header.backgroundColor = .clear
        header.accessibilityIdentifier = "admin-table-header"
        header.insetsLayoutMarginsFromSafeArea = false

        let summary = makeTableSummary()
        summary.translatesAutoresizingMaskIntoConstraints = false
        summary.heightAnchor.constraint(greaterThanOrEqualToConstant: 82).isActive = true
        header.addSubview(summary)

        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: header.layoutMarginsGuide.leadingAnchor),
            summary.trailingAnchor.constraint(equalTo: header.layoutMarginsGuide.trailingAnchor),
            summary.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            summary.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12)
        ])

        return header
    }

    private func updateTableHeaderLayout() {
        guard let header = tableView.tableHeaderView,
              tableView.bounds.width > 0 else { return }

        let safeAreaInsets = tableView.safeAreaInsets
        let isRightToLeft = tableView.effectiveUserInterfaceLayoutDirection == .rightToLeft
        header.directionalLayoutMargins = NSDirectionalEdgeInsets(
            top: 0,
            leading: 20 + (isRightToLeft ? safeAreaInsets.right : safeAreaInsets.left),
            bottom: 0,
            trailing: 20 + (isRightToLeft ? safeAreaInsets.left : safeAreaInsets.right)
        )

        let targetSize = CGSize(
            width: tableView.bounds.width,
            height: UIView.layoutFittingCompressedSize.height
        )
        let height = header.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel
        ).height

        guard header.frame.width != targetSize.width || header.frame.height != height else { return }
        header.frame.size = CGSize(width: targetSize.width, height: height)
        tableView.tableHeaderView = header
    }

    private func makeTableSummary() -> UIView {
        let container = UIView()
        container.backgroundColor = .secondarySystemGroupedBackground
        container.accessibilityIdentifier = "admin-table-summary"
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.separator.cgColor

        let title = UILabel()
        title.font = UIFont.preferredFont(forTextStyle: .headline)
        title.textColor = .label
        title.text = "Moderation Queue"
        title.adjustsFontForContentSizeCategory = true

        tableSummaryDetailLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        tableSummaryDetailLabel.textColor = .secondaryLabel
        tableSummaryDetailLabel.text = tableSummaryText
        tableSummaryDetailLabel.adjustsFontForContentSizeCategory = true
        tableSummaryDetailLabel.numberOfLines = 2

        let textStack = UIStackView(arrangedSubviews: [title, tableSummaryDetailLabel])
        textStack.axis = .vertical
        textStack.spacing = 6
        textStack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(textStack)

        NSLayoutConstraint.activate([
            textStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            textStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
        ])

        return container
    }

    private func configureEvents() {
        tableAdapter.onEvent(LiveRoomAdminEvent.self) { [weak self] event, context in
            guard let self,
                  context.section(as: AdminSection.self) == .moderation,
                  context.item(as: String.self) != nil else { return }
            switch event {
            case .selectionChanged(let id, let isSelected):
                self.viewModel.setModerationSelection(id, isSelected: isSelected)
            case .resolve(let id):
                self.viewModel.handleModeration(id)
            }
            self.render(transaction: .automatic)
        }
        tableAdapter
            .onPrefetchRows { [weak self] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count)
            }
            .onCancelPrefetchingRows { [weak self] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count, cancelled: true)
            }
    }

    override func setEditing(_ editing: Bool, animated: Bool) {
        let selectedRows = tableView.indexPathsForSelectedRows ?? []
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
        // UIKit 退出多选编辑时会清空选择；此页面在两种模式下共享同一份选择状态。
        for indexPath in selectedRows {
            tableView.selectRow(at: indexPath, animated: false, scrollPosition: .none)
        }
    }
}

/// 仅用于 UI 回归：每次查询都读取表格真实状态，避免把控制器的请求状态当作切换已完成。
@MainActor
private final class AdminTableSelectionProbeView: UITableView {
    let holdsRefreshes = ProcessInfo.processInfo.arguments.contains("-AdminTableHoldRefreshes")
    private var requestedGeneration = 0
    private var completedGeneration = 0
    private var heldGeneration: Int?
    private var heldRender: CheckedContinuation<Void, Never>?

    func beginRequest() -> Int {
        releaseHeldRender()
        requestedGeneration += 1
        return requestedGeneration
    }

    func waitForRelease(generation: Int) async {
        guard holdsRefreshes, generation > 1, generation == requestedGeneration else { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else {
                    continuation.resume()
                    return
                }
                heldGeneration = generation
                heldRender = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.releaseHeldRender(generation: generation)
            }
        }
    }

    func releaseHeldRender(generation: Int? = nil) {
        if let generation, heldGeneration != generation { return }
        let continuation = heldRender
        heldRender = nil
        heldGeneration = nil
        continuation?.resume()
    }

    func complete(generation: Int) {
        guard generation == requestedGeneration else { return }
        completedGeneration = generation
    }

    override var accessibilityValue: String? {
        get {
            let state: [String: Any] = [
                "editing": isEditing,
                "requestedGeneration": requestedGeneration,
                "completedGeneration": completedGeneration,
                "heldGeneration": heldGeneration ?? 0,
            ]
            guard let data = try? JSONSerialization.data(withJSONObject: state) else { return nil }
            return String(data: data, encoding: .utf8)
        }
        set { super.accessibilityValue = newValue }
    }
}
