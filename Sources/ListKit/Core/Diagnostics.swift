import UIKit

// MARK: - Diagnostics

/// diagnostics 发现的问题类型。
public enum ListDiagnosticsIssueKind: Equatable, Sendable {
    /// section id 重复。
    case duplicateSection
    /// row identity 重复。
    case duplicateRow
    /// supplementary identity 重复。
    case duplicateSupplementary
    /// layout 参数无效。
    case invalidLayout
    /// supplementary layout 找不到同 kind 的 supplementary view。
    case orphanSupplementaryLayout
    /// 同一个 section 内同 kind supplementary view 重复。
    case duplicateSupplementaryKind
    /// supplementary layout 配置冲突。
    case conflictingSupplementaryLayout
    /// legacy layout id 没有被 compositional layout fallback 解析。
    case unresolvedLayoutID
}

/// 一条 ListKit 诊断结果。
///
/// - Important: 诊断在 diffable apply 前执行。这样重复 identity 会先被 ListKit 捕获，
/// 而不是等 `UICollectionViewDiffableDataSource` 用更隐晦的异常崩溃。
public struct ListDiagnosticsIssue: Equatable, Sendable {
    public let kind: ListDiagnosticsIssueKind
    public let message: String
}

/// diagnostics 处理方式。
public enum ListDiagnosticsMode: Equatable, Sendable {
    /// 不拦截问题，直接交给 diffable。
    case disabled
    /// 打印问题并跳过本次 diffable apply。
    case warning
    /// 触发 assertion。
    case assertion
}

/// diagnostics 配置。
public struct ListDiagnosticsOptions: Sendable {
    public var mode: ListDiagnosticsMode
    public var logsApplySummary: Bool

    /// 创建 diagnostics 配置。
    ///
    /// - Parameters:
    ///   - mode: diagnostics 处理方式。
    ///   - logsApplySummary: 是否输出 apply summary 日志。
    public init(mode: ListDiagnosticsMode = .warning, logsApplySummary: Bool = true) {
        self.mode = mode
        self.logsApplySummary = logsApplySummary
    }

    public static let disabled = ListDiagnosticsOptions(mode: .disabled, logsApplySummary: false)
    public static let debugDefault = ListDiagnosticsOptions()
}

/// ListKit 诊断入口。
public enum ListDiagnostics {
    /// 校验 section 描述树中的重复 identity 和布局冲突。
    ///
    /// - Parameter sections: 当前将要 apply 的 section 描述树。
    /// - Returns: 诊断问题列表；无问题时返回空数组。
    @MainActor public static func validate<SectionID>(
        _ sections: [ListSection<SectionID>]
    ) -> [ListDiagnosticsIssue] where SectionID: Hashable & Sendable {
        var issues = validate(sections.map { section in
            ListSectionSnapshot(
                sectionID: AnyListID(section.id),
                rows: section.rows.map { row in
                    ListNodeSnapshot(
                        identity: row.identity,
                        refreshID: row.refreshID,
                        refreshPolicy: row.refreshPolicy,
                        role: .row
                    )
                },
                supplementaries: section.supplementaries.map { supplementary in
                    ListNodeSnapshot(
                        identity: supplementary.identity,
                        refreshID: supplementary.refreshID,
                        refreshPolicy: supplementary.refreshPolicy,
                        role: .supplementary
                    )
                }
            )
        })

        for section in sections {
            let sectionID = AnyListID(section.id)
            issues.append(contentsOf: duplicateSupplementaryKindIssues(in: section, sectionID: sectionID))
            issues.append(contentsOf: orphanSupplementaryLayoutIssues(in: section, sectionID: sectionID))
            if let sectionLayout = section.sectionLayout {
                issues.append(contentsOf: invalidSectionLayoutIssues(sectionLayout, sectionID: sectionID))
            }
            for supplementaryLayout in section.supplementaryLayouts.values {
                issues.append(contentsOf: invalidSupplementaryLayoutIssues(supplementaryLayout, sectionID: sectionID))
            }

            issues.append(contentsOf: section.layoutDiagnostics)
        }

        return issues
    }

