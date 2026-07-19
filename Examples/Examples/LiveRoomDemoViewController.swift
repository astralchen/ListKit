import UIKit
import ListKit

@MainActor
final class LiveRoomDemoViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        tabBar.accessibilityIdentifier = "design-scheme-tabs"
        tabBar.tintColor = .systemBlue
        tabBar.unselectedItemTintColor = .secondaryLabel

        let liveConsole = LiveConsoleDesignViewController()
        liveConsole.tabBarItem = UITabBarItem(
            title: "Live Console",
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            selectedImage: UIImage(systemName: "dot.radiowaves.left.and.right")
        )

        let studioControl = StudioControlDesignViewController()
        studioControl.tabBarItem = UITabBarItem(
            title: "Studio Control",
            image: UIImage(systemName: "slider.horizontal.3"),
            selectedImage: UIImage(systemName: "slider.horizontal.3")
        )

        let roomToolkit = RoomToolkitDesignViewController()
        roomToolkit.tabBarItem = UITabBarItem(
            title: "Room Toolkit",
            image: UIImage(systemName: "wrench.and.screwdriver"),
            selectedImage: UIImage(systemName: "wrench.and.screwdriver.fill")
        )

        let adminTable = AdminTableDemoViewController()
        adminTable.tabBarItem = UITabBarItem(
            title: "Admin Table",
            image: UIImage(systemName: "tablecells"),
            selectedImage: UIImage(systemName: "tablecells.fill")
        )

        viewControllers = [liveConsole, studioControl, roomToolkit, adminTable]
        selectedIndex = 0
    }
}

@MainActor
private class LiveRoomDesignScreenViewController: UIViewController {
    let viewModel: LiveRoomViewModel

    private let screenIdentifier: String
    private var renderTask: Task<Void, Never>?

    init(screenIdentifier: String, viewModel: LiveRoomViewModel = LiveRoomViewModel()) {
        self.screenIdentifier = screenIdentifier
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        configureBaseView()
        buildContent()
        render(animatingDifferences: false)
    }

    func buildContent() {
        preconditionFailure("Subclasses must build their screen content.")
    }

    func render(animatingDifferences: Bool) {
        preconditionFailure("Subclasses must render ListKit output.")
    }

