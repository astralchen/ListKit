import XCTest
import UIKit
@testable import ListKit

@MainActor
final class ListKitCoreTests: XCTestCase {
    func testBuilderSupportsForEachAndConditionalRows() {
        let users = [
            User(id: 1, name: "A", isVIP: false, version: 1),
            User(id: 2, name: "B", isVIP: true, version: 1)
        ]

        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                ForEach(users, id: \.id) { user in
                    if user.isVIP {
                        Row(model: user, cell: VIPUserCell.self) { cell, user, _ in
                            cell.name = user.name
                        }
                        .refreshID(user.version)
                    } else {
                        Row(model: user, cell: NormalUserCell.self) { cell, user, _ in
                            cell.name = user.name
                        }
                        .refreshID(user.version)
                    }
                }
            }
            .header(HeaderView.self, id: "header") { view, _ in
                view.title = "Users"
            }
        }

        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections[0].rows.count, 2)
        XCTAssertEqual(sections[0].supplementaries.count, 1)
        XCTAssertEqual(sections[0].rows[0].identity.rowID.typed(Int.self), 1)
        XCTAssertEqual(sections[0].rows[1].identity.rowID.typed(Int.self), 2)
    }

    func testForEachSupportsClosureIDForFallbackIdentity() {
        let users = [
            UserProfile(userID: "", accountID: "account-1", name: "A"),
            UserProfile(userID: "user-2", accountID: "account-2", name: "B")
        ]

        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                ForEach(users, id: { user in
                    user.userID.isEmpty ? "account-\(user.accountID)" : user.userID
                }) { user in
                    Row(model: user, cell: NormalUserCell.self) { cell, user, _ in
                        cell.name = user.name
                    }
                }
            }
        }

        XCTAssertEqual(sections[0].rows[0].identity.rowID.typed(String.self), "account-account-1")
        XCTAssertEqual(sections[0].rows[1].identity.rowID.typed(String.self), "user-2")
    }

    func testSingleIdentifiableModelRowUsesModelID() {
        let row = Row(model: IdentifiedUser(id: 7, name: "A"), cell: NormalUserCell.self) { cell, user, _ in
            cell.name = user.name
        }
        .eraseToAnyListRow(sectionID: 0)

        XCTAssertEqual(row.identity.rowID.typed(Int.self), 7)
    }

    func testSingleModelRowSupportsKeyPathID() {
        let row = Row(model: User(id: 9, name: "A", isVIP: false, version: 1), id: \.id, cell: NormalUserCell.self) { cell, user, _ in
            cell.name = user.name
        }
        .eraseToAnyListRow(sectionID: 0)

        XCTAssertEqual(row.identity.rowID.typed(Int.self), 9)
    }

    func testProviderRowUsesExplicitPresentationIdentityAndSelection() {
        let row = ProviderRow("provider", cell: NormalUserCell.self) { collectionView, indexPath, _ in
            let cell = collectionView.lk.dequeue(NormalUserCell.self, for: indexPath)
            cell.name = "provider"
            return cell
        }
        .onSelect { context in
            XCTAssertEqual(context.indexPath.item, 0)
        }
        .eraseToAnyListRows(sectionID: 0)[0]

        XCTAssertEqual(row.identity.rowID.typed(String.self), "provider")
        XCTAssertEqual(row.identity.presentationID, ObjectIdentifier(NormalUserCell.self))
    }

    func testCollectionReusableHelpersExposeCellKitMigrationUtilities() {
        XCTAssertEqual(UICollectionView.elementKind(for: HeaderView.self), "HeaderView")
        XCTAssertEqual(
            UICollectionView.elementKindSectionBackgroundDecoration,
            "UICollectionView.ElementKindSectionBackgroundDecoration"
        )

        let layout = UICollectionViewCompositionalSeparatorLayout(section: NSCollectionLayoutSection(
            group: NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(44)
                ),
                subitems: [
                    NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .fractionalHeight(1)
                    ))
                ]
            )
        ))
        layout.separatorInsets = .init(top: 0, leading: 12, bottom: 0, trailing: 12)
        XCTAssertEqual(layout.separatorInsets.leading, 12)
    }

    func testCollectionReusableNamespaceCreatesCellRegistrationWithClassFallback() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let registration: UICollectionView.CellRegistration<NormalUserCell, User> = collectionView.lk.cellRegistration(
            NormalUserCell.self
        ) { cell, _, user in
            cell.name = user.name
        }

        let cell = collectionView.dequeueConfiguredReusableCell(
            using: registration,
            for: IndexPath(item: 0, section: 0),
            item: User(id: 1, name: "A", isVIP: false, version: 1)
        )

        XCTAssertEqual(cell.name, "A")
    }

    func testCollectionReusableNamespaceCreatesSupplementaryRegistrationWithClassFallback() {
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1),
                heightDimension: .fractionalHeight(1)
            ))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: NSCollectionLayoutSize(
                    widthDimension: .fractionalWidth(1),
                    heightDimension: .absolute(44)
                ),
                subitems: [item]
            )
            let section = NSCollectionLayoutSection(group: group)
            section.boundarySupplementaryItems = [
                NSCollectionLayoutBoundarySupplementaryItem(
                    layoutSize: NSCollectionLayoutSize(
                        widthDimension: .fractionalWidth(1),
                        heightDimension: .absolute(24)
                    ),
                    elementKind: UICollectionView.elementKindSectionHeader,
                    alignment: .top
                )
            ]
            return section
        }
        let collectionView = UICollectionView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 120),
            collectionViewLayout: layout
        )
        let cellRegistration = UICollectionView.CellRegistration<UICollectionViewCell, Int> { _, _, _ in }
        let dataSource = UICollectionViewDiffableDataSource<Int, Int>(
            collectionView: collectionView
        ) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(
                using: cellRegistration,
                for: indexPath,
                item: item
            )
        }
        let registration = collectionView.lk.supplementaryRegistration(
            HeaderView.self,
            ofKind: UICollectionView.elementKindSectionHeader
        ) { view, kind, _ in
            view.title = kind
        }
        dataSource.supplementaryViewProvider = { collectionView, _, indexPath in
            collectionView.dequeueConfiguredReusableSupplementary(
                using: registration,
                for: indexPath
            )
        }
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems([0])
        dataSource.apply(snapshot, animatingDifferences: false)
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let view = dataSource.collectionView(
            collectionView,
            viewForSupplementaryElementOfKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        ) as? HeaderView

        XCTAssertEqual(view?.title, UICollectionView.elementKindSectionHeader)
    }

    func testIdentityUsesCellTypeAndRefreshIDSeparately() {
        let normal = Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            .refreshID(1)
            .eraseToAnyListRow(sectionID: 0)
        let refreshed = Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
            .refreshID(2)
            .eraseToAnyListRow(sectionID: 0)
        let vip = Row(1, model: User(id: 1, name: "B", isVIP: true, version: 2), cell: VIPUserCell.self) { _, _, _ in }
            .refreshID(2)
            .eraseToAnyListRow(sectionID: 0)

        XCTAssertEqual(normal.identity, refreshed.identity)
        XCTAssertNotEqual(normal.refreshID, refreshed.refreshID)
        XCTAssertNotEqual(normal.identity, vip.identity)
    }

    func testAdapterDispatchesSelectionAndCustomEvents() async {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var selectedID: Int?
        var receivedEvent: UserEvent?

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, context in
                    context.send(UserEvent.avatarTap(userID: 1))
                }
                .onSelect { context in
                    selectedID = context.indexPath.item
                }
            }
        }
        .onEvent(UserEvent.self) { event, _ in
            receivedEvent = event
        }

        adapter.collectionView(collectionView, didSelectItemAt: IndexPath(item: 0, section: 0))
        _ = adapter.collectionView(collectionView, cellForItemAt: IndexPath(item: 0, section: 0))

        XCTAssertEqual(selectedID, 0)
        XCTAssertEqual(receivedEvent, .avatarTap(userID: 1))
    }

    func testVariantChangesIdentityForSameCellType() {
        let compact = Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            .variant("compact")
            .eraseToAnyListRow(sectionID: 0)
        let expanded = Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            .variant("expanded")
            .eraseToAnyListRow(sectionID: 0)

        XCTAssertNotEqual(compact.identity, expanded.identity)
    }

    func testVisibleReconfigureUsesExistingCell() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let context = ListContext(
            sectionID: AnyListID(0),
            indexPath: IndexPath(item: 0, section: 0),
            collectionView: collectionView
        ) { _, _ in }
        let row = Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { cell, user, _ in
            cell.name = user.name
        }
        .eraseToAnyListRow(sectionID: 0)
        let existingCell = NormalUserCell()

        row.configureVisibleCell(existingCell, context)

        XCTAssertEqual(existingCell.name, "B")
    }

    func testHeaderTapCanSendCustomEvent() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        var receivedEvent: UserEvent?
        let context = ListContext(
            sectionID: AnyListID(0),
            indexPath: IndexPath(item: 0, section: 0),
            collectionView: collectionView
        ) { event, _ in
            receivedEvent = event as? UserEvent
        }
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .header(HeaderView.self, id: "header") { _, _ in }
        .onHeaderTap { context in
            context.send(UserEvent.headerTap)
        }

        section.supplementaries.first?.tapHandler?(context)

        XCTAssertEqual(receivedEvent, .headerTap)
    }

    func testSupplementaryTapInstallerPreservesExternalTapRecognizers() {
        let view = UICollectionReusableView()
        let externalTap = UITapGestureRecognizer()
        view.addGestureRecognizer(externalTap)

        ListTapHandlerInstaller.install(on: view) {}
        XCTAssertEqual(view.gestureRecognizers?.count, 2)
        XCTAssertTrue(view.gestureRecognizers?.contains(externalTap) == true)

        ListTapHandlerInstaller.install(on: view) {}
        XCTAssertEqual(view.gestureRecognizers?.count, 2)
        XCTAssertTrue(view.gestureRecognizers?.contains(externalTap) == true)
    }

    func testDiagnosticsReportsDuplicateIdentities() {
        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
            }
            .header(HeaderView.self, id: "same-header") { _, _ in }
            .supplementary(UICollectionView.elementKindSectionHeader, HeaderView.self, id: "same-header") { _, _ in }

            ListSection(0) {
                Row(2, model: User(id: 2, name: "C", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        let issues = ListDiagnostics.validate(sections)

        XCTAssertTrue(issues.contains { $0.kind == .duplicateSection })
        XCTAssertTrue(issues.contains { $0.kind == .duplicateRow })
        XCTAssertTrue(issues.contains { $0.kind == .duplicateSupplementary })
    }

    func testApplyOptionsExposeSummaryAndAvoidDuplicateDiffableCrash() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let options = ListApplyOptions(
            animatingDifferences: false,
            refreshStrategy: .diffableOnly,
            diagnostics: .disabled
        )

        _ = adapter.apply(options: options) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        let result = adapter.apply(options: options) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(2)
                    .refreshPolicy(.whenRefreshIDChanges)
                Row(2, model: User(id: 2, name: "C", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertEqual(result.summary.insertedCount, 1)
        XCTAssertEqual(result.summary.keptCount, 1)
        XCTAssertEqual(result.summary.refreshIDChangedCount, 1)
        XCTAssertEqual(result.summary.snapshotRefreshCount, 1)

        let duplicateResult = adapter.apply(
            options: ListApplyOptions(
                animatingDifferences: false,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            )
        ) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        XCTAssertTrue(duplicateResult.summary.diagnosticsIssues.contains { $0.kind == .duplicateRow })
    }

    func testApplyRefreshShortcutUsesApplyLevelStrategy() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        _ = adapter.apply(refresh: .diffableOnly, animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(1)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        let result = adapter.apply(refresh: .diffableOnly, animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "B", isVIP: false, version: 2), cell: NormalUserCell.self) { _, _, _ in }
                    .refreshID(2)
                    .refreshPolicy(.whenRefreshIDChanges)
            }
        }

        XCTAssertEqual(result.summary.keptCount, 1)
        XCTAssertEqual(result.summary.refreshIDChangedCount, 1)
        XCTAssertEqual(result.summary.snapshotRefreshCount, 1)
        XCTAssertEqual(result.summary.visibleRefreshCount, 0)
    }

    func testModelAwareRowEventsAndPrefetchReceiveModel() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var selectedUserID: Int?
        var deselectedUserID: Int?
        var prefetchedUserID: Int?
        var cancelledUserID: Int?

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onSelect { user, _ in selectedUserID = user.id }
                    .onDeselect { user, _ in deselectedUserID = user.id }
                    .onPrefetch { user, _ in prefetchedUserID = user.id }
                    .onCancelPrefetch { user, _ in cancelledUserID = user.id }
            }
        }

        let indexPath = IndexPath(item: 0, section: 0)
        adapter.collectionView(collectionView, didSelectItemAt: indexPath)
        adapter.collectionView(collectionView, didDeselectItemAt: indexPath)
        adapter.collectionView(collectionView, prefetchItemsAt: [indexPath])
        adapter.collectionView(collectionView, cancelPrefetchingForItemsAt: [indexPath])

        XCTAssertEqual(selectedUserID, 1)
        XCTAssertEqual(deselectedUserID, 1)
        XCTAssertEqual(prefetchedUserID, 1)
        XCTAssertEqual(cancelledUserID, 1)
    }

    func testCollectionLifecycleUsesCapturedRowAfterSnapshotChanges() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let displayDelegate = CollectionDisplayDelegateSpy()
        var endedUserID: Int?
        var cancelledUserID: Int?
        adapter.displayDelegate = displayDelegate

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onEndDisplay { _, _ in endedUserID = 1 }
                    .onCancelPrefetch { user, _ in cancelledUserID = user.id }
            }
        }

        let oldIndexPath = IndexPath(item: 0, section: 0)
        let oldCell = NormalUserCell()
        adapter.collectionView(collectionView, willDisplay: oldCell, forItemAt: oldIndexPath)
        adapter.collectionView(collectionView, prefetchItemsAt: [oldIndexPath])

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(2, model: User(id: 2, name: "B", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        adapter.collectionView(collectionView, didEndDisplaying: oldCell, forItemAt: oldIndexPath)
        adapter.collectionView(collectionView, cancelPrefetchingForItemsAt: [oldIndexPath])

        XCTAssertEqual(endedUserID, 1)
        XCTAssertEqual(cancelledUserID, 1)
        XCTAssertEqual(displayDelegate.didEndDisplayingCount, 1)
    }

    func testCollectionSelectionModeIsEnforcedPerSection() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var deselectedUserID: Int?

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(0, model: User(id: 0, name: "None", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .selectionMode(.none)
            ListSection(1) {
                Row(10, model: User(id: 10, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onDeselect { user, _ in deselectedUserID = user.id }
                Row(11, model: User(id: 11, name: "B", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .selectionMode(.single)
            ListSection(2) {
                Row(20, model: User(id: 20, name: "C", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .selectionMode(.multiple)
        }

        let disabled = IndexPath(item: 0, section: 0)
        let firstSingle = IndexPath(item: 0, section: 1)
        let secondSingle = IndexPath(item: 1, section: 1)
        let multiple = IndexPath(item: 0, section: 2)

        XCTAssertTrue(collectionView.allowsSelection)
        XCTAssertTrue(collectionView.allowsMultipleSelection)
        XCTAssertFalse(adapter.collectionView(collectionView, shouldSelectItemAt: disabled))
        XCTAssertTrue(adapter.collectionView(collectionView, shouldSelectItemAt: firstSingle))
        XCTAssertTrue(adapter.collectionView(collectionView, shouldSelectItemAt: multiple))

        collectionView.selectItem(at: firstSingle, animated: false, scrollPosition: [])
        collectionView.selectItem(at: secondSingle, animated: false, scrollPosition: [])
        adapter.collectionView(collectionView, didSelectItemAt: secondSingle)

        XCTAssertFalse(collectionView.indexPathsForSelectedItems?.contains(firstSingle) ?? false)
        XCTAssertTrue(collectionView.indexPathsForSelectedItems?.contains(secondSingle) ?? false)
        XCTAssertEqual(deselectedUserID, 10)
    }

    func testCellEventBindingSendsTypedEvent() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var receivedEvent: UserEvent?

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: EventCell.self) { _, _, _ in }
                    .onCellEvent({ cell, send in
                        cell.onButtonTap = send
                    }, send: { user in
                        UserEvent.buttonTap(userID: user.id)
                    })
            }
        }
        .onEvent(UserEvent.self) { event, _ in
            receivedEvent = event
        }

        let cell = adapter.collectionView(collectionView, cellForItemAt: IndexPath(item: 0, section: 0)) as? EventCell
        cell?.onButtonTap?()

        XCTAssertEqual(receivedEvent, .buttonTap(userID: 1))
    }

    func testStateRowsCreateStableIdentities() {
        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                ListStateRow.empty(EmptyStateCell.self) { cell, _ in
                    cell.message = "empty"
                }
                ListStateRow.loading(LoadingStateCell.self) { cell, _ in
                    cell.message = "loading"
                }
                ListStateRow.failure(FailureStateCell.self) { cell, _ in
                    cell.message = "failure"
                }
            }
        }

        XCTAssertEqual(sections[0].rows.count, 3)
        XCTAssertEqual(sections[0].rows[0].identity.rowID.typed(ListStateRowKind.self), .empty)
        XCTAssertEqual(sections[0].rows[1].identity.rowID.typed(ListStateRowKind.self), .loading)
        XCTAssertEqual(sections[0].rows[2].identity.rowID.typed(ListStateRowKind.self), .failure)
    }

    func testSectionMetadataSelectionAndSupplementaryEnhancements() {
        let header = Supplementary(
            UICollectionView.elementKindSectionHeader,
            id: "header",
            view: HeaderView.self
        ) { _, _ in }
            .refreshID(2)
            .refreshPolicy(.whenRefreshIDChanges)

        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                .selected(true)
        }
        .layout("user-grid")
        .selectionMode(.multiple)
        .stickyHeader()
        .backgroundDecoration("user-background")
        .supplementary(header)
        .supplementary("badge", HeaderView.self, id: "badge") { _, _ in }

        XCTAssertEqual(section.layoutID?.typed(String.self), "user-grid")
        XCTAssertEqual(section.selectionMode, .multiple)
        XCTAssertTrue(section.isHeaderSticky)
        XCTAssertEqual(section.backgroundDecorationKind, "user-background")
        XCTAssertTrue(section.rows[0].isSelected == true)
        XCTAssertEqual(section.supplementaries[0].refreshPolicy, .whenRefreshIDChanges)
        XCTAssertEqual(section.supplementaries.map(\.kind), [UICollectionView.elementKindSectionHeader, "badge"])
    }

    func testSelectionChangeAndDelegateForwarding() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let scrollDelegate = ScrollDelegateSpy()
        let layoutDelegate = FlowLayoutDelegateSpy()
        var selectionChanges: [Bool] = []

        adapter.scrollDelegate = scrollDelegate
        adapter.layoutDelegate = layoutDelegate
        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
                    .onSelectionChange { isSelected, _ in
                        selectionChanges.append(isSelected)
                    }
            }
        }

        let indexPath = IndexPath(item: 0, section: 0)
        adapter.collectionView(collectionView, didSelectItemAt: indexPath)
        adapter.collectionView(collectionView, didDeselectItemAt: indexPath)
        adapter.scrollViewDidScroll(collectionView)
        let size = adapter.collectionView(collectionView, layout: collectionView.collectionViewLayout, sizeForItemAt: indexPath)

        XCTAssertEqual(selectionChanges, [true, false])
        XCTAssertEqual(scrollDelegate.didScrollCount, 1)
        XCTAssertEqual(size, CGSize(width: 44, height: 55))
        XCTAssertEqual(layoutDelegate.sizeRequestCount, 1)
    }

    func testScrollDelegateIsNotForwardedDuringSnapshotApply() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let scrollDelegate = ScrollDelegateSpy()
        adapter.scrollDelegate = scrollDelegate

        adapter.isApplyingSnapshot = true
        adapter.scrollViewDidScroll(collectionView)
        XCTAssertEqual(scrollDelegate.didScrollCount, 0)

        adapter.isApplyingSnapshot = false
        adapter.scrollViewDidScroll(collectionView)
        XCTAssertEqual(scrollDelegate.didScrollCount, 1)
    }

    func testLayoutDSLKiroSpecFilesExist() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let specRoot = packageRoot
            .appendingPathComponent(".kiro")
            .appendingPathComponent("specs")
            .appendingPathComponent("listkit-layout-dsl")

        let requirements = try String(contentsOf: specRoot.appendingPathComponent("requirements.md"))
        let design = try String(contentsOf: specRoot.appendingPathComponent("design.md"))
        let tasks = try String(contentsOf: specRoot.appendingPathComponent("tasks.md"))

        XCTAssertTrue(requirements.contains(".layout(.grid(columns: 2, spacing: 12))"))
        XCTAssertTrue(design.contains("ListSupplementaryPlacement"))
        XCTAssertTrue(tasks.contains("compositional layout helper"))
    }

    func testSectionLayoutDSLPreservesLegacyLayoutID() {
        let gridSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 2, spacing: 12))

        guard case let .gridConfiguration(grid)? = gridSection.sectionLayout else {
            return XCTFail("Expected grid layout")
        }
        XCTAssertEqual(grid.columns, 2)
        XCTAssertEqual(grid.spacing, 12)

        let legacySection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout("legacy-grid")

        XCTAssertEqual(legacySection.layoutID?.typed(String.self), "legacy-grid")
        XCTAssertNil(legacySection.sectionLayout)
    }

    func testSectionLayoutBuilderSwitchesLayoutConditionally() {
        let gridSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } layout: {
            if true {
                GridLayout(columns: 2, spacing: 12)
            } else {
                ListLayout(spacing: 8)
            }
        }

        let defaultSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } layout: {
            if false {
                GridLayout(columns: 2, spacing: 12)
            }
        }

        XCTAssertEqual(gridSection.sectionLayout, ListSectionLayout.grid(columns: 2, spacing: 12))
        XCTAssertNil(defaultSection.sectionLayout)
    }

    func testSectionLayoutModifiersUseLastLayoutSource() {
        let legacyThenList = ListSection(0) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout("legacy")
        .layout(.list(spacing: 8))

        let listThenCustom = ListSection(1) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 2, spacing: 12))
        .layout(.custom(id: "manual") { _, _, _ in
            ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        })

        let customThenLegacy = ListSection(2) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.custom(id: "manual") { _, _, _ in
            ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        })
        .layout("legacy")

        XCTAssertNil(legacyThenList.layoutID)
        XCTAssertEqual(legacyThenList.sectionLayout, .list(spacing: 8))
        XCTAssertNil(legacyThenList.customSectionLayout)

        XCTAssertNil(listThenCustom.layoutID)
        XCTAssertNil(listThenCustom.sectionLayout)
        XCTAssertEqual(listThenCustom.customSectionLayout?.id.typed(String.self), "manual")

        XCTAssertEqual(customThenLegacy.layoutID?.typed(String.self), "legacy")
        XCTAssertNil(customThenLegacy.sectionLayout)
        XCTAssertNil(customThenLegacy.customSectionLayout)
    }

    func testSupplementaryLayoutBuilderConfiguresBoundaryAndItemLayoutsConditionally() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            Header(HeaderView.self, id: "header") { _, _ in }
        } supplementaries: {
            SectionSupplementary("dot", HeaderView.self, id: "dot") { _, _ in }
        } supplementaryLayouts: {
            if true {
                BoundarySupplementaryLayout(
                    kind: UICollectionView.elementKindSectionHeader,
                    height: .absolute(36),
                    pinned: true
                )
            }
            if true {
                ItemSupplementaryLayout(
                    kind: "dot",
                    anchor: .topTrailing,
                    width: .absolute(16),
                    height: .absolute(16),
                    fractionalOffset: CGPoint(x: 0.2, y: -0.2)
                )
            }
        }

        let defaultHeaderSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            Header(HeaderView.self, id: "header") { _, _ in }
        } supplementaryLayouts: {
            if false {
                BoundarySupplementaryLayout(
                    kind: UICollectionView.elementKindSectionHeader,
                    height: .absolute(36),
                    pinned: true
                )
            }
        }

        let layouts = section.resolvedSupplementaryLayouts()
        let headerLayout = layouts.first { $0.kind == UICollectionView.elementKindSectionHeader }
        let dotLayout = layouts.first { $0.kind == "dot" }
        let defaultHeaderLayout = defaultHeaderSection.resolvedSupplementaryLayouts().first

        XCTAssertEqual(headerLayout?.height, .absolute(36))
        if case let .boundary(_, _, pinned, _)? = headerLayout?.placement {
            XCTAssertTrue(pinned)
        } else {
            XCTFail("Expected boundary header layout")
        }
        XCTAssertTrue(dotLayout?.placement.isItem == true)
        XCTAssertEqual(defaultHeaderLayout?.height, .estimated(44))
    }

    func testSectionSupplementaryUsesExplicitItemSupplementaryLayoutModifier() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } supplementaries: {
            SectionSupplementary("dot", HeaderView.self, id: "dot") { _, _ in }
                .itemSupplementaryLayout(
                    anchor: .topTrailing,
                    width: .absolute(16),
                    height: .absolute(16),
                    fractionalOffset: CGPoint(x: 0.2, y: -0.2),
                    zIndex: 8
                )
        }

        let layout = section.resolvedSupplementaryLayouts().first { $0.kind == "dot" }

        XCTAssertEqual(layout?.placement, .itemSupplementary(anchor: .topTrailing, fractionalOffset: ListLayoutPoint(x: 0.2, y: -0.2)))
        XCTAssertEqual(layout?.width, .absolute(16))
        XCTAssertEqual(layout?.height, .absolute(16))
        XCTAssertEqual(layout?.zIndex, 8)
    }

    func testSupplementaryDiagnosticsReportOrphanLayoutsAndDuplicateKinds() {
        let orphanBoundary = ListSection(0) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .boundarySupplementaryLayout(kind: "badge", width: .absolute(64), height: .absolute(28))

        let orphanItem = ListSection(1) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .itemSupplementaryLayout(kind: "dot", anchor: .topTrailing, width: .absolute(16), height: .absolute(16))

        let duplicateKind = ListSection(2) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .supplementary("badge", HeaderView.self, id: "first") { _, _ in }
        .supplementary("badge", BadgeView.self, id: "second") { _, _ in }

        let viewOnly = ListSection(3) {
            Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
        }
        .supplementary("plain", HeaderView.self, id: "plain") { _, _ in }

        let issues = ListDiagnostics.validate([orphanBoundary, orphanItem, duplicateKind])

        XCTAssertEqual(issues.filter { $0.kind == .orphanSupplementaryLayout }.count, 2)
        XCTAssertTrue(issues.contains { $0.kind == .duplicateSupplementaryKind })
        XCTAssertTrue(ListDiagnostics.validate([viewOnly]).isEmpty)
    }

    func testHorizontalSectionLayoutStoresConfigurationAndBuildsSection() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.horizontal(
            itemWidth: .estimated(20),
            itemHeight: .absolute(20),
            spacing: 8,
            contentInsets: .init(top: 0, leading: 14, bottom: 0, trailing: 14)
        ))

        guard case let .horizontalConfiguration(horizontal)? = section.sectionLayout else {
            return XCTFail("Expected horizontal layout")
        }
        let layoutSection = section.makeCompositionalLayoutSection()

        XCTAssertEqual(horizontal.itemWidth, .estimated(20))
        XCTAssertEqual(horizontal.itemHeight, .absolute(20))
        XCTAssertEqual(horizontal.spacing, 8)
        XCTAssertTrue(layoutSection.boundarySupplementaryItems.isEmpty)
    }

    func testHorizontalSectionPlacesBoundaryHeaderBeforeItems() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 390, height: 300), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: "3333", cell: NormalUserCell.self) { _, _, _ in }
                Row(2, model: "800003", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.horizontal(
                itemWidth: .estimated(20),
                itemHeight: .absolute(20),
                spacing: 8,
                contentInsets: .init(top: 0, leading: 14, bottom: 0, trailing: 14)
            ))
            .header(HeaderView.self, id: "history") { _, _ in }
            .boundarySupplementaryLayout(
                kind: UICollectionView.elementKindSectionHeader,
                height: .absolute(62)
            )
        }

        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.layoutIfNeeded()

        let headerAttributes = collectionView.layoutAttributesForSupplementaryElement(
            ofKind: UICollectionView.elementKindSectionHeader,
            at: IndexPath(item: 0, section: 0)
        )
        let cellAttributes = collectionView.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))

        XCTAssertNotNil(headerAttributes)
        XCTAssertNotNil(cellAttributes)
        XCTAssertLessThanOrEqual(headerAttributes?.frame.maxY ?? .greatestFiniteMagnitude, cellAttributes?.frame.minY ?? -.greatestFiniteMagnitude)
    }

    func testCustomSectionLayoutStoresTypedBuilder() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.custom(id: "manual") { section, _, _ in
            XCTAssertEqual(section.id, 0)
            return ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        })

        XCTAssertEqual(section.customSectionLayout?.id.typed(String.self), "manual")
        XCTAssertNil(section.sectionLayout)
    }

    func testCompositionalLayoutBuildsBoundaryAndItemSupplementaries() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 2, spacing: 12))
        .header(HeaderView.self, id: "header") { _, _ in }
        .footer(HeaderView.self, id: "footer") { _, _ in }
        .supplementary("badge", HeaderView.self, id: "badge") { _, _ in }
        .boundarySupplementaryLayout(
            kind: "badge",
            alignment: .topTrailing,
            width: .absolute(64),
            height: .absolute(28),
            zIndex: 5
        )
        .supplementary("dot", HeaderView.self, id: "dot") { _, _ in }
        .itemSupplementaryLayout(
            kind: "dot",
            anchor: .topTrailing,
            width: .absolute(16),
            height: .absolute(16),
            fractionalOffset: CGPoint(x: 0.2, y: -0.2)
        )
        .stickyHeader()

        let layouts = section.resolvedSupplementaryLayouts()
        let layoutSection = section.makeCompositionalLayoutSection()
        let boundaryKinds = Set(layoutSection.boundarySupplementaryItems.map(\.elementKind))
        let dotItem = layouts.first { $0.kind == "dot" }?.makeItemSupplementaryItem()

        XCTAssertEqual(boundaryKinds, Set([UICollectionView.elementKindSectionHeader, UICollectionView.elementKindSectionFooter, "badge"]))
        XCTAssertEqual(layoutSection.boundarySupplementaryItems.first { $0.elementKind == UICollectionView.elementKindSectionHeader }?.pinToVisibleBounds, true)
        XCTAssertEqual(layoutSection.boundarySupplementaryItems.first { $0.elementKind == "badge" }?.zIndex, 5)
        XCTAssertEqual(dotItem?.elementKind, "dot")
        XCTAssertTrue(layouts.first { $0.kind == "dot" }?.placement.isItem == true)
    }

    func testSupplementaryBuilderAddsAndRemovesBoundaryItems() {
        let shownSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            Header(HeaderView.self, id: "header") { _, _ in }
        } footer: {
            Footer(HeaderView.self, id: "footer") { _, _ in }
        } supplementaries: {
            SectionSupplementary("badge", HeaderView.self, id: "badge") { _, _ in }
                .layout(
                    alignment: .topTrailing,
                    width: .absolute(64),
                    height: .absolute(28)
                )
        }

        let hiddenSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } header: {
            if false {
                Header(HeaderView.self, id: "header") { _, _ in }
            }
        } footer: {
            if false {
                Footer(HeaderView.self, id: "footer") { _, _ in }
            }
        } supplementaries: {
            if false {
                SectionSupplementary("badge", HeaderView.self, id: "badge") { _, _ in }
                    .layout(
                        alignment: .topTrailing,
                        width: .absolute(64),
                        height: .absolute(28)
                    )
            }
        }

        XCTAssertEqual(Set(shownSection.makeCompositionalLayoutSection().boundarySupplementaryItems.map(\.elementKind)), [
            UICollectionView.elementKindSectionHeader,
            UICollectionView.elementKindSectionFooter,
            "badge"
        ])
        XCTAssertTrue(hiddenSection.makeCompositionalLayoutSection().boundarySupplementaryItems.isEmpty)
    }

    func testBackgroundDecorationBuildsDecorationItemAndCanBeCleared() {
        let decoratedSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .backgroundDecoration(
            HeaderView.self,
            contentInsets: .init(top: 1, leading: 2, bottom: 3, trailing: 4),
            zIndex: -2
        )

        let clearedSection = decoratedSection.backgroundDecoration(nil as HeaderView.Type?)
        let decorationItem = decoratedSection.makeCompositionalLayoutSection().decorationItems.first

        XCTAssertEqual(decorationItem?.elementKind, UICollectionView.elementKindSectionBackgroundDecoration)
        XCTAssertEqual(decorationItem?.contentInsets.top, 1)
        XCTAssertEqual(decorationItem?.contentInsets.leading, 2)
        XCTAssertEqual(decorationItem?.contentInsets.bottom, 3)
        XCTAssertEqual(decorationItem?.contentInsets.trailing, 4)
        XCTAssertEqual(decorationItem?.zIndex, -2)
        XCTAssertTrue(clearedSection.makeCompositionalLayoutSection().decorationItems.isEmpty)
    }

    func testBackgroundDecorationBuilderAddsAndRemovesDecorationItem() {
        let decoratedSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } background: {
            if true {
                BackgroundDecoration(
                    HeaderView.self,
                    contentInsets: .init(top: 4, leading: 5, bottom: 6, trailing: 7),
                    zIndex: -3
                )
            }
        }

        let hiddenSection = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        } background: {
            if false {
                BackgroundDecoration(HeaderView.self)
            }
        }

        let decorationItem = decoratedSection.makeCompositionalLayoutSection().decorationItems.first
        XCTAssertEqual(decorationItem?.elementKind, UICollectionView.elementKindSectionBackgroundDecoration)
        XCTAssertEqual(decorationItem?.contentInsets.top, 4)
        XCTAssertEqual(decorationItem?.contentInsets.leading, 5)
        XCTAssertEqual(decorationItem?.contentInsets.bottom, 6)
        XCTAssertEqual(decorationItem?.contentInsets.trailing, 7)
        XCTAssertEqual(decorationItem?.zIndex, -3)
        XCTAssertTrue(hiddenSection.makeCompositionalLayoutSection().decorationItems.isEmpty)
    }

    func testBackgroundDecorationAppendsToCustomLayoutDecorationItems() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.custom(id: "manual-background") { _, _, _ in
            let section = ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
            section.decorationItems = [.background(elementKind: "manual-background")]
            return section
        })
        .backgroundDecoration(kind: "listkit-background")

        let fallbackSection = ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
        fallbackSection.decorationItems = [.background(elementKind: "manual-background")]
        let layoutSection = section.makeCompositionalLayoutSection(fallback: fallbackSection)

        XCTAssertEqual(layoutSection.decorationItems.map(\.elementKind), ["manual-background", "listkit-background"])
    }

    func testAdapterInvalidatesLayoutWhenSectionLayoutMetadataChangesOnly() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let layout = InvalidationTrackingCompositionalLayout()
        collectionView.collectionViewLayout = layout
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        let initialApply = expectation(description: "initial apply")
        adapter.apply(animatingDifferences: false, completion: {
            initialApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }
        wait(for: [initialApply], timeout: 1)
        let baselineGeneration = adapter.layoutInvalidationGeneration

        let dataOnlyApply = expectation(description: "data only apply")
        adapter.apply(animatingDifferences: false, completion: {
            dataOnlyApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "B", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }
        wait(for: [dataOnlyApply], timeout: 1)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration)

        let layoutApply = expectation(description: "layout apply")
        adapter.apply(animatingDifferences: false, completion: {
            layoutApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "C", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.grid(columns: 2, spacing: 12))
        }
        wait(for: [layoutApply], timeout: 1)
        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration + 1)
    }

    func testAdapterInvalidatesLayoutWhenSupplementaryOrBackgroundMetadataChanges() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let layout = InvalidationTrackingCompositionalLayout()
        collectionView.collectionViewLayout = layout
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        let initialApply = expectation(description: "initial supplementary apply")
        adapter.apply(animatingDifferences: false, completion: {
            initialApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            } header: {
                if false {
                    Header(HeaderView.self, id: "header") { _, _ in }
                }
            }
            .backgroundDecoration(nil as HeaderView.Type?)
        }
        wait(for: [initialApply], timeout: 1)
        let baselineGeneration = adapter.layoutInvalidationGeneration

        let metadataApply = expectation(description: "metadata apply")
        adapter.apply(animatingDifferences: false, completion: {
            metadataApply.fulfill()
        }) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            } header: {
                Header(HeaderView.self, id: "header") { _, _ in }
                    .layout(
                        height: .absolute(36),
                        pinned: true
                    )
            }
            .backgroundDecoration(
                HeaderView.self,
                contentInsets: .init(top: 8, leading: 16, bottom: 8, trailing: 16)
            )
        }
        wait(for: [metadataApply], timeout: 1)

        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration + 1)
    }

    func testAdapterCreatesCompositionalLayoutFromCurrentSections() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }

        let layout = adapter.makeCompositionalLayout()

        XCTAssertEqual(ObjectIdentifier(type(of: layout)), ObjectIdentifier(UICollectionViewCompositionalLayout.self))
        XCTAssertNotNil(adapter.makeCompositionalSection(for: 0))
    }

    func testMakeCompositionalLayoutCanBeCreatedBeforeApplyWithoutDiagnostics() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 120), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
            diagnostics: ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)
        )

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.list(spacing: 8))
        }
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        XCTAssertTrue(adapter.lastLayoutDiagnostics.isEmpty)
    }

    func testMakeCompositionalLayoutReportsUnresolvedLegacyLayoutID() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 120), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        adapter.apply(options: ListApplyOptions(
            animatingDifferences: false,
            diagnostics: .disabled
        )) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout("legacy")
        }

        collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
            diagnostics: ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)
        )
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.kind == .unresolvedLayoutID })

        collectionView.collectionViewLayout = adapter.makeCompositionalLayout(
            fallback: { _, _, _ in nil },
            diagnostics: ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)
        )
        collectionView.layoutIfNeeded()

        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.kind == .unresolvedLayoutID })
    }

    func testMakeCompositionalSectionForOnlySupportsBuiltInSectionLayouts() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let diagnostics = ListDiagnosticsOptions(mode: .warning, logsApplySummary: false)

        adapter.apply(options: ListApplyOptions(animatingDifferences: false, diagnostics: .disabled)) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout("legacy")
        }
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, diagnostics: diagnostics))
        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.kind == .unresolvedLayoutID })

        adapter.apply(options: ListApplyOptions(animatingDifferences: false, diagnostics: .disabled)) {
            ListSection(0) {
                Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
            }
            .layout(.custom(id: "manual") { _, _, _ in
                ListSectionLayout.list().makeCompositionalSection(itemSupplementaries: [])
            })
        }
        XCTAssertNil(adapter.makeCompositionalSection(for: 0, diagnostics: diagnostics))
        XCTAssertTrue(adapter.lastLayoutDiagnostics.contains { $0.message.contains("makeCompositionalLayout(fallback:)") })
    }

    func testAdapterFindsIndexPathsAndScrollsToLastItemByRowID() {
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 200, height: 200), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        adapter.apply(animatingDifferences: false) {
            ListSection(10) {
                Row("first", model: "A", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
                Row("second", model: "B", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            }
            ListSection(20) {
                Row("second", model: "C", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            }
        }

        XCTAssertEqual(adapter.itemCount(in: 10), 2)
        XCTAssertEqual(adapter.itemCount(in: 20), 1)
        XCTAssertEqual(adapter.indexPaths(forRowID: "second", in: 10), [IndexPath(item: 1, section: 0)])
        XCTAssertEqual(adapter.indexPaths(forRowID: "second"), [IndexPath(item: 1, section: 0), IndexPath(item: 0, section: 1)])
        XCTAssertTrue(adapter.scrollToLastItem(in: 10, animated: false))
        XCTAssertFalse(adapter.scrollToLastItem(in: 999, animated: false))
    }

    func testAdapterAppliesPrebuiltListSections() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        let sections = ListSectionsBuilder<Int>.build {
            ListSection(0) {
                Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
            }
        }

        adapter.apply(sections, animatingDifferences: false)

        XCTAssertEqual(adapter.itemCount(in: 0), 1)
    }

    func testAdapterVisibleRefreshAPIsTargetOnlyMatchingVisibleRows() {
        let layout = UICollectionViewFlowLayout()
        layout.itemSize = CGSize(width: 100, height: 44)
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 120, height: 120), collectionViewLayout: layout)
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var displayCount = 0

        adapter.apply(animatingDifferences: false) {
            ListSection(0) {
                Row("first", model: "A", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
                .onDisplay { _, _ in
                    displayCount += 1
                }
                Row("second", model: "B", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            }
        }
        collectionView.reloadData()
        collectionView.layoutIfNeeded()

        let displayCountBeforeRefresh = displayCount
        XCTAssertEqual(adapter.reconfigureVisibleRows(forRowID: "first", in: 0), 1)
        XCTAssertEqual(displayCount, displayCountBeforeRefresh + 1)
        XCTAssertEqual(adapter.reconfigureVisibleRows(forRowID: "missing", in: 0), 0)
        XCTAssertEqual(adapter.reloadVisibleRows(forRowID: "first", in: 0), 1)
        XCTAssertEqual(adapter.reloadVisibleRows(forRowID: "missing", in: 0), 0)
    }

    func testAdapterRefreshesVisibleItemSupplementaryWhenRefreshIDChanges() {
        let kind = "badge"
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var configuredCount = 0
        var badgePrefix = "one"

        func applyBadge(refreshID: Int) -> ListApplyResult<Int> {
            let applyCompleted = expectation(description: "badge apply \(refreshID)")
            let result = adapter.apply(animatingDifferences: false, completion: {
                applyCompleted.fulfill()
            }) {
                ListSection(0) {
                    Row("first", model: "First", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                    Row("second", model: "Second", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                } layout: {
                    GridLayout(columns: 2, itemHeight: .absolute(80))
                } supplementaries: {
                    SectionSupplementary(kind, BadgeView.self, id: "badge") { view, context in
                        configuredCount += 1
                        view.value = "\(badgePrefix)-\(context.indexPath.item)"
                        view.configuredIndexPath = context.indexPath
                    }
                    .refreshID(refreshID)
                    .refreshPolicy(.whenRefreshIDChanges)
                    .itemSupplementaryLayout(
                        anchor: .topTrailing,
                        width: .absolute(20),
                        height: .absolute(20)
                    )
                }
            }
            wait(for: [applyCompleted], timeout: 1)
            return result
        }

        _ = applyBadge(refreshID: 1)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let initialBadgeCount = visibleBadgeViews(in: collectionView, kind: kind).count
        XCTAssertEqual(initialBadgeCount, 2)

        let countBeforeRefresh = configuredCount
        badgePrefix = "two"
        let result = applyBadge(refreshID: 2)
        collectionView.layoutIfNeeded()
        let refreshedBadges = visibleBadgeViews(in: collectionView, kind: kind)

        XCTAssertEqual(result.summary.supplementaryRefreshIDChangedCount, 1)
        XCTAssertEqual(adapter.lastApplySummary.visibleSupplementaryRefreshCount, initialBadgeCount)
        XCTAssertEqual(configuredCount, countBeforeRefresh + initialBadgeCount)
        XCTAssertEqual(Set(refreshedBadges.map(\.value)), ["two-0", "two-1"])
    }

    func testAdapterDoesNotRefreshVisibleSupplementaryWhenPolicyIsNever() {
        let kind = "badge"
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var configuredCount = 0
        var badgePrefix = "one"

        func applyBadge(refreshID: Int) -> ListApplyResult<Int> {
            let applyCompleted = expectation(description: "never badge apply \(refreshID)")
            let result = adapter.apply(animatingDifferences: false, completion: {
                applyCompleted.fulfill()
            }) {
                ListSection(0) {
                    Row("first", model: "First", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                    Row("second", model: "Second", cell: NormalUserCell.self) { cell, model, _ in
                        cell.name = model
                    }
                } layout: {
                    GridLayout(columns: 2, itemHeight: .absolute(80))
                } supplementaries: {
                    SectionSupplementary(kind, BadgeView.self, id: "badge") { view, context in
                        configuredCount += 1
                        view.value = "\(badgePrefix)-\(context.indexPath.item)"
                        view.configuredIndexPath = context.indexPath
                    }
                    .refreshID(refreshID)
                    .refreshPolicy(.never)
                    .itemSupplementaryLayout(
                        anchor: .topTrailing,
                        width: .absolute(20),
                        height: .absolute(20)
                    )
                }
            }
            wait(for: [applyCompleted], timeout: 1)
            return result
        }

        _ = applyBadge(refreshID: 1)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        let initialBadges = visibleBadgeViews(in: collectionView, kind: kind)
        XCTAssertEqual(Set(initialBadges.map(\.value)), ["one-0", "one-1"])

        let countBeforeRefresh = configuredCount
        badgePrefix = "two"
        let result = applyBadge(refreshID: 2)
        collectionView.layoutIfNeeded()
        let badgesAfterApply = visibleBadgeViews(in: collectionView, kind: kind)

        XCTAssertEqual(result.summary.supplementaryRefreshIDChangedCount, 1)
        XCTAssertEqual(adapter.lastApplySummary.visibleSupplementaryRefreshCount, 0)
        XCTAssertEqual(configuredCount, countBeforeRefresh)
        XCTAssertEqual(Set(badgesAfterApply.map(\.value)), ["one-0", "one-1"])
    }

    func testReconfigureVisibleSupplementariesTargetsKindSectionAndRowID() {
        let kind = "badge"
        let collectionView = UICollectionView(frame: CGRect(x: 0, y: 0, width: 240, height: 160), collectionViewLayout: UICollectionViewFlowLayout())
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)
        var badgeValues = [
            "first": "A",
            "second": "B"
        ]

        let applyCompleted = expectation(description: "manual badge apply")
        adapter.apply(animatingDifferences: false, completion: {
            applyCompleted.fulfill()
        }) {
            ListSection(0) {
                Row("first", model: "First", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
                Row("second", model: "Second", cell: NormalUserCell.self) { cell, model, _ in
                    cell.name = model
                }
            } layout: {
                GridLayout(columns: 2, itemHeight: .absolute(80))
            } supplementaries: {
                SectionSupplementary(kind, BadgeView.self, id: "badge") { view, context in
                    let rowID = context.indexPath.item == 0 ? "first" : "second"
                    view.value = badgeValues[rowID]
                    view.configuredIndexPath = context.indexPath
                }
                .refreshPolicy(.never)
                .itemSupplementaryLayout(
                    anchor: .topTrailing,
                    width: .absolute(20),
                    height: .absolute(20)
                )
            }
        }
        wait(for: [applyCompleted], timeout: 1)
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        collectionView.reloadData()
        collectionView.layoutIfNeeded()
        XCTAssertEqual(Set(visibleBadgeViews(in: collectionView, kind: kind).map(\.value)), ["A", "B"])

        badgeValues["first"] = "A2"
        badgeValues["second"] = "B2"
        let refreshedCount = adapter.reconfigureVisibleSupplementaries(ofKind: kind, forRowID: "first", in: 0)
        collectionView.layoutIfNeeded()
        let badgesAfterRefresh = visibleBadgeViews(in: collectionView, kind: kind)

        XCTAssertEqual(refreshedCount, 1)
        XCTAssertEqual(badgesAfterRefresh.first { $0.configuredIndexPath?.item == 0 }?.value, "A2")
        XCTAssertEqual(badgesAfterRefresh.first { $0.configuredIndexPath?.item == 1 }?.value, "B")
        XCTAssertEqual(adapter.reconfigureVisibleSupplementaries(ofKind: "missing", in: 0), 0)
        XCTAssertEqual(adapter.reconfigureVisibleSupplementaries(ofKind: kind, forRowID: "missing", in: 0), 0)
    }

    func testAdapterInvalidatesLayoutWhenItemSupplementaryLayoutChanges() {
        let collectionView = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
        collectionView.collectionViewLayout = InvalidationTrackingCompositionalLayout()
        let adapter = CollectionListAdapter<Int>(collectionView: collectionView)

        func applyBadgeLayout(width: CGFloat) {
            let applyCompleted = expectation(description: "badge layout \(width)")
            adapter.apply(animatingDifferences: false, completion: {
                applyCompleted.fulfill()
            }) {
                ListSection(0) {
                    Row(1, model: "A", cell: NormalUserCell.self) { _, _, _ in }
                } supplementaries: {
                    SectionSupplementary("badge", BadgeView.self, id: "badge") { _, _ in }
                        .itemSupplementaryLayout(
                            anchor: .topTrailing,
                            width: .absolute(width),
                            height: .absolute(20)
                        )
                }
            }
            wait(for: [applyCompleted], timeout: 1)
        }

        applyBadgeLayout(width: 20)
        let baselineGeneration = adapter.layoutInvalidationGeneration

        applyBadgeLayout(width: 24)

        XCTAssertEqual(adapter.layoutInvalidationGeneration, baselineGeneration + 1)
    }

    func testLayoutDiagnosticsReportsInvalidColumnsDimensionsSpacingAndPlacementConflict() {
        let section = ListSection(0) {
            Row(1, model: User(id: 1, name: "A", isVIP: false, version: 1), cell: NormalUserCell.self) { _, _, _ in }
        }
        .layout(.grid(columns: 0, spacing: -12, itemHeight: .absolute(0)))
        .supplementary("badge", HeaderView.self, id: "badge") { _, _ in }
        .boundarySupplementaryLayout(kind: "badge", width: .absolute(64), height: .absolute(28))
        .itemSupplementaryLayout(kind: "badge", anchor: .topTrailing, width: .absolute(0), height: .fractionalHeight(-0.5))

        let issues = ListDiagnostics.validate([section])

        XCTAssertTrue(issues.contains { $0.kind == .invalidLayout })
        XCTAssertTrue(issues.contains { $0.kind == .conflictingSupplementaryLayout })
    }

    func testApplyPlannerBuildsSharedSummaryAndRefreshPlan() {
        let keptOld = makeTestListNode("kept", refreshID: 1)
        let deletedOld = makeTestListNode("deleted", refreshID: 1)
        let keptNew = makeTestListNode("kept", refreshID: 2, policy: .whenRefreshIDChanges)
        let insertedNew = makeTestListNode("inserted", refreshID: 1)
        let headerOld = makeTestListNode("header", refreshID: 1, role: .supplementary)
        let headerNew = makeTestListNode("header", refreshID: 2, policy: .whenRefreshIDChanges, role: .supplementary)

        let plan = ListApplyPlanner.makePlan(
            old: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [keptOld, deletedOld], supplementaries: [headerOld])
            ],
            new: [
                ListSectionSnapshot(sectionID: AnyListID(0), rows: [keptNew, insertedNew], supplementaries: [headerNew])
            ],
            options: ListApplyOptions(
                animatingDifferences: false,
                refreshStrategy: .automatic,
                diagnostics: .disabled
            ),
            diagnosticsIssues: []
        )

        XCTAssertTrue(plan.shouldApplyDiffable)
        XCTAssertEqual(plan.snapshotRefreshItems, [keptNew.identity])
        XCTAssertTrue(plan.shouldRunVisibleRefresh)
        XCTAssertEqual(plan.initialSummary.insertedCount, 1)
        XCTAssertEqual(plan.initialSummary.deletedCount, 1)
        XCTAssertEqual(plan.initialSummary.keptCount, 1)
        XCTAssertEqual(plan.initialSummary.refreshIDChangedCount, 1)
        XCTAssertEqual(plan.initialSummary.snapshotRefreshCount, 1)
        XCTAssertEqual(plan.initialSummary.supplementaryRefreshIDChangedCount, 1)
        XCTAssertEqual(
            plan.completedSummary(visibleRefreshCount: 3, visibleSupplementaryRefreshCount: 2).visibleSupplementaryRefreshCount,
            2
        )
    }

    func testApplyPlannerForceReloadOnlyTargetsKeptRows() {
        let oldRows = [
            makeTestListNode("kept", refreshID: 1),
            makeTestListNode("deleted", refreshID: 1)
        ]
        let newRows = [
            makeTestListNode("kept", refreshID: 1),
            makeTestListNode("inserted", refreshID: 1)
        ]

        let plan = ListApplyPlanner.makePlan(
            old: [ListSectionSnapshot(sectionID: AnyListID(0), rows: oldRows, supplementaries: [])],
            new: [ListSectionSnapshot(sectionID: AnyListID(0), rows: newRows, supplementaries: [])],
            options: ListApplyOptions(
                animatingDifferences: false,
                refreshStrategy: .forceReload,
                diagnostics: .disabled
            ),
            diagnosticsIssues: []
        )

        XCTAssertEqual(plan.snapshotRefreshItems, [newRows[0].identity])
        XCTAssertFalse(plan.shouldRunVisibleRefresh)
        XCTAssertEqual(plan.initialSummary.snapshotRefreshCount, 1)
    }

    func testApplyPlannerStopsBeforeDiffableForDiagnosticsWarning() {
        let oldRows = [makeTestListNode("kept", refreshID: 1)]
        let newRows = [makeTestListNode("kept", refreshID: 2, policy: .whenRefreshIDChanges)]
        let issue = ListDiagnosticsIssue(
            kind: .duplicateRow,
            message: "ListKit: duplicate row identity"
        )

        let plan = ListApplyPlanner.makePlan(
            old: [ListSectionSnapshot(sectionID: AnyListID(0), rows: oldRows, supplementaries: [])],
            new: [ListSectionSnapshot(sectionID: AnyListID(0), rows: newRows, supplementaries: [])],
            options: ListApplyOptions(
                animatingDifferences: false,
                refreshStrategy: .automatic,
                diagnostics: .init(mode: .warning, logsApplySummary: false)
            ),
            diagnosticsIssues: [issue]
        )

        XCTAssertFalse(plan.shouldApplyDiffable)
        XCTAssertTrue(plan.snapshotRefreshItems.isEmpty)
        XCTAssertEqual(plan.initialSummary.snapshotRefreshCount, 0)
        XCTAssertEqual(plan.initialSummary.visibleRefreshCount, 0)
        XCTAssertEqual(plan.initialSummary.diagnosticsIssues, [issue])
    }

    func testEventRouterDispatchesTypedEventsOnly() {
        let router = ListEventRouter<Int>()
        var receivedEvent: UserEvent?
        var receivedContext: Int?

        router.on(UserEvent.self) { event, context in
            receivedEvent = event
            receivedContext = context
        }

        router.dispatch(IgnoredEvent(), context: 7)
        XCTAssertNil(receivedEvent)

        router.dispatch(UserEvent.headerTap, context: 9)
        XCTAssertEqual(receivedEvent, .headerTap)
        XCTAssertEqual(receivedContext, 9)
    }
}

private struct User: Hashable, Sendable {
    let id: Int
    let name: String
    let isVIP: Bool
    let version: Int
}

private struct UserProfile: Hashable, Sendable {
    let userID: String
    let accountID: String
    let name: String
}

private struct IdentifiedUser: Identifiable, Hashable, Sendable {
    let id: Int
    let name: String
}

private enum UserEvent: ListEvent, Equatable {
    case avatarTap(userID: Int)
    case buttonTap(userID: Int)
    case headerTap
}

private struct IgnoredEvent: ListEvent {}

private final class NormalUserCell: UICollectionViewCell {
    var name: String?
}

private final class VIPUserCell: UICollectionViewCell {
    var name: String?
}

private final class HeaderView: UICollectionReusableView {
    var title: String?
}

private final class BadgeView: UICollectionReusableView {
    var value: String?
    var configuredIndexPath: IndexPath?
}

private final class EventCell: UICollectionViewCell {
    var onButtonTap: (@MainActor () -> Void)?
}

private final class EmptyStateCell: UICollectionViewCell {
    var message: String?
}

private final class LoadingStateCell: UICollectionViewCell {
    var message: String?
}

private final class FailureStateCell: UICollectionViewCell {
    var message: String?
}

private final class ScrollDelegateSpy: NSObject, UIScrollViewDelegate {
    var didScrollCount = 0

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        didScrollCount += 1
    }
}

