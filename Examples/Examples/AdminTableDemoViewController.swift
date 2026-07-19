import UIKit
import ListKit

@MainActor
final class AdminTableDemoViewController: LiveRoomDesignScreenViewController {
    private lazy var tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .insetGrouped)
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 72
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

    override func configureNavigation() {
        applyNavigationText(
            title: "Admin Table",
            inlineSubtitle: "\(viewModel.pendingModerationCount) active",
            largeSubtitle: "Selection, swipe actions, context menus, and reordering"
        )
        editButtonItem.accessibilityIdentifier = "admin-table-reorder"
        navigationItem.rightBarButtonItem = editButtonItem
    }

    override func buildContent() {
        tableView.allowsSelectionDuringEditing = true
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
        scheduleRender { [weak self, weak tableAdapter] in
            guard let self, let tableAdapter else { return }
            let options = ListApplyOptions(
                transaction: transaction,
                applicationMode: applicationMode
            )
            let result = await tableAdapter.applyAndWait(options: options) {
                self.viewModel.tableSections
            }
            guard !Task.isCancelled else { return }
            self.viewModel.recordTableApply(result.summary)
        }
    }

    private var tableSummaryText: String {
        "\(viewModel.pendingModerationCount) active · swipe, focus, reorder"
    }

    private func makeTableHeader() -> UIView {
        let header = UIView()
        header.backgroundColor = .clear
        header.accessibilityIdentifier = "admin-table-header"

        let summary = makeTableSummary()
        summary.translatesAutoresizingMaskIntoConstraints = false
        summary.heightAnchor.constraint(greaterThanOrEqualToConstant: 82).isActive = true
        header.addSubview(summary)

        NSLayoutConstraint.activate([
            summary.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            summary.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            summary.topAnchor.constraint(equalTo: header.topAnchor, constant: 12),
            summary.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -12)
        ])

        return header
    }

    private func updateTableHeaderLayout() {
        guard let header = tableView.tableHeaderView,
              tableView.bounds.width > 0 else { return }

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
            case .select(let id):
                self.viewModel.selectModeration(id)
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
        super.setEditing(editing, animated: animated)
        tableView.setEditing(editing, animated: animated)
    }
}