    private static func duplicateSupplementaryKindIssues<SectionID>(
        in section: ListSection<SectionID>,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] where SectionID: Hashable & Sendable {
        var kindCounts: [String: Int] = [:]
        for supplementary in section.supplementaries {
            kindCounts[supplementary.kind, default: 0] += 1
        }

        return kindCounts.compactMap { kind, count in
            guard count > 1 else { return nil }
            return ListDiagnosticsIssue(
                kind: .duplicateSupplementaryKind,
                message: "ListKit: section \(sectionID) declares \(count) supplementary views for kind \(kind); adapter lookup is kind + section, so the last one wins"
            )
        }
    }

    private static func orphanSupplementaryLayoutIssues<SectionID>(
        in section: ListSection<SectionID>,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] where SectionID: Hashable & Sendable {
        let supplementaryKinds = Set(section.supplementaries.map(\.kind))

        return section.supplementaryLayouts.values.compactMap { layout in
            guard !supplementaryKinds.contains(layout.kind) else { return nil }
            return ListDiagnosticsIssue(
                kind: .orphanSupplementaryLayout,
                message: "ListKit: section \(sectionID) has layout for supplementary kind \(layout.kind), but no matching supplementary view"
            )
        }
    }

    private static func invalidSectionLayoutIssues(
        _ layout: ListSectionLayout,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] {
        switch layout {
        case .listConfiguration(let list):
            return invalidDimensionIssues(list.itemHeight, label: "list itemHeight", sectionID: sectionID)
                + invalidSpacingIssues(list.spacing, label: "list spacing", sectionID: sectionID)
        case .gridConfiguration(let grid):
            var issues: [ListDiagnosticsIssue] = []
            if grid.columns < 1 {
                issues.append(
                    ListDiagnosticsIssue(
                        kind: .invalidLayout,
                        message: "ListKit: grid layout in section \(sectionID) requires columns >= 1, got \(grid.columns)"
                    )
                )
            }
            issues.append(contentsOf: invalidDimensionIssues(grid.itemHeight, label: "grid itemHeight", sectionID: sectionID))
            issues.append(contentsOf: invalidSpacingIssues(grid.spacing, label: "grid spacing", sectionID: sectionID))
            return issues
        case .horizontalConfiguration(let horizontal):
            return invalidDimensionIssues(horizontal.itemWidth, label: "horizontal itemWidth", sectionID: sectionID)
                + invalidDimensionIssues(horizontal.itemHeight, label: "horizontal itemHeight", sectionID: sectionID)
                + invalidSpacingIssues(horizontal.spacing, label: "horizontal spacing", sectionID: sectionID)
        case .uiKitListConfiguration:
            return []
        }
    }

    private static func invalidSupplementaryLayoutIssues(
        _ layout: ListSupplementaryLayout,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] {
        invalidDimensionIssues(layout.width, label: "supplementary \(layout.kind) width", sectionID: sectionID)
            + invalidDimensionIssues(layout.height, label: "supplementary \(layout.kind) height", sectionID: sectionID)
    }

    private static func invalidDimensionIssues(
        _ dimension: ListLayoutDimension,
        label: String,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] {
        let value = dimension.rawValueForDiagnostics
        guard value <= 0 else { return [] }
        return [
            ListDiagnosticsIssue(
                kind: .invalidLayout,
                message: "ListKit: \(label) in section \(sectionID) must be > 0, got \(value)"
            )
        ]
    }

    private static func invalidSpacingIssues(
        _ spacing: CGFloat,
        label: String,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] {
        guard spacing < 0 else { return [] }
        return [
            ListDiagnosticsIssue(
                kind: .invalidLayout,
                message: "ListKit: \(label) in section \(sectionID) must be >= 0, got \(spacing)"
            )
        ]
    }
}

private extension ListLayoutDimension {
    var rawValueForDiagnostics: CGFloat {
        switch self {
        case .absolute(let value), .estimated(let value), .fractionalWidth(let value), .fractionalHeight(let value):
            return value
        }
    }
}
