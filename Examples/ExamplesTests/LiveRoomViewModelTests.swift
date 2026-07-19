import Testing
import UIKit
@testable import ListKit
@testable import Examples

@MainActor
struct LiveRoomViewModelTests {
    @Test func builderOutputsContainExpectedCollectionAndTableSections() {
        let viewModel = LiveRoomViewModel()

        #expect(viewModel.liveConsoleSections.map(\.id) == [.consoleHeader, .consoleToolbar, .status, .micSeats, .messages, .gifts, .diagnostics])
        #expect(viewModel.tableSections.map(\.id) == [.moderation])
        #expect(viewModel.roomToolkitSections.map(\.id) == [.roomHero, .roomMetrics, .apiGuide, .roomActivityTitle, .roomActivity])
        #expect(viewModel.studioControlSections.map(\.id) == [.studioHeader, .studioControls, .messages])
        #expect(viewModel.messageCount == 4)
        #expect(viewModel.pendingModerationCount == 7)
    }

    @Test func singleAdminSectionDoesNotExposeIndexBar() {
        let viewModel = LiveRoomViewModel()

        #expect(viewModel.tableSections.compactMap(\.indexTitle).isEmpty)
    }

    @Test func designScreensInstallNativeListViewsAsRootViews() {
        let liveConsole = LiveConsoleDesignViewController()
        let studioControl = StudioControlDesignViewController()
        let roomToolkit = RoomToolkitDesignViewController()
        let adminTable = AdminTableDemoViewController()

        #expect(liveConsole.view is UICollectionView)
        #expect(studioControl.view is UICollectionView)
        #expect(roomToolkit.view is UICollectionView)
        #expect(adminTable.view is UITableView)
        #expect((adminTable.view as? UITableView)?.tableHeaderView != nil)
    }

    @Test func sendingMessageAppendsMessageAndRequestsScroll() {
        let viewModel = LiveRoomViewModel()
        let initialCount = viewModel.messageCount

        viewModel.sendMessage()

        #expect(viewModel.messageCount == initialCount + 1)
        #expect(viewModel.pendingScrollMessageID == viewModel.latestMessageID)
        #expect(viewModel.liveConsoleSections.first { $0.id == .messages }?.rows.count == initialCount + 1)
    }

    @Test func headerMenuActionsUpdateRoomStateAndResetDemo() {
        let viewModel = LiveRoomViewModel()
        let initialViewerCount = viewModel.viewerCount
        let initialHeat = viewModel.heat

        viewModel.performMenuAction(.refreshStatus)
        #expect(viewModel.viewerCount == initialViewerCount + 5)
        #expect(viewModel.heat == initialHeat + 128)
        #expect(viewModel.pendingScrollMessageID == nil)

        viewModel.performMenuAction(.addSystemEvent)
        #expect(viewModel.messageCount == 5)
        #expect(viewModel.pendingScrollMessageID == viewModel.latestMessageID)
        viewModel.setRoomActivityFilter(.system)
        #expect(viewModel.roomToolkitSections.first { $0.id == .roomActivity }?.rows.count == 1)

        viewModel.performMenuAction(.selectStudioMode(2))
        #expect(viewModel.selectedStudioMode == 2)

        viewModel.performMenuAction(.resetDemo)
        #expect(viewModel.viewerCount == initialViewerCount)
        #expect(viewModel.heat == initialHeat)
        #expect(viewModel.messageCount == 4)
        #expect(viewModel.activityFilter == .all)
        #expect(viewModel.selectedStudioMode == 0)
        #expect(viewModel.pendingScrollMessageID == nil)
    }

    @Test func selectingGiftOnlyChangesGiftSectionRefreshIDs() {
        let viewModel = LiveRoomViewModel()
        let before = viewModel.liveConsoleSections.first { $0.id == .gifts }?.rows.map(\.refreshID)

        viewModel.selectGift("rocket")

        let after = viewModel.liveConsoleSections.first { $0.id == .gifts }?.rows.map(\.refreshID)
        #expect(before != after)
        #expect(viewModel.selectedGiftID == "rocket")
        #expect(viewModel.liveConsoleSections.first { $0.id == .messages }?.rows.count == 4)
    }

