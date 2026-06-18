# ListKit Layout DSL Design

## Architecture

Layout DSL 继续遵循 ListKit 的描述树思路：section 保存轻量、可 Hash 的布局描述，adapter 提供 helper 把描述转换为 `UICollectionViewCompositionalLayout`。adapter 不自动设置 `collectionView.collectionViewLayout`，页面仍显式控制 layout 生命周期。

## Public Types

- `ListSectionLayout`: section 主布局描述，包含 `.list(...)`、`.grid(...)`、`.horizontal(...)`。
- `ListCustomSectionLayout`: 自定义 compositional layout 逃生口，使用 `.layout(.custom(id:) { ... })` 绑定到 section。
- `ListLayoutDimension`: 映射到 `NSCollectionLayoutDimension`，支持 absolute、estimated、fractionalWidth、fractionalHeight。
- `ListLayoutInsets`: 使用 top/leading/bottom/trailing 保存 spacing，避免业务层直接依赖不可 Hash 的 UIKit inset 类型。
- `ListSupplementaryLayout`: 描述 supplementary kind、placement、width、height、zIndex。
- `ListSupplementaryPlacement`: `.boundary(...)` 或 `.itemSupplementary(...)`。
- `ListSupplementaryAnchor`: top、bottom、leading、trailing 及四角位置。

## Data Flow

1. 页面通过 `ListSection.layout(.grid(...))` 或 `.layout(.horizontal(...))` 写入 `sectionLayout`。
2. 页面通过 `.header`、`.footer`、`.supplementary` 声明 supplementary view。
3. 页面可选调用 `.boundarySupplementaryLayout` 或 `.itemSupplementaryLayout` 覆盖 supplementary placement。
4. `CollectionListAdapter.makeCompositionalLayout(fallback:)` 在 layout provider 中读取当前 sections；自定义闭包 layout 优先，旧 `layoutID` 才走 fallback。
5. `ListSection.makeCompositionalLayoutSection()` 生成 `NSCollectionLayoutSection`，并附加 boundary/item supplementary。

## Supplementary Defaults

- header 默认 top boundary，height `.estimated(44)`。
- footer 默认 bottom boundary，height `.estimated(44)`。
- custom kind 默认 top boundary，height `.estimated(44)`。
- `.stickyHeader()` 只影响 header boundary。
- item-level supplementary 默认对 section 内每个 item 生效；单 item 条件显示留给后续 Row 级 supplementary API。

## Diagnostics

`ListDiagnostics.validate` 追加布局检查：

- grid columns 小于 1 时输出 invalid layout issue。
- 同一个 supplementary kind 从 boundary 切到 item 或反向切换时输出 placement conflict issue。
- diagnostics 只报告问题，布局生成仍尽量兜底，避免调试阶段直接崩溃。
