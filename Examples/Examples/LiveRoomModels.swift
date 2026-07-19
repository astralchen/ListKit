import Foundation

enum LiveRoomSection: Hashable, Sendable {
    case studioControls
    case roomMetrics
    case apiGuide
    case roomActivityTitle
    case roomActivity
    case status
    case micSeats
    case messages
    case gifts
    case diagnostics
    case consoleToolbar
}

enum AdminSection: Hashable, Sendable {
    case moderation
}

enum LiveRoomRowID: Hashable, Sendable {
    case studioControls
    case roomMetrics
    case apiGuideRoot
    case apiAsyncApply
    case apiStableIdentity
    case apiNativeInteractions
    case roomActivityTitle
    case status
    case diagnostics
    case consoleToolbar
}

enum LiveRoomMenuAction: Hashable, Sendable {
    case addMessage
    case sendSelectedGift
    case refreshStatus
    case addSystemEvent
    case selectStudioMode(Int)
    case resetDemo
}

enum LiveRoomMenuRole: Hashable, Sendable {
    case standard
    case destructive
}

struct LiveRoomMenuItem: Hashable, Sendable {
    var action: LiveRoomMenuAction
    var title: String
    var symbolName: String
    var isSelected: Bool = false
    var role: LiveRoomMenuRole = .standard
}

struct ScreenNavigationViewModel: Hashable, Sendable {
    var title: String
    var inlineSubtitle: String
    var largeSubtitle: String
    var menuItems: [LiveRoomMenuItem]
}

struct StudioControlPanelViewModel: Hashable, Sendable {
    var selectedModeIndex: Int
    var summary: String
    var chips: [String]
}

enum RoomActivityFilter: String, CaseIterable, Hashable, Sendable {
    case all
    case messages
    case gifts
    case system

    var title: String {
        switch self {
        case .all: "All Activity"
        case .messages: "Messages"
        case .gifts: "Gifts"
        case .system: "System"
        }
    }

    var symbolName: String {
        switch self {
        case .all: "line.3.horizontal.decrease.circle"
        case .messages: "message"
        case .gifts: "gift"
        case .system: "gearshape"
        }
    }

    func includes(_ message: LiveMessage) -> Bool {
        switch self {
        case .all:
            true
        case .messages:
            message.tone == "chat" || message.tone == "hot"
        case .gifts:
            message.tone == "gift"
        case .system:
            message.tone == "system"
        }
    }
}

struct RoomActivityTitleViewModel: Hashable, Sendable {
    var title: String
    var buttonTitle: String
    var symbolName: String
    var selectedFilter: RoomActivityFilter
}

struct LiveRoomToolbarViewModel: Hashable, Sendable {
    var messageButtonTitle: String
    var giftButtonTitle: String
    var selectedGiftName: String
}

struct RoomStatusViewModel: Hashable, Sendable {
    var roomName: String
    var hostName: String
    var mode: String
    var viewerCount: Int
    var heat: Int
    var pendingModerationCount: Int
    var refreshVersion: Int

    var viewerText: String { "\(viewerCount)" }
    var heatText: String { "\(heat)" }
    var moderationText: String { "\(pendingModerationCount)" }
}

struct ApplyDiagnostics: Hashable, Sendable {
    var collectionApplyCount: Int = 0
    var tableApplyCount: Int = 0
    var insertedCount: Int = 0
    var deletedCount: Int = 0
    var movedCount: Int = 0
    var keptCount: Int = 0
    var refreshIDChangedCount: Int = 0
    var visibleRefreshCount: Int = 0
    var contentTransitionCount: Int = 0
    var anchorCompensation: CGFloat = 0
    var lastCompletionState: String = "submitted"
    var diagnosticsIssueCount: Int = 0
    var prefetchedItemCount: Int = 0
    var cancelledPrefetchItemCount: Int = 0

    var refreshVersion: Int {
        var hasher = Hasher()
        hasher.combine(collectionApplyCount)
        hasher.combine(tableApplyCount)
        hasher.combine(insertedCount)
        hasher.combine(deletedCount)
        hasher.combine(movedCount)
        hasher.combine(keptCount)
        hasher.combine(refreshIDChangedCount)
        hasher.combine(visibleRefreshCount)
        hasher.combine(contentTransitionCount)
        hasher.combine(anchorCompensation)
        hasher.combine(lastCompletionState)
        hasher.combine(diagnosticsIssueCount)
        hasher.combine(prefetchedItemCount)
        hasher.combine(cancelledPrefetchItemCount)
        return hasher.finalize()
    }

    var summaryText: String {
        "apply c\(collectionApplyCount)/t\(tableApplyCount)  ins \(insertedCount)  del \(deletedCount)  move \(movedCount)  kept \(keptCount)"
    }

    var refreshText: String {
        "\(lastCompletionState)  refreshID \(refreshIDChangedCount)  visible \(visibleRefreshCount)  transition \(contentTransitionCount)  anchor \(Int(anchorCompensation.rounded()))"
    }
}

struct ListKitCapability: Hashable, Sendable {
    var id: LiveRoomRowID
    var title: String
    var detail: String
    var symbolName: String
}

struct MicSeat: Identifiable, Hashable, Sendable {
    var id: String
    var nickname: String
    var role: String
    var level: Int
    var isSpeaking: Bool
    var isMuted: Bool
    var version: Int

