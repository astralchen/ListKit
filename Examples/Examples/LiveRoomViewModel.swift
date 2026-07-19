import UIKit
import ListKit

enum LiveRoomCollectionEvent: ListEvent {
    case addMessage
    case sendSelectedGift
    case sendGift(String)
    case studioModeChanged(Int)
    case roomActivityFilterChanged(RoomActivityFilter)
    case headerMenuAction(LiveRoomMenuAction)
    case activateCapability(String)
}

enum LiveRoomAdminEvent: ListEvent {
    case select(String)
    case resolve(String)
}

@MainActor
final class LiveRoomViewModel {
    private static let cardBackgroundHorizontalInset: CGFloat = 16
    private static let cardContentHorizontalInset: CGFloat = cardBackgroundHorizontalInset + 8

    private var state: LiveRoomState
    private var selectedStudioModeIndex = 0

    init(state: LiveRoomState = .sample()) {
        self.state = state
    }

    private var titleViewModel: LiveRoomTitleViewModel {
        LiveRoomTitleViewModel(
            title: state.roomName,
            subtitle: "Live UI experiments with ListKit",
            viewerText: "\(state.viewerCount)",
            heatText: NumberFormatter.localizedString(
                from: NSNumber(value: state.heat),
                number: .decimal
            ),
            liveEventCount: 28 + state.messages.count,
            menuItems: roomToolkitMenuItems
        )
    }

    private var toolbarViewModel: LiveRoomToolbarViewModel {
        LiveRoomToolbarViewModel(
            messageButtonTitle: "Add Message",
            giftButtonTitle: "Send Gift",
            selectedGiftName: selectedGift?.name ?? "Select gift"
        )
    }

    @ListSectionBuilder<LiveRoomSection>
    var liveConsoleSections: [ListSection<LiveRoomSection>] {
        makeConsoleHeaderSection()
        makeConsoleToolbarSection()
        makeStatusSection()
        makeMicSeatsSection()
        makeMessagesSection()
        makeGiftsSection()
        makeDiagnosticsSection()
    }

    @ListSectionBuilder<LiveRoomSection>
    var studioControlSections: [ListSection<LiveRoomSection>] {
        makeStudioHeaderSection()
        makeStudioControlsSection()
        makeMessagesSection()
    }

    @ListSectionBuilder<LiveRoomSection>
    var roomToolkitSections: [ListSection<LiveRoomSection>] {
        makeRoomHeroSection()
        makeRoomMetricsSection()
        makeAPIGuideSection()
        makeRoomActivityTitleSection()
        makeRoomActivitySection()
    }

    var tableSections: [TableSection<AdminSection>] {
        [
            makeModerationSection()
        ]
    }

    var pendingScrollMessageID: String? {
        state.pendingScrollMessageID
    }

    var isAPIGuideExpanded: Bool {
        state.isAPIGuideExpanded
    }

    var activityFilter: RoomActivityFilter {
        state.activityFilter
    }

    var messageCount: Int {
        state.messages.count
    }

    var viewerCount: Int {
        state.viewerCount
    }

    var heat: Int {
        state.heat
    }

    var selectedStudioMode: Int {
        selectedStudioModeIndex
    }

    var pendingModerationCount: Int {
        state.moderationEvents.count
    }

    var selectedGiftID: String {
        state.selectedGiftID
    }

    var latestMessageID: String? {
        state.messages.last?.id
    }

    var visibleModerationEventIDs: [String] {
        state.moderationEvents.map(\.id)
    }

    func sendMessage() {
        state.messageSequence += 1
        let message = LiveMessage(
            id: "msg-\(state.messageSequence)",
            sender: ["Rin", "Sam", "Tara", "Bo"][state.messageSequence % 4],
            text: nextMessageText(),
            tone: "chat",
            version: 0
        )
        state.messages.append(message)
        state.viewerCount += 7
        state.heat += 216
        state.statusVersion += 1
        state.pendingScrollMessageID = message.id
    }

