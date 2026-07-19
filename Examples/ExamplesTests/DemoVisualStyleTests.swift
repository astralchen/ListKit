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
        #expect(truncatedLabels(in: cell.contentView).isEmpty)
    }

    @Test func headerMoreButtonsExposeConfiguredMenus() {
        let live = LiveConsoleDesignViewController()
        let studio = StudioControlDesignViewController()
        let room = RoomToolkitDesignViewController()
        [live, studio, room].forEach { $0.loadViewIfNeeded() }

        let liveMenu = live.navigationItem.rightBarButtonItem?.menu
        let studioMenu = studio.navigationItem.rightBarButtonItem?.menu
        let roomMenu = room.navigationItem.rightBarButtonItem?.menu

        #expect(menuActionTitles(in: liveMenu) == [
            "Add Message", "Send Selected Gift", "Refresh Status", "Reset Demo"
        ])
        #expect(menuActionTitles(in: studioMenu) == [
            "Room Mode", "Gift Mode", "Log Mode", "Refresh Status", "Reset Demo"
        ])
        #expect(menuActionTitles(in: roomMenu) == [
            "Refresh Status", "Add System Event", "Reset Demo"
        ])
        #expect(menuActions(in: studioMenu).first?.state == .on)
    }

    @Test func tabsOwnNavigationControllersWithNativeLargeTitles() throws {
        let tabs = LiveRoomDemoViewController()
        tabs.loadViewIfNeeded()

        let navigationControllers = try #require(tabs.viewControllers as? [UINavigationController])
        #expect(navigationControllers.count == 4)
        #expect(navigationControllers.allSatisfy { $0.navigationBar.prefersLargeTitles })

        let live = try #require(navigationControllers.first?.topViewController)
        live.loadViewIfNeeded()
        #expect(live is LiveConsoleDesignViewController)
        #expect(live.navigationItem.title == "Live Console")
        #expect(live.navigationItem.largeTitleDisplayMode == .always)
        #expect(live.navigationItem.rightBarButtonItem?.accessibilityIdentifier == "live-console-header-menu")
        if #available(iOS 26.0, *) {
            #expect(live.navigationItem.subtitle == "LIVE")
            #expect(live.navigationItem.largeSubtitle?.contains("mic seats") == true)
        }
    }

    @Test func liveRoomStatusMetricsFitPhoneWidth() {
        let cell = LiveRoomStatusCell(frame: CGRect(x: 0, y: 0, width: 390, height: 150))
        cell.configure(
            RoomStatusViewModel(
                roomName: "Room Toolkit",
                hostName: "Alex",
                mode: "LIVE",
                viewerCount: 1_255,
                heat: 9_148,
                pendingModerationCount: 7,
                refreshVersion: 0
            )
        )

        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        cell.contentView.layoutIfNeeded()

        #expect(truncatedLabels(in: cell.contentView).isEmpty)
    }

    @Test func roomToolkitRootViewIsCollectionView() throws {
        let viewController = LiveRoomDemoViewController()

        viewController.loadViewIfNeeded()
        let navigationController = try #require(
            viewController.viewControllers?[2] as? UINavigationController
        )
        let roomToolkitController = try #require(navigationController.topViewController)
        roomToolkitController.loadViewIfNeeded()

        #expect(roomToolkitController.view is UICollectionView)
        #expect(roomToolkitController.view.accessibilityIdentifier == "room-toolkit-screen")
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

    @Test func giftMessageUsesAlignedMetadataAndCompactAccessory() throws {
        let cell = LiveMessageCell(frame: CGRect(x: 0, y: 0, width: 390, height: 140))
        cell.configure(
            LiveMessage(
                id: "gift-layout",
                sender: "Sophie",
                text: "Sent a Rocket",
                tone: "gift",
                version: 0
            )
        )

        cell.setNeedsLayout()
        cell.layoutIfNeeded()
        cell.contentView.layoutIfNeeded()

        let labels = descendants(of: UILabel.self, in: cell.contentView)
        let senderLabel = try #require(labels.first { $0.text == "Sophie" })
        let timeLabel = try #require(labels.first { $0.text == "2m ago" })
        let countLabel = try #require(labels.first { $0.text == "x 10" })
        let badgeLabel = try #require(labels.first { $0.text == "Top Gifter" })
        let giftImage = try #require(
            descendants(of: UIImageView.self, in: cell.contentView)
                .first { $0.accessibilityIdentifier == "live-message-gift-image" }
        )
        let senderFrame = senderLabel.convert(senderLabel.bounds, to: cell.contentView)
        let timeFrame = timeLabel.convert(timeLabel.bounds, to: cell.contentView)
        let countFrame = countLabel.convert(countLabel.bounds, to: cell.contentView)
        let giftFrame = giftImage.convert(giftImage.bounds, to: cell.contentView)

        #expect(abs(senderFrame.maxY - timeFrame.maxY) < 3)
        #expect(abs(senderFrame.maxY - countFrame.maxY) < 3)
        #expect(giftFrame.minY > senderFrame.minY)
        #expect(giftFrame.width <= 64.5)
        #expect(badgeLabel.bounds.width < 110)
        #expect(truncatedLabels(in: cell.contentView).isEmpty)
    }

    @Test func sectionHeaderTextUsesCompactInnerInsets() {
        let header = SectionHeaderView(frame: CGRect(x: 0, y: 0, width: 390, height: 36))

        header.configure(title: "Live activity", detail: "4 messages")
        header.setNeedsLayout()
        header.layoutIfNeeded()

        let descendantBounds = descendantUnionBounds(in: header)

        #expect(abs(descendantBounds.minX - 8) < 0.5)
        #expect(descendantBounds.maxX <= header.bounds.maxX - 8)
    }

    @Test func roomMetricsAlignIconsAndTitlesBelowThem() {
        let strip = RoomMetricStripView(frame: CGRect(x: 0, y: 0, width: 390, height: 112))

        strip.setNeedsLayout()
        strip.layoutIfNeeded()

        let icons = descendants(of: UIImageView.self, in: strip)
        let iconContainers = descendants(of: UIView.self, in: strip).filter {
            $0.accessibilityIdentifier == "room-metric-icon-container"
        }
        let titleValues = Set(["LIVE", "1248", "8932", "Host", "7"])
        let titles = descendants(of: UILabel.self, in: strip).filter {
            titleValues.contains($0.text?.trimmingCharacters(in: .whitespaces) ?? "")
        }
        let iconFrames = iconContainers.map { $0.convert($0.bounds, to: strip) }
        let titleFrames = titles.map { $0.convert($0.bounds, to: strip) }

        #expect(icons.count == 5)
        #expect(iconContainers.count == 5)
        #expect(titleFrames.count == 5)
        #expect(verticalSpread(of: iconFrames) < 0.5)
        #expect(verticalSpread(of: titleFrames) < 0.5)
        #expect((iconFrames.map(\.maxY).max() ?? 0) <= (titleFrames.map(\.minY).min() ?? 0))

        let liveLabel = titles.first {
            $0.text?.trimmingCharacters(in: .whitespaces) == "LIVE"
        }
        #expect(liveLabel?.layer.cornerRadius == (liveLabel?.bounds.height ?? 0) / 2)
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

@MainActor
private func truncatedLabels(in rootView: UIView) -> [UILabel] {
    var result: [UILabel] = []

    func visit(_ view: UIView) {
        if let label = view as? UILabel,
           label.isHidden == false,
           label.intrinsicContentSize.width > label.bounds.width + 0.5 {
            result.append(label)
        }
        view.subviews.forEach(visit)
    }

    visit(rootView)
    return result
}

@MainActor
private func descendants<View: UIView>(of type: View.Type, in rootView: UIView) -> [View] {
    var result: [View] = []

    func visit(_ view: UIView) {
        if let match = view as? View {
            result.append(match)
        }
        view.subviews.forEach(visit)
    }

    rootView.subviews.forEach(visit)
    return result
}

private func verticalSpread(of frames: [CGRect]) -> CGFloat {
    guard let minimum = frames.map(\.minY).min(),
          let maximum = frames.map(\.minY).max() else {
        return .infinity
    }
    return maximum - minimum
}

@MainActor
private func menuActions(in menu: UIMenu?) -> [UIAction] {
    guard let menu else { return [] }
    return menu.children.flatMap { element -> [UIAction] in
        if let action = element as? UIAction { return [action] }
        if let submenu = element as? UIMenu { return menuActions(in: submenu) }
        return []
    }
}

@MainActor
private func menuActionTitles(in menu: UIMenu?) -> [String] {
    menuActions(in: menu).map(\.title)
}
