import UIKit
import ListKit

@MainActor
protocol LiveRoomViewModelInput: AnyObject {
    func sendMessage()
    func toggleMic(_ id: String)
    func selectGift(_ id: String)
    func sendGift()
    func selectStudioMode(_ index: Int)
    func handleModeration(_ id: String)
}

@MainActor
protocol LiveRoomViewModelOutput: AnyObject {
    var titleViewModel: LiveRoomTitleViewModel { get }
    var toolbarViewModel: LiveRoomToolbarViewModel { get }
    var liveConsoleSections: [ListSection<LiveRoomSection>] { get }
    var studioControlSections: [ListSection<LiveRoomSection>] { get }
    var roomToolkitSections: [ListSection<LiveRoomSection>] { get }
    var collectionSections: [ListSection<LiveRoomSection>] { get }
    var tableSections: [TableSection<AdminSection>] { get }
    var pendingScrollMessageID: String? { get }
}

enum LiveRoomCollectionEvent: ListEvent {
    case addMessage
    case sendSelectedGift
    case sendGift(String)
    case studioModeChanged(Int)
}

enum LiveRoomAdminEvent: ListEvent {
    case resolve(String)
}

@MainActor
final class LiveRoomViewModel: LiveRoomViewModelInput, LiveRoomViewModelOutput {
    private var state: LiveRoomState
    private var selectedStudioModeIndex = 0

    init(state: LiveRoomState = .sample()) {
        self.state = state
    }

    var titleViewModel: LiveRoomTitleViewModel {
        LiveRoomTitleViewModel(
            title: state.roomName,
            subtitle: "Live UI experiments with ListKit",
            viewerText: "\(state.viewerCount)"
        )
    }

    var toolbarViewModel: LiveRoomToolbarViewModel {
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
        makeRoomActivityTitleSection()
        makeRoomActivitySection()
    }

    @ListSectionBuilder<LiveRoomSection>
    var collectionSections: [ListSection<LiveRoomSection>] {
        makeStatusSection()
        makeMicSeatsSection()
        makeMessagesSection()
        makeGiftsSection()
        makeDiagnosticsSection()
    }

    var tableSections: [TableSection<AdminSection>] {
        [
            makeModerationSection()
        ]
    }

    @ListSectionBuilder<LiveRoomSection>
    var liveActivitySections: [ListSection<LiveRoomSection>] {
        makeRoomActivitySection()
    }

    @ListSectionBuilder<LiveRoomSection>
    var peopleSections: [ListSection<LiveRoomSection>] {
        makeMicSeatsSection()
    }

    @ListSectionBuilder<LiveRoomSection>
    var toolkitSections: [ListSection<LiveRoomSection>] {
        makeStatusSection()
        makeGiftsSection()
        makeDiagnosticsSection()
    }

    var pendingScrollMessageID: String? {
        state.pendingScrollMessageID
    }

    var messageCount: Int {
        state.messages.count
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

    func recordCollectionApply(_ summary: ListApplySummary) {
        state.diagnostics.collectionApplyCount += 1
        state.diagnostics.insertedCount = summary.insertedCount
        state.diagnostics.deletedCount = summary.deletedCount
        state.diagnostics.keptCount = summary.keptCount
        state.diagnostics.refreshIDChangedCount = summary.refreshIDChangedCount
        state.diagnostics.visibleRefreshCount = summary.visibleRefreshCount
        state.diagnostics.diagnosticsIssueCount = summary.diagnosticsIssues.count
    }

    func recordTableApply(_ summary: ListApplySummary) {
        state.diagnostics.tableApplyCount += 1
        state.diagnostics.insertedCount += summary.insertedCount
        state.diagnostics.deletedCount += summary.deletedCount
        state.diagnostics.keptCount += summary.keptCount
        state.diagnostics.refreshIDChangedCount += summary.refreshIDChangedCount
        state.diagnostics.visibleRefreshCount += summary.visibleRefreshCount
        state.diagnostics.diagnosticsIssueCount += summary.diagnosticsIssues.count
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
            badge: "LIVE"
        )
    }