    @Test func handlingModerationEventRemovesItFromTableOutput() {
        let viewModel = LiveRoomViewModel()
        let firstEventID = viewModel.visibleModerationEventIDs[0]

        viewModel.handleModeration(firstEventID)

        #expect(viewModel.visibleModerationEventIDs.contains(firstEventID) == false)
        #expect(viewModel.pendingModerationCount == 6)
        #expect(viewModel.tableSections.first { $0.id == .moderation }?.rows.count == 6)
    }

    @Test func roomToolkitUsesNativeExpandableAPIGuide() {
        let viewModel = LiveRoomViewModel()
        let section = viewModel.roomToolkitSections.first { $0.id == .apiGuide }

        #expect(section?.hasOutlineHierarchy == true)
        #expect(section?.rows.count == 4)
        #expect(section?.outlineRoots.first?.isExpanded == true)
        #expect(section?.rows.first?.showsOutlineDisclosure == true)
        #expect(section?.rows.first?.selectHandler == nil)
        #expect(section?.rows.dropFirst().allSatisfy { $0.isFocusable == true } == true)
        #expect(section?.indexTitle == "API")
        #expect(section?.sectionLayout == .uiKitListConfiguration(.init(appearance: .insetGrouped, headerTopPadding: 0)))
    }

    @Test func apiGuideSelectionDoesNotActivateOrScroll() {
        let viewModel = LiveRoomViewModel()
        let section = viewModel.roomToolkitSections.first { $0.id == .apiGuide }
        let capabilityIDs: Set<LiveRoomRowID> = [.apiAsyncApply, .apiStableIdentity, .apiNativeInteractions]
        let capabilityRows = section?.rows.filter {
            guard let rowID = $0.identity.rowID.typed(LiveRoomRowID.self) else { return false }
            return capabilityIDs.contains(rowID)
        } ?? []

        #expect(capabilityRows.count == 3)
        #expect(capabilityRows.allSatisfy { $0.selectHandler == nil })
        #expect(capabilityRows.allSatisfy { $0.primaryActionHandler == nil })
        #expect(capabilityRows.allSatisfy { $0.contextMenuProvider != nil })
        #expect(capabilityRows.allSatisfy { $0.trailingSwipeActionsProvider != nil })
    }

    @Test func apiGuideExpansionStateHidesAndRestoresAllChildren() {
        let viewModel = LiveRoomViewModel()

        #expect(viewModel.isAPIGuideExpanded == true)
        #expect(viewModel.roomToolkitSections.first { $0.id == .apiGuide }?.outlineRoots.first?.isExpanded == true)

        viewModel.setAPIGuideExpanded(false)

        #expect(viewModel.isAPIGuideExpanded == false)
        #expect(viewModel.roomToolkitSections.first { $0.id == .apiGuide }?.outlineRoots.first?.isExpanded == false)

        viewModel.setAPIGuideExpanded(true)

        #expect(viewModel.isAPIGuideExpanded == true)
        #expect(viewModel.roomToolkitSections.first { $0.id == .apiGuide }?.outlineRoots.first?.isExpanded == true)
    }

    @Test func roomActivityFilterUpdatesOnlyMatchingRowsWithoutRequestingScroll() {
        let viewModel = LiveRoomViewModel()
        let initialTitleRefreshID = viewModel.roomToolkitSections
            .first { $0.id == .roomActivityTitle }?
            .rows.first?.refreshID

        #expect(viewModel.activityFilter == .all)
        #expect(viewModel.roomToolkitSections.first { $0.id == .roomActivity }?.rows.count == 4)

        viewModel.setRoomActivityFilter(.messages)
        #expect(viewModel.activityFilter == .messages)
        #expect(viewModel.roomToolkitSections.first { $0.id == .roomActivity }?.rows.count == 3)
        #expect(viewModel.pendingScrollMessageID == nil)
        #expect(
            viewModel.roomToolkitSections.first { $0.id == .roomActivityTitle }?.rows.first?.refreshID
                == initialTitleRefreshID
        )

