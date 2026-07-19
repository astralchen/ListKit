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
        let standard = LiveRoomMenuItem(
            action: .refreshStatus,
            title: "Refresh Status",
            symbolName: "arrow.clockwise"
        )
        let selected = LiveRoomMenuItem(
            action: .selectStudioMode(0),
            title: "Room Mode",
            symbolName: "person.3",
            isSelected: true
        )
        let destructive = LiveRoomMenuItem(
            action: .resetDemo,
            title: "Reset Demo",
            symbolName: "arrow.counterclockwise",
            role: .destructive
        )

        let liveCell = LiveConsoleHeaderCell(frame: CGRect(x: 0, y: 0, width: 390, height: 86))
        liveCell.configure(
            LiveConsoleHeaderViewModel(
                title: "Live Console",
                subtitle: "Demo",
                badge: "LIVE",
                menuItems: [standard, destructive]
            ),
            onMenuAction: { _ in }
        )

        let studioCell = StudioControlHeaderCell(frame: CGRect(x: 0, y: 0, width: 390, height: 86))
        studioCell.configure(
            LiveConsoleHeaderViewModel(
                title: "Studio Control",
                subtitle: "Demo",
                badge: "OPS",
                menuItems: [selected, destructive]
            ),
            onMenuAction: { _ in }
        )

        let roomCell = RoomHeroCell(frame: CGRect(x: 0, y: 0, width: 390, height: 104))
        roomCell.configure(
            LiveRoomTitleViewModel(
                title: "Room Toolkit",
                subtitle: "Demo",
                viewerText: "1248",
                heatText: "8932",
                liveEventCount: 4,
                menuItems: [standard, destructive]
            ),
            onMenuAction: { _ in }
        )

        let liveMenu = descendants(of: UIButton.self, in: liveCell)
            .first { $0.accessibilityIdentifier == "live-console-header-menu" }?.menu
        let studioMenu = descendants(of: UIButton.self, in: studioCell)
            .first { $0.accessibilityIdentifier == "studio-control-header-menu" }?.menu
        let roomMenu = descendants(of: UIButton.self, in: roomCell)
            .first { $0.accessibilityIdentifier == "room-toolkit-header-menu" }?.menu

        #expect(menuActionTitles(in: liveMenu) == ["Refresh Status", "Reset Demo"])
        #expect(menuActionTitles(in: studioMenu) == ["Room Mode", "Reset Demo"])
        #expect(menuActionTitles(in: roomMenu) == ["Refresh Status", "Reset Demo"])
        #expect(menuActions(in: studioMenu).first?.state == .on)
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

    @Test func roomMetricsAlignIconsAndTitlesBelowThem() {
        let strip = RoomMetricStripView(frame: CGRect(x: 0, y: 0, width: 390, height: 112))

        strip.setNeedsLayout()
        strip.layoutIfNeeded()

        let icons = descendants(of: UIImageView.self, in: strip)
        let iconContainers = descendants(of: UIView.self, in: strip).filter {
            $0.accessibilityIdentifier == "room-metric-icon-container"
        }
        let titleValues = Set(["LIVE", "Excellent", "Host", "Mic On", "5"])
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