    var refreshToken: String {
        "\(version)-\(isSpeaking)-\(isMuted)-\(level)"
    }
}

struct LiveMessage: Identifiable, Hashable, Sendable {
    var id: String
    var sender: String
    var text: String
    var tone: String
    var version: Int

    var refreshToken: String {
        "\(version)-\(tone)-\(text)"
    }
}

struct GiftItem: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var symbolName: String
    var price: Int
    var sentCount: Int
    var isSelected: Bool
    var version: Int

    var refreshToken: String {
        "\(version)-\(sentCount)-\(isSelected)"
    }
}

enum ModerationEventKind: String, Hashable, Sendable {
    case moderator = "Moderator"
    case flaggedMessage = "Flagged"
    case muted = "Muted"
    case topGifter = "Gift"
    case announcement = "Announcement"
    case userLeft = "Exit"
    case goalReached = "Goal"
}

struct ModerationEvent: Identifiable, Hashable, Sendable {
    var id: String
    var kind: ModerationEventKind
    var title: String
    var detail: String
    var isSelected: Bool
    var version: Int

    var refreshToken: String {
        "\(version)-\(isSelected)-\(title)-\(detail)"
    }
}

struct LiveRoomState: Hashable, Sendable {
    var roomName: String
    var hostName: String
    var viewerCount: Int
    var heat: Int
    var mode: String
    var statusVersion: Int
    var messageSequence: Int
    var selectedGiftID: String
    var isAPIGuideExpanded: Bool
    var activityFilter: RoomActivityFilter
    var pendingScrollMessageID: String?
    var micSeats: [MicSeat]
    var messages: [LiveMessage]
    var gifts: [GiftItem]
    var moderationEvents: [ModerationEvent]
    var diagnostics: ApplyDiagnostics

    static func sample() -> LiveRoomState {
        let gifts = [
            GiftItem(id: "rose", name: "Rose", symbolName: "seal.fill", price: 1, sentCount: 24, isSelected: false, version: 0),
            GiftItem(id: "spark", name: "Spark", symbolName: "sparkles", price: 6, sentCount: 12, isSelected: false, version: 0),
            GiftItem(id: "rocket", name: "Rocket", symbolName: "paperplane.fill", price: 30, sentCount: 5, isSelected: true, version: 1),
            GiftItem(id: "crown", name: "Crown", symbolName: "crown.fill", price: 88, sentCount: 2, isSelected: false, version: 0)
        ]

        return LiveRoomState(
            roomName: "Room Toolkit",
            hostName: "Alex",
            viewerCount: 1248,
            heat: 8932,
            mode: "LIVE",
            statusVersion: 1,
            messageSequence: 4,
            selectedGiftID: "rocket",
            isAPIGuideExpanded: true,
            activityFilter: .all,
            pendingScrollMessageID: nil,
            micSeats: [
                MicSeat(id: "host", nickname: "Alex", role: "Host", level: 48, isSpeaking: true, isMuted: false, version: 1),
                MicSeat(id: "guest-1", nickname: "Mia", role: "Moderator", level: 31, isSpeaking: false, isMuted: false, version: 0),
                MicSeat(id: "guest-2", nickname: "Daniel", role: "Speaker", level: 29, isSpeaking: false, isMuted: true, version: 0),
                MicSeat(id: "guest-3", nickname: "Sophie", role: "Top Gifter", level: 18, isSpeaking: false, isMuted: false, version: 0),
                MicSeat(id: "guest-4", nickname: "Michael", role: "Listener", level: 16, isSpeaking: false, isMuted: false, version: 0)
            ],
            messages: [
                LiveMessage(id: "msg-1", sender: "Emma", text: "Loving the new ListKit live demo!", tone: "hot", version: 0),
                LiveMessage(id: "msg-2", sender: "Daniel", text: "The diffable data source feels so smooth.", tone: "chat", version: 0),
                LiveMessage(id: "msg-3", sender: "Sophie", text: "Sent a Rocket", tone: "gift", version: 0),
                LiveMessage(id: "msg-4", sender: "Michael", text: "Swipe, select, context menu - all handles perfectly.", tone: "chat", version: 0)
            ],
            gifts: gifts,
            moderationEvents: [
                ModerationEvent(id: "mod-1", kind: .moderator, title: "Moderator joined", detail: "Mia - just now", isSelected: true, version: 1),
                ModerationEvent(id: "mod-2", kind: .flaggedMessage, title: "Message flagged", detail: "By Daniel - 1m ago", isSelected: false, version: 0),
                ModerationEvent(id: "mod-3", kind: .muted, title: "User muted", detail: "Chris - 2m ago", isSelected: true, version: 1),
                ModerationEvent(id: "mod-4", kind: .topGifter, title: "New top gifter", detail: "Sophie - 3m ago", isSelected: false, version: 0),
                ModerationEvent(id: "mod-5", kind: .announcement, title: "Announcement updated", detail: "Alex - 5m ago", isSelected: false, version: 0),
                ModerationEvent(id: "mod-6", kind: .userLeft, title: "User left", detail: "Kevin - 6m ago", isSelected: false, version: 0),
                ModerationEvent(id: "mod-7", kind: .goalReached, title: "Gift goal reached", detail: "Room - 8m ago", isSelected: false, version: 0)
            ],
            diagnostics: ApplyDiagnostics()
        )
    }
}