    func toggleMic(_ id: String) {
        guard let index = state.micSeats.firstIndex(where: { $0.id == id }) else { return }
        for seatIndex in state.micSeats.indices {
            state.micSeats[seatIndex].isSpeaking = seatIndex == index
            state.micSeats[seatIndex].version += 1
        }
        state.statusVersion += 1
    }

    func selectGift(_ id: String) {
        guard state.gifts.contains(where: { $0.id == id }) else { return }
        state.selectedGiftID = id
        for index in state.gifts.indices {
            state.gifts[index].isSelected = state.gifts[index].id == id
            state.gifts[index].version += 1
        }
    }

    func sendGift() {
        guard let selectedGift else { return }
        if let index = state.gifts.firstIndex(where: { $0.id == selectedGift.id }) {
            state.gifts[index].sentCount += 1
            state.gifts[index].version += 1
        }
        state.messageSequence += 1
        let message = LiveMessage(
            id: "msg-\(state.messageSequence)",
            sender: "System",
            text: "\(selectedGift.name) sent to \(state.hostName).",
            tone: "gift",
            version: 0
        )
        state.messages.append(message)
        state.heat += selectedGift.price * 18
        state.statusVersion += 1
        state.pendingScrollMessageID = message.id
    }

    func selectStudioMode(_ index: Int) {
        selectedStudioModeIndex = min(max(index, 0), 2)
    }

    func performMenuAction(_ action: LiveRoomMenuAction) {
        switch action {
        case .addMessage:
            sendMessage()
        case .sendSelectedGift:
            sendGift()
        case .refreshStatus:
            state.viewerCount += 5
            state.heat += 128
            state.statusVersion += 1
            state.pendingScrollMessageID = nil
        case .addSystemEvent:
            state.messageSequence += 1
            let message = LiveMessage(
                id: "msg-\(state.messageSequence)",
                sender: "System",
                text: "System health check completed.",
                tone: "system",
                version: 0
            )
            state.messages.append(message)
            state.heat += 64
            state.statusVersion += 1
            state.pendingScrollMessageID = message.id
        case .selectStudioMode(let index):
            selectStudioMode(index)
            state.pendingScrollMessageID = nil
        case .resetDemo:
            state = .sample()
            selectedStudioModeIndex = 0
        }
    }

    func handleModeration(_ id: String) {
        guard let index = state.moderationEvents.firstIndex(where: { $0.id == id }) else { return }
        let event = state.moderationEvents.remove(at: index)
        state.messageSequence += 1
        state.messages.append(
            LiveMessage(
                id: "msg-\(state.messageSequence)",
                sender: "Admin",
                text: "Resolved: \(event.title)",
                tone: "system",
                version: 0
            )
        )
        state.statusVersion += 1
        state.pendingScrollMessageID = state.messages.last?.id
    }

    func activateCapability(_ title: String) {
        state.messageSequence += 1
        let message = LiveMessage(
            id: "msg-\(state.messageSequence)",
            sender: "ListKit",
            text: "Activated \(title) through a stable row context.",
            tone: "system",
            version: 0
        )
        state.messages.append(message)
        state.pendingScrollMessageID = message.id
    }

    func setAPIGuideExpanded(_ isExpanded: Bool) {
        state.isAPIGuideExpanded = isExpanded
    }

    func setRoomActivityFilter(_ filter: RoomActivityFilter) {
        guard state.activityFilter != filter else { return }
        state.activityFilter = filter
        state.pendingScrollMessageID = nil
    }

    func moveModeration(from source: IndexPath, to destination: IndexPath) {
        guard source.section == destination.section,
              state.moderationEvents.indices.contains(source.row) else { return }
        let event = state.moderationEvents.remove(at: source.row)
        let destinationRow = min(max(destination.row, 0), state.moderationEvents.count)
        state.moderationEvents.insert(event, at: destinationRow)
    }

    func recordCollectionApply(_ summary: ListApplySummary) {
        state.diagnostics.collectionApplyCount += 1
        recordApply(summary)
    }

    func recordTableApply(_ summary: ListApplySummary) {
        state.diagnostics.tableApplyCount += 1
        recordApply(summary)
    }