    func scheduleRender(_ operation: @escaping @MainActor () async -> Void) {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            await operation()
        }
    }

    func makeCollectionView(identifier: String) -> UICollectionView {
        let view = UICollectionView(frame: .zero, collectionViewLayout: Self.placeholderLayout())
        view.backgroundColor = .clear
        view.alwaysBounceVertical = false
        view.isScrollEnabled = true
        view.keyboardDismissMode = .onDrag
        view.accessibilityIdentifier = identifier
        view.contentInsetAdjustmentBehavior = .always
        view.automaticallyAdjustsScrollIndicatorInsets = true
        view.configureDemoScrollEdgeEffects()
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func makeTableView(identifier: String) -> UITableView {
        let view = UITableView(frame: .zero, style: .plain)
        view.backgroundColor = .clear
        view.separatorStyle = .none
        view.isScrollEnabled = true
        view.rowHeight = UITableView.automaticDimension
        view.estimatedRowHeight = 72
        view.sectionHeaderHeight = UITableView.automaticDimension
        view.accessibilityIdentifier = identifier
        view.configureDemoScrollEdgeEffects()
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func makeScreenHeader(title: String, subtitle: String, badge: String? = nil) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let titleLabel = UILabel()
        titleLabel.font = UIFont.systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.text = title
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        let subtitleLabel = UILabel()
        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.text = subtitle
        subtitleLabel.numberOfLines = 2
        subtitleLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let row = UIStackView(arrangedSubviews: [textStack])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 10

        if let badge {
            let badgeLabel = CapsuleLabel()
            badgeLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
            badgeLabel.textColor = .white
            badgeLabel.textAlignment = .center
            badgeLabel.text = "  \(badge)  "
            badgeLabel.backgroundColor = .systemIndigo
            row.addArrangedSubview(badgeLabel)
        }

        let menuButton = UIButton(type: .system)
        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .label
        menuButton.backgroundColor = UIColor.tertiarySystemFill
        menuButton.layer.cornerRadius = 22
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        row.addArrangedSubview(menuButton)

        row.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(row)

        NSLayoutConstraint.activate([
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            row.topAnchor.constraint(equalTo: container.topAnchor),
            row.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    func makeTitleRow(title: String, detail: String? = nil, buttonTitle: String? = nil, symbolName: String? = nil) -> UIView {
        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        titleLabel.textColor = .label
        titleLabel.text = title
        titleLabel.adjustsFontForContentSizeCategory = true

        let spacer = UIView()
        let stack = UIStackView(arrangedSubviews: [titleLabel, spacer])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12

        if let detail {
            let detailLabel = UILabel()
            detailLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
            detailLabel.textColor = .secondaryLabel
            detailLabel.text = detail
            detailLabel.adjustsFontForContentSizeCategory = true
            stack.addArrangedSubview(detailLabel)
        }

        if let buttonTitle {
            let button = UIButton(type: .system)
            button.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
            button.setTitle(buttonTitle, for: .normal)
            if let symbolName {
                button.setImage(UIImage(systemName: symbolName), for: .normal)
            }
            stack.addArrangedSubview(button)
        }

        return stack
    }

    func makeChipRow(_ titles: [String]) -> UIView {
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 8
        stack.distribution = .fillProportionally

        for title in titles {
            let chip = UIButton(type: .system)
            chip.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
            chip.setTitle(title, for: .normal)
            chip.setTitleColor(.label, for: .normal)
            chip.backgroundColor = .secondarySystemGroupedBackground
            chip.layer.cornerRadius = 14
            chip.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
            stack.addArrangedSubview(chip)
        }

        return stack
    }

    func makeLiveRoomPreviewCard() -> UIView {
        let model = viewModel.titleViewModel
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 16
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.separator.cgColor

        let badge = UILabel()
        badge.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        badge.textColor = .systemGreen
        badge.textAlignment = .center
        badge.text = "LIVE"
        badge.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        badge.layer.cornerRadius = 8
        badge.layer.masksToBounds = true

        let title = UILabel()
        title.font = UIFont.preferredFont(forTextStyle: .title2)
        title.textColor = .label
        title.text = model.title
        title.adjustsFontForContentSizeCategory = true

        let subtitle = UILabel()
        subtitle.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitle.textColor = .secondaryLabel
        subtitle.text = "Host \(viewModel.titleViewModel.title == "Room Toolkit" ? "Alex" : "Mira")"
        subtitle.adjustsFontForContentSizeCategory = true

        let metrics = UIStackView(arrangedSubviews: [
            makeMetricPill(symbolName: "person.2.fill", value: "1,248", label: "Audience", tint: .systemBlue),
            makeMetricPill(symbolName: "bolt.fill", value: "8,932", label: "Heat", tint: .systemBlue),
            makeMetricPill(symbolName: "shield.fill", value: "7", label: "Admin", tint: .systemBlue)
        ])
        metrics.axis = .horizontal
        metrics.alignment = .fill
        metrics.distribution = .fillEqually
        metrics.spacing = 10

        let stack = UIStackView(arrangedSubviews: [badge, title, subtitle, metrics])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            badge.widthAnchor.constraint(equalToConstant: 72),
            badge.heightAnchor.constraint(equalToConstant: 28),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -16)
        ])

        return container
    }

    func makeMicPreviewGrid() -> UIView {
        let seats = [
            ("A", "Alex", "Host", "Live", true),
            ("M", "Mia", "Moderator", "Ready", false),
            ("D", "Daniel", "Speaker", "Muted", false),
            ("S", "Sophie", "Top Gifter", "Ready", false),
            ("M", "Michael", "Listener", "Ready", false)
        ]

        let firstRow = UIStackView()
        firstRow.axis = .horizontal
        firstRow.distribution = .fillEqually
        firstRow.spacing = 10

        let secondRow = UIStackView()
        secondRow.axis = .horizontal
        secondRow.distribution = .fillEqually
        secondRow.spacing = 10

        for (index, seat) in seats.enumerated() {
            let card = makeMicPreviewCard(initial: seat.0, name: seat.1, role: seat.2, state: seat.3, selected: seat.4)
            if index < 3 {
                firstRow.addArrangedSubview(card)
            } else {
                secondRow.addArrangedSubview(card)
            }
        }

        let spacer = UIView()
        secondRow.addArrangedSubview(spacer)

        let stack = UIStackView(arrangedSubviews: [firstRow, secondRow])
        stack.axis = .vertical
        stack.spacing = 10
        return stack
    }

    func makeActivityPreviewCard() -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 14
        container.layer.borderWidth = 1
        container.layer.borderColor = UIColor.separator.cgColor

        let first = makeActivityPreviewRow(initial: "E", name: "Emma", time: "just now", message: "Loving the new ListKit live demo!", meta: "12")
        let second = makeActivityPreviewRow(initial: "D", name: "Daniel", time: "30s ago", message: "The diffable data source feels so smooth.", meta: "7")

        let stack = UIStackView(arrangedSubviews: [first, second])
        stack.axis = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }

    func configureCollectionEvents(_ adapter: CollectionListAdapter<LiveRoomSection>, onChange: @escaping @MainActor () -> Void) {
        adapter.onEvent(LiveRoomCollectionEvent.self) { [weak self] event, context in
            guard let self else { return }
            switch event {
            case .addMessage:
                self.viewModel.sendMessage()
                onChange()
            case .sendSelectedGift:
                self.viewModel.sendGift()
                onChange()
            case .sendGift(let giftID):
                self.viewModel.selectGift(giftID)
                self.viewModel.sendGift()
                onChange()
            case .studioModeChanged(let index):
                self.viewModel.selectStudioMode(index)
                onChange()
            case .activateCapability(let title):
                guard context.section(as: LiveRoomSection.self) == .apiGuide,
                      context.item(as: LiveRoomRowID.self) != nil else { return }
                self.viewModel.activateCapability(title)
                onChange()
            }
        }
        adapter
            .onPrefetchItems { [weak self, weak adapter] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count)
                adapter?.reconfigureVisibleRows(forRowID: LiveRoomRowID.diagnostics, in: .diagnostics)
            }
            .onCancelPrefetchingItems { [weak self, weak adapter] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count, cancelled: true)
                adapter?.reconfigureVisibleRows(forRowID: LiveRoomRowID.diagnostics, in: .diagnostics)
            }
    }

    func applyCollection(
        _ adapter: CollectionListAdapter<LiveRoomSection>,
        collectionView: UICollectionView,
        sections: [ListSection<LiveRoomSection>],
        animatingDifferences: Bool
    ) {
        scheduleRender { [weak self, weak adapter, weak collectionView] in
            guard let self, let adapter, let collectionView else { return }
            let options = ListApplyOptions(
                animatingDifferences: animatingDifferences,
                applicationMode: animatingDifferences ? .differences : .reloadData
            )
            let result = await adapter.apply(options: options) {
                sections
            }
            guard !Task.isCancelled else { return }

            self.viewModel.recordCollectionApply(result.summary)
            adapter.reconfigureVisibleRows(forRowID: LiveRoomRowID.diagnostics, in: .diagnostics)

            if let messageID = self.viewModel.pendingScrollMessageID,
               let indexPath = adapter.indexPaths(forRowID: messageID).first {
                collectionView.scrollToItem(at: indexPath, at: .bottom, animated: true)
                self.viewModel.clearPendingScroll()
            }
        }
    }

    func applyTable(
        _ adapter: TableListAdapter<AdminSection>,
        tableView: UITableView,
        animatingDifferences: Bool
    ) {
        scheduleRender { [weak self, weak adapter, weak tableView] in
            guard let self, let adapter, let tableView else { return }
            let options = ListApplyOptions(
                animatingDifferences: animatingDifferences,
                applicationMode: animatingDifferences ? .differences : .reloadData
            )
            let result = await adapter.apply(options: options) {
                self.viewModel.tableSections
            }
            guard !Task.isCancelled else { return }
            self.viewModel.recordTableApply(result.summary)
            tableView.layoutIfNeeded()
        }
    }

    func configureTableEvents(
        _ adapter: TableListAdapter<AdminSection>,
        onChange: @escaping @MainActor () -> Void
    ) {
        adapter.onEvent(LiveRoomAdminEvent.self) { [weak self] event, context in
            guard let self else { return }
            guard context.section(as: AdminSection.self) == .moderation,
                  context.item(as: String.self) != nil else { return }
            switch event {
            case .select(let id):
                self.viewModel.selectModeration(id)
            case .resolve(let id):
                self.viewModel.handleModeration(id)
            }
            onChange()
        }
        adapter
            .onPrefetchRows { [weak self] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count)
            }
            .onCancelPrefetchingRows { [weak self] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count, cancelled: true)
            }
    }

    func configureBaseView() {
        view.backgroundColor = .systemGroupedBackground
        view.accessibilityIdentifier = screenIdentifier
    }
}