private final class FlowLayoutDelegateSpy: NSObject, UICollectionViewDelegateFlowLayout {
    var sizeRequestCount = 0

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        sizeRequestCount += 1
        return CGSize(width: 44, height: 55)
    }
}

private final class CollectionDisplayDelegateSpy: NSObject, UICollectionViewDelegate {
    var didEndDisplayingCount = 0

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        didEndDisplayingCount += 1
    }
}

@MainActor
private func visibleBadgeViews(in collectionView: UICollectionView, kind: String) -> [BadgeView] {
    collectionView.layoutIfNeeded()
    return collectionView.visibleSupplementaryViews(ofKind: kind).compactMap { $0 as? BadgeView }
}

private final class InvalidationTrackingCompositionalLayout: UICollectionViewCompositionalLayout {
    var invalidateCount = 0

    init() {
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1),
            heightDimension: .estimated(44)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: itemSize, subitem: item, count: 1)
        super.init(section: NSCollectionLayoutSection(group: group))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func invalidateLayout() {
        invalidateCount += 1
        super.invalidateLayout()
    }
}

private func makeTestListNode(
    _ id: String,
    refreshID: Int?,
    policy: RowRefreshPolicy = .automaticVisible,
    role: ListNodeRole = .row
) -> ListNodeSnapshot {
    ListNodeSnapshot(
        identity: AnyListIdentity(
            sectionID: AnyListID(0),
            rowID: AnyListID(id),
            presentationID: role == .row ? ObjectIdentifier(NormalUserCell.self) : ObjectIdentifier(HeaderView.self),
            variant: role == .row ? nil : AnyListID("supplementary")
        ),
        refreshID: refreshID.map(AnyListID.init),
        refreshPolicy: policy,
        role: role
    )
}