    private func recordApply(_ summary: ListApplySummary) {
        state.diagnostics.insertedCount = summary.insertedCount
        state.diagnostics.deletedCount = summary.deletedCount
        state.diagnostics.movedCount = summary.movedCount
        state.diagnostics.keptCount = summary.keptCount
        state.diagnostics.refreshIDChangedCount = summary.refreshIDChangedCount
        state.diagnostics.visibleRefreshCount = summary.visibleRefreshCount
        state.diagnostics.contentTransitionCount = summary.animation.contentTransitionCount
        state.diagnostics.anchorCompensation = summary.animation.anchorCompensation
        state.diagnostics.lastCompletionState = String(describing: summary.animation.completionState)
        state.diagnostics.diagnosticsIssueCount = summary.diagnosticsIssues.count
    }

    func recordPrefetch(itemCount: Int, cancelled: Bool = false) {
        if cancelled {
            state.diagnostics.cancelledPrefetchItemCount += itemCount
        } else {
            state.diagnostics.prefetchedItemCount += itemCount
        }
    }

    func clearPendingScroll() {
        state.pendingScrollMessageID = nil
    }

    private var selectedGift: GiftItem? {
        state.gifts.first { $0.id == state.selectedGiftID }
    }

    private var consoleHeaderViewModel: LiveConsoleHeaderViewModel {
        LiveConsoleHeaderViewModel(
            title: "Live Console",
            subtitle: "Collection adapter demo with room status, mic seats, activity, gifts, and diagnostics.",
            badge: "LIVE",
            menuItems: liveConsoleMenuItems
        )
    }

    private var studioHeaderViewModel: LiveConsoleHeaderViewModel {
        LiveConsoleHeaderViewModel(
            title: "Studio Control",
            subtitle: "Operational density with segmented modes, filters, collection sections, and admin actions.",
            badge: "OPS",
            menuItems: studioControlMenuItems
        )
    }

    private var liveConsoleMenuItems: [LiveRoomMenuItem] {
        [
            LiveRoomMenuItem(action: .addMessage, title: "Add Message", symbolName: "text.bubble"),
            LiveRoomMenuItem(action: .sendSelectedGift, title: "Send Selected Gift", symbolName: "gift"),
            LiveRoomMenuItem(action: .refreshStatus, title: "Refresh Status", symbolName: "arrow.clockwise"),
            LiveRoomMenuItem(
                action: .resetDemo,
                title: "Reset Demo",
                symbolName: "arrow.counterclockwise",
                role: .destructive
            )
        ]
    }

    private var studioControlMenuItems: [LiveRoomMenuItem] {
        let modes = ["Room Mode", "Gift Mode", "Log Mode"]
        var items = modes.indices.map { index in
            LiveRoomMenuItem(
                action: .selectStudioMode(index),
                title: modes[index],
                symbolName: ["person.3", "gift", "text.alignleft"][index],
                isSelected: selectedStudioModeIndex == index
            )
        }
        items.append(
            LiveRoomMenuItem(action: .refreshStatus, title: "Refresh Status", symbolName: "arrow.clockwise")
        )
        items.append(
            LiveRoomMenuItem(
                action: .resetDemo,
                title: "Reset Demo",
                symbolName: "arrow.counterclockwise",
                role: .destructive
            )
        )
        return items
    }

    private var roomToolkitMenuItems: [LiveRoomMenuItem] {
        [
            LiveRoomMenuItem(action: .refreshStatus, title: "Refresh Status", symbolName: "arrow.clockwise"),
            LiveRoomMenuItem(action: .addSystemEvent, title: "Add System Event", symbolName: "bolt.horizontal"),
            LiveRoomMenuItem(
                action: .resetDemo,
                title: "Reset Demo",
                symbolName: "arrow.counterclockwise",
                role: .destructive
            )
        ]
    }

    private var studioControlPanelViewModel: StudioControlPanelViewModel {
        StudioControlPanelViewModel(
            selectedModeIndex: selectedStudioModeIndex,
            summary: studioModeSummary,
            chips: ["Hot", "Guest Requests", "Moderation", "Gift Goal"]
        )
    }