        viewModel.setRoomActivityFilter(.gifts)
        #expect(viewModel.roomToolkitSections.first { $0.id == .roomActivity }?.rows.count == 1)

        viewModel.setRoomActivityFilter(.system)
        #expect(viewModel.roomToolkitSections.first { $0.id == .roomActivity }?.rows.isEmpty == true)

        viewModel.setRoomActivityFilter(.all)
        #expect(viewModel.roomToolkitSections.first { $0.id == .roomActivity }?.rows.count == 4)
    }

    @Test func micSeatsStartAtTheSectionLeadingBoundary() {
        let viewModel = LiveRoomViewModel()
        let section = viewModel.liveConsoleSections.first { $0.id == .micSeats }

        guard case .horizontalConfiguration(let layout) = section?.sectionLayout else {
            Issue.record("Expected horizontal mic-seat layout")
            return
        }
        #expect(layout.scrollingBehavior == .continuousGroupLeadingBoundary)
        #expect(section?.rows.allSatisfy { $0.isFocusable == true } == true)
    }

    @Test func moderationMovePersistsBusinessOrder() {
        let viewModel = LiveRoomViewModel()
        let firstID = viewModel.visibleModerationEventIDs[0]

        viewModel.moveModeration(
            from: IndexPath(row: 0, section: 0),
            to: IndexPath(row: 2, section: 0)
        )

        #expect(viewModel.visibleModerationEventIDs[2] == firstID)
    }

    @Test func capabilityActivationUsesStableMessageIdentity() {
        let viewModel = LiveRoomViewModel()

        viewModel.activateCapability("Async snapshot apply")

        #expect(viewModel.pendingScrollMessageID == viewModel.latestMessageID)
        #expect(viewModel.messageCount == 5)
    }

    @Test func sectionContentKeepsDefaultPaddingInsideBackground() {
        let viewModel = LiveRoomViewModel()
        let sections = viewModel.liveConsoleSections + viewModel.studioControlSections + viewModel.roomToolkitSections

        for section in sections {
            guard let backgroundInsets = section.backgroundDecorationItem?.contentInsets,
                  let contentInsets = section.sectionLayout?.contentInsets else {
                continue
            }

            #expect(contentInsets.leading - backgroundInsets.leading == 8)
            #expect(contentInsets.trailing - backgroundInsets.trailing == 8)
        }
    }

    @Test func statusSectionDoesNotUseNestedBackgroundDecoration() {
        let viewModel = LiveRoomViewModel()
        let statusSection = viewModel.liveConsoleSections.first { $0.id == .status }

        #expect(statusSection?.backgroundDecorationItem == nil)
    }

    @Test func contentSectionHeadersDoNotPinOverRows() {
        let viewModel = LiveRoomViewModel()
        let sections = viewModel.liveConsoleSections.filter { [.micSeats, .messages, .gifts].contains($0.id) }

        for section in sections {
            let headerLayout = section.supplementaryLayouts[UICollectionView.elementKindSectionHeader]

            #expect(headerLayout?.pinsToVisibleBounds == false)
        }
    }

}

private extension ListSectionLayout {
    var contentInsets: ListLayoutInsets {
        switch self {
        case .listConfiguration(let configuration):
            return configuration.contentInsets
        case .gridConfiguration(let configuration):
            return configuration.contentInsets
        case .horizontalConfiguration(let configuration):
            return configuration.contentInsets
        case .uiKitListConfiguration:
            return .zero
        }
    }
}

private extension ListSupplementaryLayout {
    var pinsToVisibleBounds: Bool {
        guard case .boundary(_, _, let pinToVisibleBounds, _) = placement else {
            return false
        }
        return pinToVisibleBounds
    }
}
