// MARK: - Shared Apply Core

enum ListNodeRole: Hashable, Sendable {
    case row
    case supplementary
}

struct ListNodeSnapshot: Sendable {
    let identity: AnyListIdentity
    let refreshID: AnyListID?
    let refreshPolicy: RowRefreshPolicy
    let role: ListNodeRole
}

struct ListSectionSnapshot: Sendable {
    let sectionID: AnyListID
    let rows: [ListNodeSnapshot]
    let supplementaries: [ListNodeSnapshot]
}

struct ListApplyPlan {
    let shouldApplyDiffable: Bool
    let snapshotRefreshItems: [AnyListIdentity]
    let shouldRunVisibleRefresh: Bool
    let initialSummary: ListApplySummary
    let oldRowsByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let newRowsByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let oldSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let newSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot]

    func completedSummary(
        visibleRefreshCount: Int,
        visibleSupplementaryRefreshCount: Int
    ) -> ListApplySummary {
        ListApplySummary(
            insertedCount: initialSummary.insertedCount,
            deletedCount: initialSummary.deletedCount,
            keptCount: initialSummary.keptCount,
            refreshIDChangedCount: initialSummary.refreshIDChangedCount,
            snapshotRefreshCount: initialSummary.snapshotRefreshCount,
            visibleRefreshCount: visibleRefreshCount,
            supplementaryRefreshIDChangedCount: initialSummary.supplementaryRefreshIDChangedCount,
            visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount,
            diagnosticsIssues: initialSummary.diagnosticsIssues
        )
    }
}

enum ListApplyPlanner {
    static func makePlan(
        old oldSections: [ListSectionSnapshot],
        new newSections: [ListSectionSnapshot],
        options: ListApplyOptions,
        diagnosticsIssues: [ListDiagnosticsIssue]
    ) -> ListApplyPlan {
        let oldRows = oldSections.flatMap(\.rows)
        let newRows = newSections.flatMap(\.rows)
        let oldSupplementaries = oldSections.flatMap(\.supplementaries)
        let newSupplementaries = newSections.flatMap(\.supplementaries)
        let oldRowsByIdentity = lookup(from: oldRows)
        let newRowsByIdentity = lookup(from: newRows)
        let oldSupplementariesByIdentity = lookup(from: oldSupplementaries)
        let newSupplementariesByIdentity = lookup(from: newSupplementaries)

        let shouldApplyDiffable = !shouldStopBeforeDiffableApply(
            issues: diagnosticsIssues,
            options: options
        )
        let snapshotRefreshItems = shouldApplyDiffable
            ? itemsNeedingSnapshotRefresh(
                oldRowsByIdentity: oldRowsByIdentity,
                newRows: newRows,
                strategy: options.refreshStrategy
            )
            : []
        let initialSummary = makeSummary(
            oldRowsByIdentity: oldRowsByIdentity,
            newRowsByIdentity: newRowsByIdentity,
            oldSupplementariesByIdentity: oldSupplementariesByIdentity,
            newSupplementariesByIdentity: newSupplementariesByIdentity,
            snapshotRefreshItems: snapshotRefreshItems,
            visibleRefreshCount: 0,
            visibleSupplementaryRefreshCount: 0,
            diagnosticsIssues: diagnosticsIssues
        )

        return ListApplyPlan(
            shouldApplyDiffable: shouldApplyDiffable,
            snapshotRefreshItems: snapshotRefreshItems,
            shouldRunVisibleRefresh: shouldRunVisibleRefresh(strategy: options.refreshStrategy),
            initialSummary: initialSummary,
            oldRowsByIdentity: oldRowsByIdentity,
            newRowsByIdentity: newRowsByIdentity,
            oldSupplementariesByIdentity: oldSupplementariesByIdentity,
            newSupplementariesByIdentity: newSupplementariesByIdentity
        )
    }

    static func shouldRefreshVisibleRow(_ row: ListNodeSnapshot) -> Bool {
        switch row.refreshPolicy {
        case .automaticVisible, .alwaysVisible:
            return true
        case .whenRefreshIDChanges, .never:
            return false
        }
    }

    static func shouldRefreshVisibleSupplementary(
        _ supplementary: ListNodeSnapshot,
        oldSupplementary: ListNodeSnapshot
    ) -> Bool {
        switch supplementary.refreshPolicy {
        case .automaticVisible, .alwaysVisible:
            return true
        case .whenRefreshIDChanges:
            return oldSupplementary.refreshID != supplementary.refreshID
        case .never:
            return false
        }
    }

    private static func shouldStopBeforeDiffableApply(
        issues: [ListDiagnosticsIssue],
        options: ListApplyOptions
    ) -> Bool {
        guard !issues.isEmpty else { return false }

        switch options.diagnostics.mode {
        case .disabled:
            return false
        case .warning:
            return true
        case .assertion:
            assertionFailure(issues.map(\.message).joined(separator: "\n"))
            return true
        }
    }

    private static func itemsNeedingSnapshotRefresh(
        oldRowsByIdentity: [AnyListIdentity: ListNodeSnapshot],
        newRows: [ListNodeSnapshot],
        strategy: ListApplyRefreshStrategy
    ) -> [AnyListIdentity] {
        switch strategy {
        case .visibleOnly:
            return []
        case .forceReload:
            return newRows.compactMap { row in
                oldRowsByIdentity[row.identity] == nil ? nil : row.identity
            }
        case .automatic, .diffableOnly:
            break
        }

        return newRows.compactMap { row in
            guard
                let oldRow = oldRowsByIdentity[row.identity],
                row.refreshPolicy == .whenRefreshIDChanges,
                oldRow.refreshID != row.refreshID
            else { return nil }
            return row.identity
        }
    }

