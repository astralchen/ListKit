# ListKit Conditional Layout Metadata Design

## Layout Metadata Signature

`CollectionListAdapter` 在 apply 前后生成 `[ListSectionLayoutSignature]`。signature 只描述布局相关信息，不包含 row model 或 refreshID。

signature 字段：

- section id 和顺序
- `layoutID`、`sectionLayout`、`customSectionLayout.id`
- resolved supplementary layout 列表和 supplementary identity 列表
- sticky header 和 selection mode 中会影响 layout 的字段
- background decoration kind、contentInsets、zIndex

当新旧 signature 不一致时，adapter 在 diffable apply completion 里调用 `collectionView.collectionViewLayout.invalidateLayout()`。

## Conditional Supplementary Builder

`ListSection` 提供多 trailing-closure initializer，让 section layout、supplementary 和 background 声明接近 SwiftUI `Section`：

```swift
ListSection(.main) {
    Row(...)
} layout: {
    if isGrid {
        GridLayout(columns: 2, spacing: 12)
    } else {
        ListLayout(spacing: 8)
    }
} header: {
    if showHeader {
        Header(TitleHeaderView.self, id: "title") { view, _ in
            view.titleLabel.text = title
        }
        .layout(height: .estimated(44), pinned: isPinned)
    }
} footer: {
    if showFooter {
        Footer(FooterView.self, id: "footer") { view, _ in
            view.configure()
        }
    }
} supplementaries: {
    if showBadge {
        SectionSupplementary("badge", BadgeView.self, id: "badge") { view, _ in
            view.configure()
        }
        .layout(alignment: .topTrailing, width: .absolute(64), height: .absolute(28))
    }
} supplementaryLayouts: {
    if isPinned {
        BoundarySupplementaryLayout(
            kind: UICollectionView.elementKindSectionHeader,
            height: .absolute(36),
            pinned: true
        )
    }
}
```

`ListSectionSupplementaryBuilder` 支持 `if`、`if/else`、`for`、数组和空分支。builder 元素携带 optional `ListSupplementaryLayout`，所以 header/footer 的高度、pinning、自定义 supplementary placement 可以和 view 声明保持在同一个代码块里。

`ListSectionLayoutBuilder` 支持 `ListLayout(...)`、`GridLayout(...)`、`HorizontalLayout(...)` 和 `ListCustomSectionLayout.custom(...)`。`ListSupplementaryLayoutBuilder` 支持 `SupplementaryLayout(...)`、`BoundarySupplementaryLayout(...)`、`ItemSupplementaryLayout(...)`。旧 `.layout(...)`、`.supplementaryLayout(...)`、`.boundarySupplementaryLayout(...)`、`.itemSupplementaryLayout(...)` modifier 保留为固定配置和迁移兼容入口，不在 README 主路径中优先展示。

`headerIf`、`footerIf`、`supplementaryIf` 这类条件参数 API 已清理；条件统一写在 builder 的 `if` 分支里，避免 API 面同时存在 UIKit modifier 风格和 SwiftUI builder 风格。

## Background Decoration

新增 `ListBackgroundDecoration`：

- `kind`
- `contentInsets`
- `zIndex`
- typed view registration closure（仅 typed API 有）
- Hashable signature 不比较 closure，只比较 kind、contentInsets、zIndex 和 typed view key

`background:` 使用独立 builder，和 header/footer 的条件表达保持一致：

```swift
ListSection(.main) {
    Row(...)
} background: {
    if showBackground {
        BackgroundDecoration(
            GroupBackgroundView.self,
            contentInsets: .init(top: 8, leading: 16, bottom: 8, trailing: 16)
        )
    }
}
```

raw kind 用 `BackgroundDecoration(kind:contentInsets:zIndex:)`；固定背景仍保留 `.backgroundDecoration(...)` modifier 作为简写。

`ListSection.makeCompositionalLayoutSection()` 会在现有 decoration items 后追加 background decoration item，避免覆盖 custom layout 里已有 decoration。

## Registration

`CollectionListAdapter` 在 rebuild lookup tables 或创建 compositional layout 时，对 typed background decoration 执行 `layout.registerDecorationView(View.self, forKind:)`。raw kind API 不注册 view，适合业务已在 custom layout 中手动注册的场景。
