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
    let changedSectionCount: Int
    let initialSummary: ListApplySummary
    let oldRowsByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let newRowsByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let oldSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot]
    let newSupplementariesByIdentity: [AnyListIdentity: ListNodeSnapshot]

    var hasSnapshotChanges: Bool {
        initialSummary.insertedSectionCount > 0
            || initialSummary.deletedSectionCount > 0
            || initialSummary.movedSectionCount > 0
            || initialSummary.insertedCount > 0
            || initialSummary.deletedCount > 0
            || initialSummary.movedCount > 0
            || initialSummary.snapshotRefreshCount > 0
    }

    func completedSummary(
        visibleRefreshCount: Int,
        visibleSupplementaryRefreshCount: Int,
        animation: ListAnimationSummary = ListAnimationSummary(completionState: .completed)
    ) -> ListApplySummary {
        ListApplySummary(
            insertedSectionCount: initialSummary.insertedSectionCount,
            deletedSectionCount: initialSummary.deletedSectionCount,
            movedSectionCount: initialSummary.movedSectionCount,
            keptSectionCount: initialSummary.keptSectionCount,
            insertedCount: initialSummary.insertedCount,
            deletedCount: initialSummary.deletedCount,
            movedCount: initialSummary.movedCount,
            keptCount: initialSummary.keptCount,
            refreshIDChangedCount: initialSummary.refreshIDChangedCount,
            snapshotRefreshCount: initialSummary.snapshotRefreshCount,
            visibleRefreshCount: visibleRefreshCount,
            supplementaryRefreshIDChangedCount: initialSummary.supplementaryRefreshIDChangedCount,
            visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount,
            diagnosticsIssues: initialSummary.diagnosticsIssues,
            animation: animation
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
        let movedCount = inferredRowMoveCount(old: oldSections, new: newSections)
        let sectionChanges = sectionChanges(old: oldSections, new: newSections)
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
            diagnosticsIssues: diagnosticsIssues,
            movedCount: movedCount,
            sectionChanges: sectionChanges
        )

        return ListApplyPlan(
            shouldApplyDiffable: shouldApplyDiffable,
            snapshotRefreshItems: snapshotRefreshItems,
            shouldRunVisibleRefresh: shouldRunVisibleRefresh(strategy: options.refreshStrategy),
            changedSectionCount: sectionChanges.changedCount,
            initialSummary: initialSummary,
            oldRowsByIdentity: oldRowsByIdentity,
            newRowsByIdentity: newRowsByIdentity,
            oldSupplementariesByIdentity: oldSupplementariesByIdentity,
            newSupplementariesByIdentity: newSupplementariesByIdentity
        )
    }

    static func shouldRefreshVisibleRow(
        _ row: ListNodeSnapshot,
        oldRow: ListNodeSnapshot,
        strategy: ListApplyRefreshStrategy
    ) -> Bool {
        switch row.refreshPolicy {
        case .automaticVisible:
            return row.refreshID == nil || oldRow.refreshID != row.refreshID
        case .alwaysVisible:
            return true
        case .whenRefreshIDChanges:
            return strategy == .visibleOnly && oldRow.refreshID != row.refreshID
        case .never:
            return false
        }
    }

    static func shouldRefreshVisibleSupplementary(
        _ supplementary: ListNodeSnapshot,
        oldSupplementary: ListNodeSnapshot
    ) -> Bool {
        switch supplementary.refreshPolicy {
        case .automaticVisible:
            return supplementary.refreshID == nil
                || oldSupplementary.refreshID != supplementary.refreshID
        case .alwaysVisible:
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
        diagnosticsIssues: [ListDiagnosticsIssue],
        movedCount: Int,
        sectionChanges: ListSectionChanges
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
            insertedSectionCount: sectionChanges.insertedCount,
            deletedSectionCount: sectionChanges.deletedCount,
            movedSectionCount: sectionChanges.movedCount,
            keptSectionCount: sectionChanges.keptCount,
            insertedCount: newIDs.subtracting(oldIDs).count,
            deletedCount: oldIDs.subtracting(newIDs).count,
            movedCount: movedCount,
            keptCount: keptIDs.count,
            refreshIDChangedCount: refreshIDChangedCount,
            snapshotRefreshCount: snapshotRefreshItems.count,
            visibleRefreshCount: visibleRefreshCount,
            supplementaryRefreshIDChangedCount: supplementaryRefreshIDChangedCount,
            visibleSupplementaryRefreshCount: visibleSupplementaryRefreshCount,
            diagnosticsIssues: diagnosticsIssues
        )
    }

    private static func inferredMovedIdentities<ID>(old: [ID], new: [ID]) -> Set<ID>
    where ID: Hashable {
        new.difference(from: old)
            .inferringMoves()
            .reduce(into: Set<ID>()) { identities, change in
                guard case .insert(_, let identity, associatedWith: .some) = change else { return }
                identities.insert(identity)
            }
    }

    private static func inferredRowMoveCount(
        old: [ListSectionSnapshot],
        new: [ListSectionSnapshot]
    ) -> Int {
        let oldRowsBySection = old.reduce(into: [AnyListID: [AnyListIdentity]]()) { result, section in
            result[section.sectionID] = section.rows.map(\.identity)
        }
        let newRowsBySection = new.reduce(into: [AnyListID: [AnyListIdentity]]()) { result, section in
            result[section.sectionID] = section.rows.map(\.identity)
        }
        return Set(oldRowsBySection.keys).intersection(newRowsBySection.keys).reduce(into: 0) { count, sectionID in
            count += inferredMovedIdentities(
                old: oldRowsBySection[sectionID] ?? [],
                new: newRowsBySection[sectionID] ?? []
            ).count
        }
    }

    private static func sectionChanges(
        old: [ListSectionSnapshot],
        new: [ListSectionSnapshot]
    ) -> ListSectionChanges {
        let oldIDs = old.map(\.sectionID)
        let newIDs = new.map(\.sectionID)
        let oldIDSet = Set(oldIDs)
        let newIDSet = Set(newIDs)
        let movedIDs = inferredMovedIdentities(old: oldIDs, new: newIDs)
        let oldFingerprints = sectionFingerprints(from: old)
        let newFingerprints = sectionFingerprints(from: new)
        let contentChangedIDs = Set(oldFingerprints.keys).union(newFingerprints.keys).filter { sectionID in
            oldFingerprints[sectionID] != newFingerprints[sectionID]
        }
        return ListSectionChanges(
            insertedCount: newIDSet.subtracting(oldIDSet).count,
            deletedCount: oldIDSet.subtracting(newIDSet).count,
            movedCount: movedIDs.count,
            keptCount: oldIDSet.intersection(newIDSet).count,
            changedCount: contentChangedIDs.union(movedIDs).count
        )
    }

    /// Diagnostics may intentionally stop an apply containing duplicate section IDs.
    /// Build the summary without trapping first so `.warning` can report and skip it.
    private static func sectionFingerprints(
        from sections: [ListSectionSnapshot]
    ) -> [AnyListID: ListSectionChangeFingerprint] {
        sections.reduce(into: [:]) { fingerprints, section in
            fingerprints[section.sectionID] = ListSectionChangeFingerprint(section: section)
        }
    }

    private static func lookup(from nodes: [ListNodeSnapshot]) -> [AnyListIdentity: ListNodeSnapshot] {
        nodes.reduce(into: [:]) { result, node in
            result[node.identity] = node
        }
    }
}

