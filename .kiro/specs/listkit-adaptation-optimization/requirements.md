# ListKit Adaptation Optimization Requirements

## Goal

让 Rebirth 的长期列表写法向 ListKit DSL 收敛，优先修复 adapter 被绕过、delegate 被覆盖、identity 不稳定等正确性问题。

## Requirements

1. 已接入 `CollectionListAdapter` 的页面不得再直接覆盖 `collectionView.delegate` 或 `collectionView.dataSource`。
2. 高频实时页面必须保留原行为：
   - 麦位页保留麦位定位、布局切换、发言动画可见刷新。
   - 公屏页保留自动滚底、可见消息布局刷新、链接点击。
   - 工具面板保留 PK 状态和倒计时刷新。
3. `ListCellProvider` / `ListProviderSection` 只能作为迁移兼容层，标准页面应使用 `ListSection`、`Row(model:id:cell:)`、`.refreshID`、`.refreshPolicy` 和 `.onSelect`。
4. Row identity 必须稳定，禁止使用 `UUID()` 参与 ListKit row/section identity 或 hash。
5. `collectionView.lk.*` 是 reusable helper 主入口，未命名空间兼容方法只用于迁移期。
6. Supplementary tap 安装不得移除业务 view 自带的 tap 手势。