    private static func shouldRunVisibleRefresh(strategy: ListApplyRefreshStrategy) -> Bool {
        switch strategy {
        case .automatic, .visibleOnly:
            return true
        case .diffableOnly, .forceReload:
            return false
        }
    }

    private static func makeSummary(
        oldRowsByIdentity: [AnyListIdentity: ListNodeSnapshot],
        newRowsByIdentity: [AnyListIdentity: ListNodeSnapshot],
        oldSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot],
        newSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot],
        snapshotRefreshItems: [AnyListIdentity],
        visibleRefreshCount: Int,
        visibleSupplementaryRefreshCount: Int,
        diagnosticsIssues: [ListDiagnosticsIssue]
    ) -> ListApplySummary {
        let oldIDs = Set(oldRowsByIdentity.keys)
        let newIDs = Set(newRowsByIdentity.keys)
        let keptIDs = oldIDs.intersection(newIDs)
        let refreshIDChangedCount = keptIDs.reduce(into: 0) { count, identity in
            guard oldRowsByIdentity[identity]?.refreshID != newRowsByIdentity[identity]?.refreshID else { return }
            count += 1
        }

        let oldSupplementaryIDs = Set(oldSupplementariesByIdentity.keys)
        let newSupplementaryIDs = Set(newSupplementariesByIdentity.keys)
        let keptSupplementaryIDs = oldSupplementaryIDs.intersection(newSupplementaryIDs)
        let supplementaryRefreshIDChangedCount = keptSupplementaryIDs.reduce(into: 0) { count, identity in
            guard oldSupplementariesByIdentity[identity]?.refreshID != newSupplementariesByIdentity[identity]?.refreshID else { return }
            count += 1
        }

        return ListApplySummary(
            insertedCount: newIDs.subtracting(oldIDs).count,
            deletedCount: oldIDs.subtracting(newIDs).count,
            keptCount: keptIDs.count,
            refreshIDChangedCount: refreshIDChangedCount,
            snapshotRefreshCount: snapshotRefreshItems.count,
            visibleRefreshCount: visibleRefreshCount,
            supplementaryRefreshIDChangedCount: supplementaryRefreshIDChangedCount,
            visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount,
            diagnosticsIssues: diagnosticsIssues
        )
    }

    private static func lookup(from nodes: [ListNodeSnapshot]) -> [AnyListIdentity: ListNodeSnapshot] {
        nodes.reduce(into: [:]) { result, node in
            result[node.identity] = node
        }
    }
}

extension ListDiagnostics {
    static func validate(_ sections: [ListSectionSnapshot]) -> [ListDiagnosticsIssue] {
        var issues: [ListDiagnosticsIssue] = []
        var seenSections: Set<AnyListID> = []
        var seenRows: Set<AnyListIdentity> = []
        var seenSupplementaries: Set<AnyListIdentity> = []

        for section in sections {
            if !seenSections.insert(section.sectionID).inserted {
                issues.append(
                    ListDiagnosticsIssue(
                        kind: .duplicateSection,
                        message: "ListKit: duplicate section identity \(section.sectionID)"
                    )
                )
            }

            for row in section.rows where !seenRows.insert(row.identity).inserted {
                issues.append(
                    ListDiagnosticsIssue(
                        kind: .duplicateRow,
                        message: "ListKit: duplicate row identity in section \(section.sectionID), row \(row.identity.rowID)"
                    )
                )
            }

            for supplementary in section.supplementaries where !seenSupplementaries.insert(supplementary.identity).inserted {
                issues.append(
                    ListDiagnosticsIssue(
                        kind: .duplicateSupplementary,
                        message: "ListKit: duplicate supplementary identity in section \(section.sectionID)"
                    )
                )
            }
        }

        return issues
    }
}

enum ListApplyLogger {
    static func logDiagnostics(issues: [ListDiagnosticsIssue], options: ListApplyOptions) {
        #if DEBUG
        guard options.diagnostics.mode != .disabled else { return }
        for issue in issues {
            print(issue.message)
        }
        #endif
    }

    static func logApplySummary(
        _ summary: ListApplySummary,
        options: ListApplyOptions,
        prefix: String = "ListKit apply summary"
    ) {
        #if DEBUG
        guard options.diagnostics.logsApplySummary else { return }
        print(
            "\(prefix): inserted=\(summary.insertedCount), deleted=\(summary.deletedCount), kept=\(summary.keptCount), refreshIDChanged=\(summary.refreshIDChangedCount), snapshotRefresh=\(summary.snapshotRefreshCount), visibleRefresh=\(summary.visibleRefreshCount), supplementaryRefreshIDChanged=\(summary.supplementaryRefreshIDChangedCount), visibleSupplementaryRefresh=\(summary.visibleSupplementaryRefreshCount), diagnostics=\(summary.diagnosticsIssues.count)"
        )
        #endif
    }
}

@MainActor
final class ListEventRouter<Context> {
    private var handlers: [ObjectIdentifier: @MainActor (any ListEvent, Context) -> Void] = [:]

    func on<Event>(
        _ eventType: Event.Type = Event.self,
        handler: @escaping @MainActor (Event, Context) -> Void
    ) where Event: ListEvent {
        handlers[ObjectIdentifier(eventType)] = { event, context in
            guard let typedEvent = event as? Event else { return }
            handler(typedEvent, context)
        }
    }

    func dispatch(_ event: any ListEvent, context: Context) {
        handlers[ObjectIdentifier(type(of: event))]?(event, context)
    }
}
