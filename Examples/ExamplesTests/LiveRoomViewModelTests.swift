import Testing
import UIKit
import ListKit
@testable import Examples

@MainActor
struct LiveRoomViewModelTests {
    @Test func builderOutputsContainExpectedCollectionAndTableSections() {
        let viewModel = LiveRoomViewModel()

        #expect(viewModel.collectionSections.map(\.id) == [.status, .micSeats, .messages, .gifts, .diagnostics])
        #expect(viewModel.tableSections.map(\.id) == [.moderation])
        #expect(viewModel.liveActivitySections.map(\.id) == [.roomActivity])
        #expect(viewModel.roomToolkitSections.map(\.id) == [.roomHero, .roomMetrics, .apiGuide, .roomActivityTitle, .roomActivity])
        #expect(viewModel.peopleSections.map(\.id) == [.micSeats])
        #expect(viewModel.toolkitSections.map(\.id) == [.status, .gifts, .diagnostics])
        #expect(viewModel.studioControlSections.map(\.id) == [.studioHeader, .studioControls, .messages])
        #expect(viewModel.messageCount == 4)
        #expect(viewModel.pendingModerationCount == 7)
    }

    @Test func sendingMessageAppendsMessageAndRequestsScroll() {
        let viewModel = LiveRoomViewModel()
        let initialCount = viewModel.messageCount

        viewModel.sendMessage()

        #expect(viewModel.messageCount == initialCount + 1)
        #expect(viewModel.pendingScrollMessageID == viewModel.latestMessageID)
        #expect(viewModel.collectionSections.first { $0.id == .messages }?.rows.count == initialCount + 1)
    }

    @Test func selectingGiftOnlyChangesGiftSectionRefreshIDs() {
        let viewModel = LiveRoomViewModel()
        let before = viewModel.collectionSections.first { $0.id == .gifts }?.rows.map(\.refreshID)

        viewModel.selectGift("rocket")

        let after = viewModel.collectionSections.first { $0.id == .gifts }?.rows.map(\.refreshID)
        #expect(before != after)
        #expect(viewModel.selectedGiftID == "rocket")
        #expect(viewModel.collectionSections.first { $0.id == .messages }?.rows.count == 4)
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
        #expect(section?.rows.dropFirst().allSatisfy { $0.isFocusable == true } == true)
        #expect(section?.indexTitle == "API")
        #expect(section?.sectionLayout == .uiKitListConfiguration(.init(appearance: .insetGrouped, headerTopPadding: 0)))
    }

    @Test func micSeatsUseCenteredPagingForFocusedInteraction() {
        let viewModel = LiveRoomViewModel()
        let section = viewModel.collectionSections.first { $0.id == .micSeats }

        guard case .horizontalConfiguration(let layout) = section?.sectionLayout else {
            Issue.record("Expected horizontal mic-seat layout")
            return
        }
        #expect(layout.scrollingBehavior == .groupPagingCentered)
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

    @Test func sectionBackgroundsUseSameHorizontalInsetsAsContent() {
        let viewModel = LiveRoomViewModel()
        let sections = viewModel.liveConsoleSections + viewModel.studioControlSections + viewModel.toolkitSections + viewModel.roomToolkitSections

        for section in sections {
            guard let backgroundInsets = section.backgroundDecorationItem?.contentInsets,
                  let contentInsets = section.sectionLayout?.contentInsets else {
                continue
            }

            #expect(backgroundInsets.leading == contentInsets.leading)
            #expect(backgroundInsets.trailing == contentInsets.trailing)
        }
    }

    @Test func statusSectionDoesNotUseNestedBackgroundDecoration() {
        let viewModel = LiveRoomViewModel()
        let statusSection = viewModel.collectionSections.first { $0.id == .status }

        #expect(statusSection?.backgroundDecorationItem == nil)
    }

    @Test func contentSectionHeadersDoNotPinOverRows() {
        let viewModel = LiveRoomViewModel()
        let sections = viewModel.collectionSections.filter { [.micSeats, .messages, .gifts].contains($0.id) }

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
