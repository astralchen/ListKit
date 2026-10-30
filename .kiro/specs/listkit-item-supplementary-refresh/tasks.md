# Section 整体布局与补充视图

当前实现契约见 [Layout API](../../../Documentation/Layout-API.md)。

- layout 返回完整值，公共修饰保持主体类型；Section inset 只有一个来源。
- boundarySupplementaries 与 itemSupplementaries 分开建模，通过实际 kind 关联 SectionSupplementary 内容与 UIKit 注册；decoration 通过逻辑 kind 关联注册，并解析实际 elementKind。
- decorationItems 为布局集合，decorations 为 SectionDecoration 注册集合；重复修饰替换集合，显式空集合清除几何。
- Supplementary 内容不携带尺寸/位置；事件使用内容 onTap，刷新继续支持可见视图重配及 reloadSection。
- 环境选择返回完整值，自定义 provider 明确边界和 inset 所有权；布局签名覆盖几何与关联变化。
- 不保留通用 Header/Footer、旧背景 DSL 或迁移包装层；UITableView 的 TableHeader/TableFooter 保留。
- 测试覆盖编译正反例、状态更新、真实 UIKit 几何与 LayoutLab 交互；验证状态见 Documentation/Layout-Validation.md。