extension UIScrollView {
    func configureDemoScrollEdgeEffects() {
        if #available(iOS 26.0, *) {
            topEdgeEffect.isHidden = true
            leftEdgeEffect.isHidden = true
            bottomEdgeEffect.isHidden = true
            rightEdgeEffect.isHidden = true
        }
    }
}

@MainActor
private class LiveRoomStackDesignScreenViewController: LiveRoomDesignScreenViewController {
    private let stackView = UIStackView()

    override func configureBaseView() {
        super.configureBaseView()

        stackView.axis = .vertical
        stackView.alignment = .fill
        stackView.spacing = 12
        stackView.isLayoutMarginsRelativeArrangement = true
        stackView.layoutMargins = UIEdgeInsets(top: 18, left: 20, bottom: 14, right: 20)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(stackView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stackView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: guide.topAnchor),
            stackView.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])
    }

    func addArrangedView(_ view: UIView, height: CGFloat? = nil) {
        view.translatesAutoresizingMaskIntoConstraints = false
        stackView.addArrangedSubview(view)

        if let height {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = .defaultHigh
            constraint.isActive = true
        }
    }
}

private extension LiveRoomDesignScreenViewController {

    private func makeMetricPill(symbolName: String, value: String, label: String, tint: UIColor) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: symbolName))
        icon.tintColor = tint
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false

        let valueLabel = UILabel()
        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.text = value

        let labelView = UILabel()
        labelView.font = UIFont.preferredFont(forTextStyle: .caption2)
        labelView.textColor = .secondaryLabel
        labelView.text = label

        let textStack = UIStackView(arrangedSubviews: [valueLabel, labelView])
        textStack.axis = .vertical
        textStack.spacing = 1

        let stack = UIStackView(arrangedSubviews: [icon, textStack])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 7

        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18)
        ])

        return stack
    }

    private func makeMicPreviewCard(initial: String, name: String, role: String, state: String, selected: Bool) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        container.layer.cornerRadius = 10
        container.layer.borderWidth = selected ? 2 : 1
        container.layer.borderColor = (selected ? UIColor.systemGreen : UIColor.separator).cgColor

        let avatar = UILabel()
        avatar.font = UIFont.systemFont(ofSize: 20, weight: .bold)
        avatar.textColor = .white
        avatar.textAlignment = .center
        avatar.text = initial
        avatar.backgroundColor = .systemIndigo
        avatar.layer.cornerRadius = 24
        avatar.layer.masksToBounds = true
        avatar.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        nameLabel.textColor = .label
        nameLabel.textAlignment = .center
        nameLabel.text = name

        let roleLabel = UILabel()
        roleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        roleLabel.textColor = .secondaryLabel
        roleLabel.textAlignment = .center
        roleLabel.text = role

        let stateLabel = UILabel()
        stateLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        stateLabel.textColor = selected ? .systemGreen : .secondaryLabel
        stateLabel.textAlignment = .center
        stateLabel.text = state
        stateLabel.backgroundColor = selected ? UIColor.systemGreen.withAlphaComponent(0.12) : UIColor.tertiarySystemFill
        stateLabel.layer.cornerRadius = 6
        stateLabel.layer.masksToBounds = true

        let stack = UIStackView(arrangedSubviews: [avatar, nameLabel, roleLabel, stateLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(stack)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 48),
            avatar.heightAnchor.constraint(equalToConstant: 48),
            stateLabel.widthAnchor.constraint(equalTo: container.widthAnchor, constant: -18),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -10)
        ])

        return container
    }

    private func makeActivityPreviewRow(initial: String, name: String, time: String, message: String, meta: String) -> UIView {
        let avatar = UILabel()
        avatar.font = UIFont.systemFont(ofSize: 17, weight: .bold)
        avatar.textColor = .white
        avatar.textAlignment = .center
        avatar.text = initial
        avatar.backgroundColor = .systemGreen
        avatar.layer.cornerRadius = 22
        avatar.layer.masksToBounds = true
        avatar.translatesAutoresizingMaskIntoConstraints = false

        let nameLabel = UILabel()
        nameLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        nameLabel.textColor = .label
        nameLabel.text = name

        let timeLabel = UILabel()
        timeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        timeLabel.textColor = .tertiaryLabel
        timeLabel.text = time

        let messageLabel = UILabel()
        messageLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        messageLabel.textColor = .label
        messageLabel.numberOfLines = 2
        messageLabel.text = message

        let replyLabel = UILabel()
        replyLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        replyLabel.textColor = .secondaryLabel
        replyLabel.text = "Reply"

        let nameRow = UIStackView(arrangedSubviews: [nameLabel, timeLabel])
        nameRow.axis = .horizontal
        nameRow.alignment = .firstBaseline
        nameRow.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [nameRow, messageLabel, replyLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let metaLabel = UILabel()
        metaLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        metaLabel.textColor = .systemRed
        metaLabel.textAlignment = .right
        metaLabel.text = meta

        let row = UIStackView(arrangedSubviews: [avatar, textStack, metaLabel])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)

        NSLayoutConstraint.activate([
            avatar.widthAnchor.constraint(equalToConstant: 44),
            avatar.heightAnchor.constraint(equalToConstant: 44),
            metaLabel.widthAnchor.constraint(equalToConstant: 40)
        ])

        return row
    }

    private static func placeholderLayout() -> UICollectionViewLayout {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(44)
            )
        )
        let group = NSCollectionLayoutGroup.vertical(
            layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .estimated(44)
            ),
            subitems: [item]
        )
        return UICollectionViewCompositionalLayout(section: NSCollectionLayoutSection(group: group))
    }
}