    private var roomActivityTitleViewModel: RoomActivityTitleViewModel {
        RoomActivityTitleViewModel(
            title: "Live Activity",
            buttonTitle: "Filter",
            symbolName: "slider.horizontal.3",
            selectedFilter: state.activityFilter
        )
    }

    private var filteredRoomActivityMessages: [LiveMessage] {
        state.messages.filter(state.activityFilter.includes)
    }

    private var studioModeSummary: String {
        switch selectedStudioModeIndex {
        case 1:
            return "Gift mode highlights selected items and refreshID-driven reconfigure behavior."
        case 2:
            return "Log mode focuses on swipe actions, context menus, and table selection."
        default:
            return "Room mode keeps the live control surface dense and scan-friendly."
        }
    }

    private var statusViewModel: RoomStatusViewModel {
        RoomStatusViewModel(
            roomName: state.roomName,
            hostName: state.hostName,
            mode: state.mode,
            viewerCount: state.viewerCount,
            heat: state.heat,
            pendingModerationCount: state.moderationEvents.count,
            refreshVersion: state.statusVersion
        )
    }

    private func makeConsoleHeaderSection() -> ListSection<LiveRoomSection> {
        let model = consoleHeaderViewModel
        return ListSection(.consoleHeader) {
            Row(LiveRoomRowID.consoleHeader, model: model, cell: LiveConsoleHeaderCell.self) { cell, model, context in
                cell.configure(model) { action in
                    context.send(LiveRoomCollectionEvent.headerMenuAction(action))
                }
            }
            .refreshID(model)
            .refreshPolicy(.whenRefreshIDChanges)
        } layout: {
            ListLayout(
                itemHeight: .absolute(86),
                contentInsets: ListLayoutInsets(top: 18, leading: 16, bottom: 6, trailing: 16)
            )
        }
    }

    private func makeStudioHeaderSection() -> ListSection<LiveRoomSection> {
        let model = studioHeaderViewModel
        return ListSection(.studioHeader) {
            Row(LiveRoomRowID.studioHeader, model: model, cell: StudioControlHeaderCell.self) { cell, model, context in
                cell.configure(model) { action in
                    context.send(LiveRoomCollectionEvent.headerMenuAction(action))
                }
            }
            .refreshID(model)
            .refreshPolicy(.whenRefreshIDChanges)
        } layout: {
            ListLayout(
                itemHeight: .absolute(86),
                contentInsets: ListLayoutInsets(top: 18, leading: 16, bottom: 6, trailing: 16)
            )
        }
    }

    private func makeStudioControlsSection() -> ListSection<LiveRoomSection> {
        let model = studioControlPanelViewModel
        return ListSection(.studioControls) {
            Row(LiveRoomRowID.studioControls, model: model, cell: StudioControlPanelCell.self) { cell, model, context in
                cell.configure(model)
                cell.onModeChange = { index in
                    context.send(LiveRoomCollectionEvent.studioModeChanged(index))
                }
            }
            .refreshID(model)
            .refreshPolicy(.automaticVisible)
        } layout: {
            ListLayout(
                itemHeight: .absolute(274),
                contentInsets: ListLayoutInsets(top: 4, leading: 16, bottom: 10, trailing: 16)
            )
        }
    }

    private func makeRoomHeroSection() -> ListSection<LiveRoomSection> {
        let model = titleViewModel
        return ListSection(.roomHero) {
            Row(LiveRoomRowID.roomHero, model: model, cell: RoomHeroCell.self) { cell, model, context in
                cell.configure(model) { action in
                    context.send(LiveRoomCollectionEvent.headerMenuAction(action))
                }
            }
            .refreshID(model)
            .refreshPolicy(.whenRefreshIDChanges)
        } layout: {
            ListLayout(
                itemHeight: .absolute(104),
                contentInsets: ListLayoutInsets(top: 22, leading: 16, bottom: 8, trailing: 16)
            )
        }
    }

