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
    private let reorderButton = UIButton(type: .system)

    override func loadView() {
        view = tableView
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateTableHeaderLayout()
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

        let screenHeader = makeScreenHeader()
        let summary = makeTableSummary()
        summary.heightAnchor.constraint(greaterThanOrEqualToConstant: 94).isActive = true

        let stack = UIStackView(arrangedSubviews: [screenHeader, summary])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        header.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: header.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: header.bottomAnchor, constant: -14)
        ])

        return header
    }

    private func makeScreenHeader() -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.text = "Admin Table"
        titleLabel.adjustsFontForContentSizeCategory = true

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.text = "Selection, swipe, context menus, and reordering."
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let badgeLabel = CapsuleLabel()
        badgeLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.text = "  TABLE  "
        badgeLabel.backgroundColor = .systemIndigo
        badgeLabel.setContentHuggingPriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [textStack, badgeLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10
        return row
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

        reorderButton.setTitle("Reorder", for: .normal)
        reorderButton.setImage(UIImage(systemName: "arrow.up.arrow.down"), for: .normal)
        reorderButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        reorderButton.accessibilityIdentifier = "admin-table-reorder"
        reorderButton.addTarget(self, action: #selector(toggleTableEditing), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [title, tableSummaryDetailLabel])
        textStack.axis = .vertical
        textStack.spacing = 6

        let stack = UIStackView(arrangedSubviews: [textStack, reorderButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14)
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

    @objc private func toggleTableEditing() {
        tableView.setEditing(!tableView.isEditing, animated: true)
        reorderButton.setTitle(tableView.isEditing ? "Done" : "Reorder", for: .normal)
    }
}