@MainActor
private final class LiveConsoleDesignViewController: LiveRoomDesignScreenViewController {
    private lazy var collectionView = makeCollectionView(identifier: "live-console-collection")
    private lazy var collectionAdapter = CollectionListAdapter<LiveRoomSection>(collectionView: collectionView)

    init() {
        super.init(screenIdentifier: "live-console-screen")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .systemGroupedBackground
        rootView.accessibilityIdentifier = "live-console-screen"
        view = rootView
    }

    override func viewDidLoad() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        buildContent()
        render(animatingDifferences: false)
    }

    override func buildContent() {
        collectionView.alwaysBounceVertical = true
        collectionView.setCollectionViewLayout(
            collectionAdapter.makeCompositionalLayout(
                configuration: .init(interSectionSpacing: 4, contentInsetsReference: .none)
            ),
            animated: false
        )
        configureCollectionEvents(collectionAdapter) { [weak self] in
            self?.render(animatingDifferences: true)
        }
    }

    override func render(animatingDifferences: Bool) {
        applyCollection(
            collectionAdapter,
            collectionView: collectionView,
            sections: viewModel.liveConsoleSections,
            animatingDifferences: animatingDifferences
        )
    }
}

@MainActor
private final class StudioControlDesignViewController: LiveRoomDesignScreenViewController {
    private lazy var collectionView = makeCollectionView(identifier: "studio-control-collection")
    private lazy var collectionAdapter = CollectionListAdapter<LiveRoomSection>(collectionView: collectionView)

