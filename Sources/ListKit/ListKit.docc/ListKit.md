# ``ListKit``

用声明式描述树驱动 UIKit Collection View 与 Table View。

ListKit 将 Section、Row、Supplementary 的展示 identity 与内容刷新分开建模，并统一处理
diffable snapshot、可见内容配置、布局重测量、滚动、动画、取消和完成时序。

## Topics

### 构建列表

- ``ListSection``
- ``Row``
- ``RowGroup``
- ``TableSection``
- ``TableRow``
- ``TableRowGroup``

### 声明刷新

- ``ListRefreshTrigger``
- ``ListRefreshScope``
- ``ListRefreshLayoutPolicy``
- ``ListRowRefreshAction``
- ``ListRowRefreshRule``
- ``ListSupplementaryRefreshAction``
- ``ListSupplementaryRefreshRule``

### Collection 布局

- ``ListCompositionalLayoutConfiguration``
- ``ListContentInsetsReference``
- ``ListLayoutScrollDirection``
- <doc:Layout-Inset-Coordination>

### 提交与观测

- ``ListApplyOptions``
- ``ListTransaction``
- ``ListApplySummary``
- ``ListRefreshSummary``
- ``ListRefreshMetrics``
- <doc:Refresh-System-Migration>
