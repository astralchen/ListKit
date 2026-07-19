import UIKit
import ListKit

@MainActor
class LiveRoomCollectionDesignScreenViewController: LiveRoomDesignScreenViewController {
    private let sectionsKeyPath: KeyPath<LiveRoomViewModel, [ListSection<LiveRoomSection>]>
    private let navigationKeyPath: KeyPath<LiveRoomViewModel, ScreenNavigationViewModel>
    private let navigationMenuIdentifier: String
    private let collectionView: UICollectionView

    private lazy var collectionAdapter = CollectionListAdapter<LiveRoomSection>(collectionView: collectionView)
    private lazy var navigationMenuItem: UIBarButtonItem = {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis"),
            primaryAction: nil,
            menu: nil
        )
        item.accessibilityLabel = "More Actions"
        item.accessibilityIdentifier = navigationMenuIdentifier
        return item
    }()

    init(
        collectionIdentifier: String,
        sections: KeyPath<LiveRoomViewModel, [ListSection<LiveRoomSection>]>,
        navigation: KeyPath<LiveRoomViewModel, ScreenNavigationViewModel>,
        navigationMenuIdentifier: String
    ) {
        self.collectionView = Self.makeCollectionView(identifier: collectionIdentifier)
        self.sectionsKeyPath = sections
        self.navigationKeyPath = navigation
        self.navigationMenuIdentifier = navigationMenuIdentifier
        super.init()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = collectionView
    }

    override func configureNavigation() {
        let model = viewModel[keyPath: navigationKeyPath]
        applyNavigationText(
            title: model.title,
            inlineSubtitle: model.inlineSubtitle,
            largeSubtitle: model.largeSubtitle
        )
        navigationMenuItem.menu = LiveRoomActionMenu.make(items: model.menuItems) { [weak self] action in
            self?.performNavigationAction(action)
        }
        navigationItem.rightBarButtonItem = navigationMenuItem
    }

    override func buildContent() {
        collectionView.setCollectionViewLayout(
            collectionAdapter.makeCompositionalLayout(
                configuration: .init(interSectionSpacing: 4, contentInsetsReference: .none)
            ),
            animated: false
        )
        configureEvents()
    }

    override func render(
        transaction: ListTransaction = .automatic,
        applicationMode: ListSnapshotApplicationMode = .differences
    ) {
        configureNavigation()
        let sections = viewModel[keyPath: sectionsKeyPath]
        scheduleRender { [weak self, weak collectionAdapter] in
            guard let self, let collectionAdapter else { return }
            let options = ListApplyOptions(
                transaction: transaction,
                applicationMode: applicationMode
            )
            let result = await collectionAdapter.applyAndWait(options: options) {
                sections
            }
            guard !Task.isCancelled else { return }

            self.viewModel.recordCollectionApply(result.summary)
            collectionAdapter.reconfigureVisibleRows(forRowID: LiveRoomRowID.diagnostics, in: .diagnostics)
            if self.viewModel.pendingScrollMessageID != nil {
                self.viewModel.clearPendingScroll()
            }
        }
    }

    private func configureEvents() {
        collectionAdapter.onEvent(LiveRoomCollectionEvent.self) { [weak self] event, context in
            guard let self else { return }
            var transaction = ListTransaction.automatic
            switch event {
            case .addMessage:
                self.viewModel.sendMessage()
                transaction = self.transactionScrollingToPendingMessage(transaction)
            case .sendSelectedGift:
                self.viewModel.sendGift()
                transaction = self.transactionScrollingToPendingMessage(transaction)
            case .sendGift(let giftID):
                self.viewModel.selectGift(giftID)
                self.viewModel.sendGift()
                transaction = self.transactionScrollingToPendingMessage(transaction)
            case .studioModeChanged(let index):
                self.viewModel.selectStudioMode(index)
            case .roomActivityFilterChanged(let filter):
                guard context.section(as: LiveRoomSection.self) == .roomActivityTitle,
                      context.item(as: LiveRoomRowID.self) == .roomActivityTitle else { return }
                guard self.viewModel.activityFilter != filter else { return }
                self.viewModel.setRoomActivityFilter(filter)
                transaction = transaction
                    .snapshotAnimation(.disabled)
                    .layoutAnimation(.disabled)
                    .scrollAnimation(.disabled)
                    .scrollBehavior(
                        .preserveVisiblePosition(
                            of: ListScrollTarget(
                                LiveRoomRowID.roomActivityTitle,
                                in: LiveRoomSection.roomActivityTitle
                            )
                        )
                    )
            case .activateCapability(let title):
                guard context.section(as: LiveRoomSection.self) == .apiGuide,
                      context.item(as: LiveRoomRowID.self) != nil else { return }
                self.viewModel.activateCapability(title)
                transaction = self.transactionScrollingToPendingMessage(transaction)
            }
            self.render(transaction: transaction)
        }
        collectionAdapter
            .onPrefetchItems { [weak self, weak collectionAdapter] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count)
                collectionAdapter?.reconfigureVisibleRows(forRowID: LiveRoomRowID.diagnostics, in: .diagnostics)
            }
            .onCancelPrefetchingItems { [weak self, weak collectionAdapter] contexts in
                self?.viewModel.recordPrefetch(itemCount: contexts.count, cancelled: true)
                collectionAdapter?.reconfigureVisibleRows(forRowID: LiveRoomRowID.diagnostics, in: .diagnostics)
            }
    }

    private func performNavigationAction(_ action: LiveRoomMenuAction) {
        viewModel.performMenuAction(action)
        var transaction = ListTransaction.automatic
        switch action {
        case .addMessage, .sendSelectedGift, .addSystemEvent:
            transaction = transactionScrollingToPendingMessage(transaction)
        case .resetDemo:
            transaction = .disabled
        case .refreshStatus, .selectStudioMode:
            break
        }
        render(transaction: transaction)
    }

    private func transactionScrollingToPendingMessage(
        _ transaction: ListTransaction
    ) -> ListTransaction {
        guard let messageID = viewModel.pendingScrollMessageID else { return transaction }
        return transaction.scrollBehavior(
            .scrollTo(ListScrollTarget(messageID), position: .bottom)
        )
    }

    private static func makeCollectionView(identifier: String) -> UICollectionView {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: placeholderLayout())
        collectionView.alwaysBounceVertical = true
        collectionView.keyboardDismissMode = .onDrag
        collectionView.accessibilityIdentifier = identifier
        collectionView.contentInsetAdjustmentBehavior = .always
        return collectionView
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
final class LiveConsoleDesignViewController: LiveRoomCollectionDesignScreenViewController {
    init() {
        super.init(
            collectionIdentifier: "live-console-collection",
            sections: \.liveConsoleSections,
            navigation: \.liveConsoleNavigation,
            navigationMenuIdentifier: "live-console-header-menu"
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class StudioControlDesignViewController: LiveRoomCollectionDesignScreenViewController {
    init() {
        super.init(
            collectionIdentifier: "studio-control-collection",
            sections: \.studioControlSections,
            navigation: \.studioControlNavigation,
            navigationMenuIdentifier: "studio-control-header-menu"
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

@MainActor
final class RoomToolkitDesignViewController: LiveRoomCollectionDesignScreenViewController {
    init() {
        super.init(
            collectionIdentifier: "room-toolkit-screen",
            sections: \.roomToolkitSections,
            navigation: \.roomToolkitNavigation,
            navigationMenuIdentifier: "room-toolkit-header-menu"
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