    init() {
        super.init(screenIdentifier: "studio-control-screen")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let rootView = UIView()
        rootView.backgroundColor = .systemGroupedBackground
        rootView.accessibilityIdentifier = "studio-control-screen"
        view = rootView
    }

    override func viewDidLoad() {
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        buildContent()
        render(animatingDifferences: false)
    }

    override func buildContent() {
        collectionView.alwaysBounceVertical = true
        collectionView.setCollectionViewLayout(
            collectionAdapter.makeCompositionalLayout(
                configuration: .init(interSectionSpacing: 4, contentInsetsReference: .none)
            ),
            animated: false
        )
        configureCollectionEvents(collectionAdapter) { [weak self] in
            self?.render(animatingDifferences: true)
        }
    }

    override func render(animatingDifferences: Bool) {
        applyCollection(
            collectionAdapter,
            collectionView: collectionView,
            sections: viewModel.studioControlSections,
            animatingDifferences: animatingDifferences
        )
    }
}

@MainActor
private final class RoomToolkitDesignViewController: LiveRoomDesignScreenViewController {
    private lazy var collectionView = makeCollectionView(identifier: "room-toolkit-screen")
    private lazy var collectionAdapter = CollectionListAdapter<LiveRoomSection>(collectionView: collectionView)

    init() {
        super.init(screenIdentifier: "room-toolkit-screen")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        collectionView.backgroundColor = .systemGroupedBackground
        view = collectionView
    }

