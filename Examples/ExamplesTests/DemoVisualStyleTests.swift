import Testing
import UIKit
@testable import Examples

@MainActor
struct DemoVisualStyleTests {
    @Test func tabBarUsesNativeSystemAppearance() {
        let viewController = LiveRoomDemoViewController()

        viewController.loadViewIfNeeded()

        #expect(viewController.tabBar.accessibilityIdentifier == "design-scheme-tabs")
        #expect(viewController.tabBar.subviews.contains { $0.accessibilityIdentifier == "design-scheme-tabs-glass" } == false)
    }

    @Test func actionButtonsUseGlassConfigurationOnIOS26() {
        let button = UIButton(type: .system)

        button.applyDemoActionButtonStyle(symbolName: "paperplane.fill")
        button.setDemoActionButtonTitle("Send")

        if #available(iOS 26.0, *) {
            #expect(button.configuration != nil)
            #expect(button.backgroundColor == nil)
            #expect(button.configuration?.title == "Send")
        } else {
            #expect(button.configuration == nil)
            #expect(button.backgroundColor == UIColor.systemBlue)
            #expect(button.title(for: .normal) == " Send")
        }
    }

    @Test func liveConsoleToolbarFitsPhoneWidth() {
        let cell = LiveConsoleToolbarCell(frame: CGRect(x: 0, y: 0, width: 390, height: 76))

        cell.configure(
            LiveRoomToolbarViewModel(
                messageButtonTitle: "Add Message",
                giftButtonTitle: "Send Gift",
                selectedGiftName: "Rocket"
            )
        )
        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        cell.contentView.layoutIfNeeded()

        let bounds = cell.contentView.bounds
        let descendantBounds = descendantUnionBounds(in: cell.contentView)

        #expect(descendantBounds.minX >= bounds.minX - 0.5)
        #expect(descendantBounds.maxX <= bounds.maxX + 0.5)
    }

    @Test func roomToolkitRootViewIsCollectionView() {
        let viewController = LiveRoomDemoViewController()

        viewController.loadViewIfNeeded()
        let roomToolkitController = viewController.viewControllers?[2]
        roomToolkitController?.loadViewIfNeeded()

        #expect(roomToolkitController?.view is UICollectionView)
        #expect(roomToolkitController?.view.accessibilityIdentifier == "room-toolkit-screen")
    }

    @Test func liveMessageCellsLeaveSectionBackgroundVisible() {
        let cell = LiveMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 106))

        #expect(cell.backgroundColor == .clear)
        #expect(cell.contentView.backgroundColor == .clear)
    }

    @Test func giftMessageCellFitsPhoneWidthWithoutFixedBadgeColumn() {
        let cell = LiveMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 106))
        cell.configure(
            LiveMessage(
                id: "gift-layout",
                sender: "System",
                text: "Rocket sent to Alex.",
                tone: "gift",
                version: 0
            )
        )

        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        cell.contentView.layoutIfNeeded()

        let bounds = cell.contentView.bounds
        let descendantBounds = descendantUnionBounds(in: cell.contentView)
        #expect(descendantBounds.minX >= bounds.minX - 0.5)
        #expect(descendantBounds.maxX <= bounds.maxX + 0.5)
    }

    @Test func sectionHeadersUseCardContentInsets() {
        let header = SectionHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 36))

        header.configure(title: "Live activity", detail: "4 messages")
        header.setNeedsLayout()
        header.layoutIfNeeded()

        let descendantBounds = descendantUnionBounds(in: header)

        #expect(descendantBounds.minX >= 32)
        #expect(descendantBounds.maxX <= header.bounds.maxX - 32)
    }

    @Test func capsuleLabelsUseHalfHeightCornerRadius() {
        let label = CapsuleLabel(frame: CGRect(x: 0, y: 0, width: 74, height: 24))

        label.layoutIfNeeded()

        #expect(label.layer.cornerRadius == 12)
    }
}

@MainActor
private func descendantUnionBounds(in rootView: UIView) -> CGRect {
    var result = CGRect.null

    func visit(_ view: UIView) {
        for subview in view.subviews where subview.isHidden == false {
            result = result.union(subview.convert(subview.bounds, to: rootView))
            visit(subview)
        }
    }

    visit(rootView)
    return result
}