    private var studioHeaderViewModel: LiveConsoleHeaderViewModel {
        LiveConsoleHeaderViewModel(
            title: "Studio Control",
            subtitle: "Operational density with segmented modes, filters, collection sections, and admin actions.",
            badge: "OPS"
        )
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
            symbolName: "slider.horizontal.3"
        )
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
            Row(LiveRoomRowID.consoleHeader, model: model, cell: LiveConsoleHeaderCell.self) { cell, model, _ in
                cell.configure(model)
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
            Row(LiveRoomRowID.studioHeader, model: model, cell: StudioControlHeaderCell.self) { cell, model, _ in
                cell.configure(model)
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
            Row(LiveRoomRowID.roomHero, model: model, cell: RoomHeroCell.self) { cell, model, _ in
                cell.configure(model)
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

    private func makeRoomActivityTitleSection() -> ListSection<LiveRoomSection> {
        let model = roomActivityTitleViewModel
        return ListSection(.roomActivityTitle) {
            Row(LiveRoomRowID.roomActivityTitle, model: model, cell: RoomActivityTitleCell.self) { cell, model, _ in
                cell.configure(model)
            }
            .refreshID(model)
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
            ForEach(state.messages, id: \.id) { message in
                Row(model: message, cell: LiveMessageCell.self) { cell, message, _ in
                    cell.configure(message)
                }
                .refreshID(message.refreshToken)
                .refreshPolicy(.automaticVisible)
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
                contentInsets: ListLayoutInsets(top: 0, leading: 16, bottom: 28, trailing: 16)
            )
        } background: {
            BackgroundDecoration(LiveActivityBackgroundView.self, contentInsets: ListLayoutInsets(top: 0, leading: 16, bottom: 28, trailing: 16))
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
                .onSelect { seat, _ in
                    self?.toggleMic(seat.id)
                }
            }
        } layout: {
            HorizontalLayout(
                itemWidth: .absolute(92),
                itemHeight: .absolute(112),
                spacing: 10,
                contentInsets: ListLayoutInsets(top: 8, leading: 16, bottom: 12, trailing: 16)
            )
        } header: {
            Header(SectionHeaderView.self, id: "mic-header") { view, _ in
                view.configure(title: "Mic seats", detail: "Tap a seat to move speaking focus")
            }
            .layout(height: .absolute(36))
            .refreshID(state.micSeats.map(\.refreshToken).joined(separator: "|"))
        } background: {
            BackgroundDecoration(LiveSectionBackgroundView.self, contentInsets: ListLayoutInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
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
                itemHeight: .estimated(54),
                spacing: 8,
                contentInsets: ListLayoutInsets(top: 8, leading: 16, bottom: 12, trailing: 16)
            )
        } header: {
            Header(SectionHeaderView.self, id: "messages-header") { view, _ in
                view.configure(title: "Live activity", detail: "\(messageCount) messages")
            }
            .layout(height: .absolute(36))
            .refreshID(messageCount)
        } background: {
            BackgroundDecoration(LiveSectionBackgroundView.self, contentInsets: ListLayoutInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
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
                .onSelect { gift, _ in
                    self?.selectGift(gift.id)
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
                contentInsets: ListLayoutInsets(top: 8, leading: 16, bottom: 12, trailing: 16)
            )
        } header: {
            Header(SectionHeaderView.self, id: "gifts-header") { view, _ in
                view.configure(title: "Gift tray", detail: "Selection uses refreshID reconfigure")
            }
            .layout(height: .absolute(36))
            .refreshID(state.selectedGiftID)
        } background: {
            BackgroundDecoration(LiveSectionBackgroundView.self, contentInsets: ListLayoutInsets(top: 4, leading: 16, bottom: 6, trailing: 16))
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
                .selected(event.isSelected)
                .onSelect { event, _ in
                    self?.selectModeration(event.id)
                }
                .contextMenu { _ in
                    UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                        UIMenu(children: [
                            UIAction(title: "Remove event", image: UIImage(systemName: "trash")) { [weak self] _ in
                                self?.handleModeration(event.id)
                            }
                        ])
                    }
                }
                .trailingSwipeActions { [weak self] _ in
                    let action = UIContextualAction(style: .destructive, title: "Mute") { _, _, completion in
                        self?.handleModeration(event.id)
                        completion(true)
                    }
                    action.image = UIImage(systemName: "mic.slash")
                    return UISwipeActionsConfiguration(actions: [action])
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

    private func selectModeration(_ id: String) {
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