    override func buildContent() {
        collectionView.alwaysBounceVertical = true
        collectionView.setCollectionViewLayout(
            collectionAdapter.makeCompositionalLayout(
                configuration: .init(interSectionSpacing: 4, contentInsetsReference: .none)
            ),
            animated: false
        )
        configureCollectionEvents(collectionAdapter) { [weak self] in
            self?.render(animatingDifferences: true)
        }
    }

    override func render(animatingDifferences: Bool) {
        applyCollection(
            collectionAdapter,
            collectionView: collectionView,
            sections: viewModel.roomToolkitSections,
            animatingDifferences: animatingDifferences
        )
    }
}

@MainActor
private final class AdminTableDemoViewController: LiveRoomStackDesignScreenViewController {
    private lazy var tableView = makeTableView(identifier: "admin-table-demo-table")
    private lazy var tableAdapter = TableListAdapter<AdminSection>(tableView: tableView)
    private let tableSummaryDetailLabel = UILabel()
    private let reorderButton = UIButton(type: .system)

    init() {
        super.init(screenIdentifier: "admin-table-screen")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func buildContent() {
        addArrangedView(
            makeScreenHeader(
                title: "Admin Table",
                subtitle: "UITableView adapter demo for selection, swipe actions, context menus, and row reconfigure.",
                badge: "TABLE"
            ),
            height: 82
        )

        addArrangedView(makeTableSummary(), height: 86)

        tableView.backgroundColor = .secondarySystemGroupedBackground
        tableView.layer.cornerRadius = 16
        tableView.layer.borderWidth = 1
        tableView.layer.borderColor = UIColor.separator.cgColor
        tableView.layer.masksToBounds = true
        tableView.allowsSelectionDuringEditing = true
        tableView.dragInteractionEnabled = true
        configureTableEvents(tableAdapter) { [weak self] in
            self?.render(animatingDifferences: true)
        }
        addArrangedView(tableView)
    }

    override func render(animatingDifferences: Bool) {
        tableSummaryDetailLabel.text = "\(viewModel.pendingModerationCount) active actions - swipe, focus, or reorder rows"
        applyTable(tableAdapter, tableView: tableView, animatingDifferences: animatingDifferences)
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
        tableSummaryDetailLabel.text = "\(viewModel.pendingModerationCount) active actions - swipe, focus, or reorder rows"
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

    @objc private func toggleTableEditing() {
        tableView.setEditing(!tableView.isEditing, animated: true)
        reorderButton.setTitle(tableView.isEditing ? "Done" : "Reorder", for: .normal)
    }
}