private struct ListSectionChangeFingerprint: Equatable {
    let rows: [ListNodeChangeFingerprint]
    let supplementaries: [ListNodeChangeFingerprint]

    init(section: ListSectionSnapshot) {
        rows = section.rows.map(ListNodeChangeFingerprint.init)
        supplementaries = section.supplementaries.map(ListNodeChangeFingerprint.init)
    }
}

private struct ListSectionChanges {
    let insertedCount: Int
    let deletedCount: Int
    let movedCount: Int
    let keptCount: Int
    let changedCount: Int
}

private struct ListNodeChangeFingerprint: Equatable {
    let identity: AnyListIdentity
    let refreshID: AnyListID?

    init(node: ListNodeSnapshot) {
        identity = node.identity
        refreshID = node.refreshID
    }
}

@MainActor
final class ListAnimationCompletionCoordinator {
    private var pendingCount = 1
    private let completion: @MainActor () -> Void

    init(completion: @escaping @MainActor () -> Void) {
        self.completion = completion
    }

    func enter() {
        pendingCount += 1
    }

    func leave() {
        pendingCount -= 1
        if pendingCount == 0 {
            completion()
        }
    }

    func finishScheduling() {
        leave()
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
            "\(prefix): sectionInserted=\(summary.insertedSectionCount), sectionDeleted=\(summary.deletedSectionCount), sectionMoved=\(summary.movedSectionCount), sectionKept=\(summary.keptSectionCount), inserted=\(summary.insertedCount), deleted=\(summary.deletedCount), moved=\(summary.movedCount), kept=\(summary.keptCount), refreshIDChanged=\(summary.refreshIDChangedCount), snapshotRefresh=\(summary.snapshotRefreshCount), visibleRefresh=\(summary.visibleRefreshCount), supplementaryRefreshIDChanged=\(summary.supplementaryRefreshIDChangedCount), visibleSupplementaryRefresh=\(summary.visibleSupplementaryRefreshCount), animation=\(summary.animation.completionState), snapshotAnimated=\(summary.animation.snapshotAnimated), outlineAnimated=\(summary.animation.outlineAnimatedSectionCount), contentTransitions=\(summary.animation.contentTransitionCount), layoutAnimated=\(summary.animation.layoutAnimated), scrollAnimated=\(summary.animation.scrollAnimated), anchorCompensation=\(summary.animation.anchorCompensation), reduceMotion=\(summary.animation.reduceMotionApplied), diagnostics=\(summary.diagnosticsIssues.count)"
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