    private func makeRoomMetricsSection() -> ListSection<LiveRoomSection> {
        ListSection(.roomMetrics) {
            Row(LiveRoomRowID.roomMetrics, model: statusViewModel, cell: RoomMetricStripCell.self) { cell, model, _ in
                cell.configure(model)
            }
            .refreshID(statusViewModel.refreshVersion)
            .refreshPolicy(.whenRefreshIDChanges)
        } layout: {
            ListLayout(
                itemHeight: .absolute(112),
                contentInsets: ListLayoutInsets(top: 10, leading: 16, bottom: 18, trailing: 16)
            )
        }
    }

    private func makeAPIGuideSection() -> ListSection<LiveRoomSection> {
        let root = ListKitCapability(
            id: .apiGuideRoot,
            title: "SwiftUI-style API guide",
            detail: "Expand to try stable identity, async apply, focus, menus, and native swipe actions.",
            symbolName: "point.3.connected.trianglepath.dotted"
        )
        let capabilities = [
            ListKitCapability(
                id: .apiAsyncApply,
                title: "Async snapshot apply",
                detail: "Rendering waits for diffable and outline snapshots before scrolling.",
                symbolName: "arrow.triangle.2.circlepath"
            ),
            ListKitCapability(
                id: .apiStableIdentity,
                title: "Stable row context",
                detail: "Selection and events use business identity instead of captured index paths.",
                symbolName: "number.square"
            ),
            ListKitCapability(
                id: .apiNativeInteractions,
                title: "Native interactions",
                detail: "Try keyboard focus, Return, a context menu, or swipe this row.",
                symbolName: "hand.tap"
            )
        ]

        return ListSection(.apiGuide) {
            DisclosureGroup(
                Row(root.id, model: root, cell: UICollectionViewListCell.self) { cell, capability, _ in
                    Self.configureCapabilityCell(cell, capability: capability)
                }
                .refreshID(root)
                .focusable()
                .outlineDisclosure()
                .outlineAnimation(.automatic),
                isExpanded: state.isAPIGuideExpanded
            ) {
                ForEach(capabilities, id: \.id) { capability in
                    Row(model: capability, cell: UICollectionViewListCell.self) { cell, capability, _ in
                        Self.configureCapabilityCell(cell, capability: capability)
                    }
                    .refreshID(capability)
                    .focusable()
                    .selectionFollowsFocus()
                    .springLoadingEnabled()
                    .contextMenu { context in
                        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                            UIMenu(children: [
                                UIAction(title: "Activate", image: UIImage(systemName: "bolt.fill")) { _ in
                                    context.send(LiveRoomCollectionEvent.activateCapability(capability.title))
                                }
                            ])
                        }
                    }
                    .contextMenuPreview(highlighting: { context in
                        guard let collectionView = context.collectionViewIfAvailable,
                              let cell = collectionView.cellForItem(at: context.indexPath) else { return nil }
                        return UITargetedPreview(view: cell)
                    })
                    .trailingSwipeActions { context in
                        let action = UIContextualAction(style: .normal, title: "Try") { _, _, completion in
                            context.send(LiveRoomCollectionEvent.activateCapability(capability.title))
                            completion(true)
                        }
                        action.backgroundColor = .systemIndigo
                        action.image = UIImage(systemName: "bolt.fill")
                        return UISwipeActionsConfiguration(actions: [action])
                    }
                }
            }
        } layout: {
            UIKitListLayout(appearance: .insetGrouped, headerTopPadding: 0)
        }
        .selectionMode(.single)
        .indexTitle("API")
        .onExpansionChange { [weak self] identity, isExpanded in
            guard identity.rowID.typed(LiveRoomRowID.self) == .apiGuideRoot else { return }
            self?.setAPIGuideExpanded(isExpanded)
        }
    }

    private static func configureCapabilityCell(
        _ cell: UICollectionViewListCell,
        capability: ListKitCapability
    ) {
        var content = cell.defaultContentConfiguration()
        content.text = capability.title
        content.secondaryText = capability.detail
        content.secondaryTextProperties.numberOfLines = 2
        content.image = UIImage(systemName: capability.symbolName)
        content.imageProperties.tintColor = .systemIndigo
        cell.contentConfiguration = content
    }

    private static func cardContentInsets(top: CGFloat, bottom: CGFloat) -> ListLayoutInsets {
        ListLayoutInsets(
            top: top,
            leading: cardContentHorizontalInset,
            bottom: bottom,
            trailing: cardContentHorizontalInset
        )
    }

    private static func cardBackgroundInsets(top: CGFloat, bottom: CGFloat) -> ListLayoutInsets {
        ListLayoutInsets(
            top: top,
            leading: cardBackgroundHorizontalInset,
            bottom: bottom,
            trailing: cardBackgroundHorizontalInset
        )
    }

    private func makeRoomActivityTitleSection() -> ListSection<LiveRoomSection> {
        let model = roomActivityTitleViewModel
        return ListSection(.roomActivityTitle) {
            Row(LiveRoomRowID.roomActivityTitle, model: model, cell: RoomActivityTitleCell.self) { cell, model, context in
                cell.configure(model) { filter in
                    context.send(LiveRoomCollectionEvent.roomActivityFilterChanged(filter))
                }
            }
            .refreshID(LiveRoomRowID.roomActivityTitle)
            .refreshPolicy(.whenRefreshIDChanges)
        } layout: {
            ListLayout(
                itemHeight: .absolute(42),
                contentInsets: ListLayoutInsets(top: 4, leading: 16, bottom: 6, trailing: 16)
            )
        }
    }

    private func makeRoomActivitySection() -> ListSection<LiveRoomSection> {
        ListSection(.roomActivity) {
            ForEach(filteredRoomActivityMessages, id: \.id) { message in
                Row(model: message, cell: LiveMessageCell.self) { cell, message, _ in
                    cell.configure(message)
                }
                .refreshID(message.refreshToken)
                .refreshPolicy(.automaticVisible)
                .contentTransition(.opacity)
                .selectionDisabled()
                .contextMenu { _ in
                    UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                        UIMenu(children: [
                            UIAction(title: "Copy text", image: UIImage(systemName: "doc.on.doc")) { _ in }
                        ])
                    }
                }
            }
        } layout: {
            ListLayout(
                itemHeight: .estimated(106),
                spacing: 0,
                contentInsets: Self.cardContentInsets(top: 0, bottom: 28)
            )
        } background: {
            BackgroundDecoration(
                LiveActivityBackgroundView.self,
                contentInsets: Self.cardBackgroundInsets(top: 0, bottom: 28)
            )
        }
    }

    private func makeStatusSection() -> ListSection<LiveRoomSection> {
        let model = statusViewModel
        return ListSection(.status) {
            Row(LiveRoomRowID.status, model: model, cell: LiveRoomStatusCell.self) { cell, model, _ in
                cell.configure(model)
            }
            .refreshID(model.refreshVersion)
            .refreshPolicy(.whenRefreshIDChanges)
            .selectionDisabled()
        } layout: {
            ListLayout(
                itemHeight: .estimated(118),
                contentInsets: ListLayoutInsets(top: 14, leading: 16, bottom: 8, trailing: 16)
            )
        }
    }

    private func makeMicSeatsSection() -> ListSection<LiveRoomSection> {
        ListSection(.micSeats) {
            ForEach(state.micSeats, id: \.id) { [weak self] seat in
                Row(model: seat, cell: MicSeatCell.self) { cell, seat, _ in
                    cell.configure(seat)
                }
                .refreshID(seat.refreshToken)
                .selected(seat.isSpeaking)
                .focusable()
                .selectionFollowsFocus()
                .onSelect { seat, _ in
                    self?.toggleMic(seat.id)
                }
                .onPrimaryAction { seat, _ in
                    self?.toggleMic(seat.id)
                }
            }
        } layout: {
            HorizontalLayout(
                itemWidth: .absolute(92),
                itemHeight: .absolute(112),
                spacing: 10,
                contentInsets: Self.cardContentInsets(top: 8, bottom: 12),
                scrollingBehavior: .continuousGroupLeadingBoundary
            )
        } header: {
            Header(SectionHeaderView.self, id: "mic-header") { view, _ in
                view.configure(title: "Mic seats", detail: "Tap a seat to move speaking focus")
            }
            .layout(height: .absolute(36))
            .refreshID(state.micSeats.map(\.refreshToken).joined(separator: "|"))
        } background: {
            BackgroundDecoration(
                LiveSectionBackgroundView.self,
                contentInsets: Self.cardBackgroundInsets(top: 4, bottom: 6)
            )
        }
        .selectionMode(.single)
    }

    private func makeMessagesSection() -> ListSection<LiveRoomSection> {
        let messageCount = state.messages.count
        return ListSection(.messages) {
            ForEach(state.messages, id: \.id) { message in
                Row(model: message, cell: LiveMessageCell.self) { cell, message, _ in
                    cell.configure(message)
                }
                .refreshID(message.refreshToken)
                .refreshPolicy(.automaticVisible)
                .contentTransition(.opacity)
                .selectionDisabled()
                .contextMenu { _ in
                    UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                        UIMenu(children: [
                            UIAction(title: "Copy text", image: UIImage(systemName: "doc.on.doc")) { _ in }
                        ])
                    }
                }
            }
        } layout: {
            ListLayout(
                itemHeight: .estimated(106),
                spacing: 8,
                contentInsets: Self.cardContentInsets(top: 8, bottom: 12)
            )
        } header: {
            Header(SectionHeaderView.self, id: "messages-header") { view, _ in
                view.configure(title: "Live activity", detail: "\(messageCount) messages")
            }
            .layout(height: .absolute(36))
            .refreshID(messageCount)
        } background: {
            BackgroundDecoration(
                LiveSectionBackgroundView.self,
                contentInsets: Self.cardBackgroundInsets(top: 4, bottom: 6)
            )
        }
    }

    private func makeGiftsSection() -> ListSection<LiveRoomSection> {
        ListSection(.gifts) {
            ForEach(state.gifts, id: \.id) { [weak self] gift in
                Row(model: gift, cell: GiftCell.self) { cell, gift, _ in
                    cell.configure(gift)
                }
                .refreshID(gift.refreshToken)
                .refreshPolicy(.whenRefreshIDChanges)
                .selected(gift.isSelected)
                .focusable()
                .selectionFollowsFocus()
                .springLoadingEnabled()
                .onSelect { gift, _ in
                    self?.selectGift(gift.id)
                }
                .onPrimaryAction { gift, _ in
                    self?.selectGift(gift.id)
                }
                .onHighlightChange { highlighted, context in
                    guard let cell = context.collectionViewIfAvailable?.cellForItem(at: context.indexPath) else { return }
                    UIView.animate(withDuration: 0.15) {
                        cell.transform = highlighted
                            ? CGAffineTransform(scaleX: 0.97, y: 0.97)
                            : .identity
                    }
                }
                .onCellEvent({ cell, trigger in
                    cell.onSend = trigger
                }, send: { gift in
                    LiveRoomCollectionEvent.sendGift(gift.id)
                })
            }
        } layout: {
            GridLayout(
                columns: 2,
                spacing: 10,
                itemHeight: .absolute(86),
                contentInsets: Self.cardContentInsets(top: 8, bottom: 12)
            )
        } header: {
            Header(SectionHeaderView.self, id: "gifts-header") { view, _ in
                view.configure(title: "Gift tray", detail: "Selection uses refreshID reconfigure")
            }
            .layout(height: .absolute(36))
            .refreshID(state.selectedGiftID)
        } background: {
            BackgroundDecoration(
                LiveSectionBackgroundView.self,
                contentInsets: Self.cardBackgroundInsets(top: 4, bottom: 6)
            )
        }
        .selectionMode(.single)
    }

    private func makeDiagnosticsSection() -> ListSection<LiveRoomSection> {
        ListSection(.diagnostics) {
            Row(LiveRoomRowID.diagnostics, model: (), cell: DiagnosticsCell.self) { [weak self] cell, _, _ in
                cell.configure(self?.state.diagnostics ?? ApplyDiagnostics())
            }
            .refreshID(state.diagnostics.refreshVersion)
            .refreshPolicy(.alwaysVisible)
        } layout: {
            ListLayout(
                itemHeight: .estimated(58),
                contentInsets: ListLayoutInsets(top: 4, leading: 16, bottom: 20, trailing: 16)
            )
        }
    }

    private func makeConsoleToolbarSection() -> ListSection<LiveRoomSection> {
        let model = toolbarViewModel
        return ListSection(.consoleToolbar) {
            Row(LiveRoomRowID.consoleToolbar, model: model, cell: LiveConsoleToolbarCell.self) { cell, model, _ in
                cell.configure(model)
            }
            .refreshID(model)
            .refreshPolicy(.automaticVisible)
            .onCellEvent({ cell, trigger in
                cell.onAddMessage = trigger
            }, send: { _ in
                LiveRoomCollectionEvent.addMessage
            })
            .onCellEvent({ cell, trigger in
                cell.onSendGift = trigger
            }, send: { _ in
                LiveRoomCollectionEvent.sendSelectedGift
            })
        } layout: {
            ListLayout(
                itemHeight: .absolute(76),
                contentInsets: ListLayoutInsets(top: 4, leading: 16, bottom: 22, trailing: 16)
            )
        }
    }

    private func makeModerationSection() -> TableSection<AdminSection> {
        let moderationCount = state.moderationEvents.count
        return TableSection(.moderation) {
            TableForEach(state.moderationEvents, id: \.id) { [weak self] event in
                TableRow(model: event, cell: AdminEventTableCell.self) { cell, event, _ in
                    cell.configure(event)
                }
                .height(.fixed(72))
                .refreshID(event.refreshToken)
                .contentTransition(.opacity)
                .selected(event.isSelected)
                .focusable()
                .selectionFollowsFocus()
                .springLoadingEnabled()
                .indentWhileEditing(false)
                .onSelect { event, context in
                    context.send(LiveRoomAdminEvent.select(event.id))
                }
                .onPrimaryAction { event, context in
                    context.send(LiveRoomAdminEvent.select(event.id))
                }
                .contextMenu { context in
                    UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                        UIMenu(children: [
                            UIAction(title: "Resolve event", image: UIImage(systemName: "checkmark.circle")) { _ in
                                context.send(LiveRoomAdminEvent.resolve(event.id))
                            }
                        ])
                    }
                }
                .contextMenuPreview(highlighting: { context in
                    guard let tableView = context.tableViewIfAvailable,
                          let cell = tableView.cellForRow(at: context.indexPath) else { return nil }
                    return UITargetedPreview(view: cell)
                })
                .editing(.delete) { event, _, context in
                    context.send(LiveRoomAdminEvent.resolve(event.id))
                }
                .onEditingChange { isEditing, context in
                    context.tableViewIfAvailable?.cellForRow(at: context.indexPath)?.contentView.alpha = isEditing ? 0.82 : 1
                }
                .trailingSwipeActions { context in
                    let action = UIContextualAction(style: .destructive, title: "Mute") { _, _, completion in
                        context.send(LiveRoomAdminEvent.resolve(event.id))
                        completion(true)
                    }
                    action.image = UIImage(systemName: "mic.slash")
                    return UISwipeActionsConfiguration(actions: [action])
                }
                .moveTarget { source, proposed in
                    IndexPath(row: proposed.row, section: source.section)
                }
                .onMove { _, source, destination in
                    self?.moveModeration(from: source, to: destination)
                }
            }
        } header: {
            TableHeader(AdminHeaderView.self, id: "moderation-header") { view, _ in
                view.configure(title: "Admin Events", detail: "\(moderationCount)")
            }
            .height(.fixed(54))
            .refreshID(moderationCount)
        }
        .selectionMode(.single)
    }

    func selectModeration(_ id: String) {
        for index in state.moderationEvents.indices {
            state.moderationEvents[index].isSelected = state.moderationEvents[index].id == id
            state.moderationEvents[index].version += 1
        }
    }

    private func nextMessageText() -> String {
        let messages = [
            "Queue the next guest request.",
            "Moderator action synced.",
            "Audience heat is climbing.",
            "Pinned notice refreshed."
        ]
        return messages[state.messageSequence % messages.count]
    }
}
