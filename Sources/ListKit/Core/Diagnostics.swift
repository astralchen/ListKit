import UIKit

// MARK: - Diagnostics

/// 列表诊断发现的问题类型。
public enum ListDiagnosticsIssueKind: Equatable, Sendable {
    /// section id 重复。
    case duplicateSection
    /// row identity 重复。
    case duplicateRow
    /// supplementary identity 重复。
    case duplicateSupplementary
    /// layout 参数无效。
    case invalidLayout
    /// 同一个 section 内同 kind supplementary view 重复。
    case duplicateSupplementaryKind
    /// supplementary layout 配置冲突。
    case conflictingSupplementaryLayout
}

/// 一条 ListKit 诊断结果。
///
/// 适配器在提交差异快照前验证描述树，是否拦截问题由诊断模式决定。
/// 依赖容器尺寸或提供者结果的布局问题在布局解析时另行验证。
public struct ListDiagnosticsIssue: Equatable, Sendable {
    /// 问题分类，用于程序化筛选和测试断言。
    public let kind: ListDiagnosticsIssueKind
    /// 面向开发者的具体问题描述。
    public let message: String
}

/// 列表诊断发现问题时的处理策略。
public enum ListDiagnosticsMode: Equatable, Sendable {
    /// 不因描述树诊断而拦截快照提交，也不输出诊断日志。
    /// 仍会计算描述树诊断结果；独立的布局解析仍拒绝无效几何。
    case disabled
    /// 发现问题时跳过本次快照提交，并在 DEBUG 构建中输出警告。
    case warning
    /// 触发断言并阻止本次提交；关闭断言的构建仍跳过提交。
    case assertion
}

/// 列表结构诊断与更新日志的配置。
public struct ListDiagnosticsOptions: Sendable {
    /// 诊断问题的拦截与报告策略，默认使用警告模式。
    public var mode: ListDiagnosticsMode
    /// 是否允许在 DEBUG 构建中输出每次 apply 的 summary；还需设置启动参数 -ListKitLogApplySummary true。
    public var logsApplySummary: Bool

    /// 创建 列表结构诊断与更新日志的配置。
    ///
    /// - Parameters:
    ///   - mode: 列表诊断发现问题时的处理策略。
    ///   - logsApplySummary: 是否允许输出 apply summary 日志，仅在 DEBUG 构建且启动参数为 -ListKitLogApplySummary true 时生效。
    public init(mode: ListDiagnosticsMode = .warning, logsApplySummary: Bool = true) {
        self.mode = mode
        self.logsApplySummary = logsApplySummary
    }

    /// 关闭结构诊断拦截与日志输出的配置，不关闭诊断结果的计算。
    public static let disabled = ListDiagnosticsOptions(mode: .disabled, logsApplySummary: false)
    /// DEBUG 场景的默认配置：发现问题时警告，设置 -ListKitLogApplySummary true 后输出 apply summary。
    public static let debugDefault = ListDiagnosticsOptions()
}

/// 用于验证列表内容与布局声明的诊断工具。
public enum ListDiagnostics {
    /// 校验 section 描述树中的重复 identity 和布局冲突。
    ///
    /// - Parameter sections: 当前将要 apply 的 section 描述树。
    /// - Returns: 诊断问题列表；无问题时返回空数组。
    @MainActor public static func validate<SectionID>(
        _ sections: [ListSection<SectionID>]
    ) -> [ListDiagnosticsIssue] where SectionID: Hashable & Sendable {
        var issues = validate(
            sections.map { section in
                ListSectionSnapshot(
                    sectionID: AnyListID(section.id),
                    rows: section.rows.map { row in
                        ListNodeSnapshot(
                            identity: row.identity,
                            refreshID: row.refreshID,
                            refreshRule: .row(row.refreshRule),
                            role: .row
                        )
                    },
                    supplementaries: section.supplementaries.map { supplementary in
                        ListNodeSnapshot(
                            identity: supplementary.identity,
                            refreshID: supplementary.refreshID,
                            refreshRule: .supplementary(supplementary.refreshRule),
                            role: .supplementary
                        )
                    }
                )
            })

        for section in sections {
            let sectionID = AnyListID(section.id)
            issues.append(contentsOf: duplicateSupplementaryKindIssues(in: section, sectionID: sectionID))
            if case .builtIn(let layout) = section.layoutSource {
                issues += invalidSectionLayoutIssues(layout, sectionID: sectionID)
                if layout.uiKitListLayout != nil && layout.options.items.contains(where: { rule in
                    section.supplementaries.contains { $0.kind == rule.kind }
                }) {
                    issues.append(
                        .init(
                            kind: .invalidLayout,
                            message: "ListKit: UIKitListLayout does not support item supplementaries"))
                }
            }
            let options = section.layoutSource.options ?? ListSectionLayoutOptions(decorations: [])
            let custom: Bool
            if case .custom = section.layoutSource { custom = true } else { custom = false }
            issues += options.issues(in: section, custom: custom)
        }

        // 注册作用于整个 UICollectionViewLayout；逻辑 kind 可以在不同 Section 中复用。
        var decorationTypes: [String: ObjectIdentifier] = [:]
        for section in sections {
            for decoration in section.decorations {
                guard let type = decoration.registrationKey else { continue }
                if let existing = decorationTypes[decoration.elementKind], existing != type {
                    issues.append(
                        .init(
                            kind: .invalidLayout,
                            message: "ListKit: decoration elementKind \(decoration.elementKind) has conflicting view registrations"))
                }
                decorationTypes[decoration.elementKind] = type
            }
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
                message:
                    "ListKit: section \(sectionID) declares \(count) supplementary views for kind \(kind); each kind must identify one declaration within a section"
            )
        }
    }

    static func invalidSectionLayoutIssues(
        _ layout: ListSectionLayout,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] {
        switch layout {
        case .gridConfiguration(let grid):
            return grid.validationErrors.map {
                .init(kind: .invalidLayout, message: "ListKit: section \(sectionID): " + $0)
            }
        case .uiKitListConfiguration(let list):
            return list.headerTopPadding.map {
                invalidSpacingIssues($0, label: "headerTopPadding", sectionID: sectionID)
            } ?? []
        }
    }

    private static func invalidSpacingIssues(
        _ spacing: CGFloat,
        label: String,
        sectionID: AnyListID
    ) -> [ListDiagnosticsIssue] {
        guard !spacing.isFinite || spacing < 0 else { return [] }
        return [
            ListDiagnosticsIssue(
                kind: .invalidLayout,
                message: "ListKit: \(label) in section \(sectionID) must be >= 0, got \(spacing)"
            )
        ]
    }
}
