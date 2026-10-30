# Layout Lab 重构验证

日期：2026-10-29。改动范围是 Examples 的布局实验室、示例测试、使用说明；没有修改 ListKit 的布局实现。

## 环境与范围

- Xcode 27.1，iPhone 17 Pro Max 模拟器，iOS 26.5。
- Examples deployment target 为 iOS 15。编译成功不代表 iOS 15 运行时验证。
- 本轮未运行真机、iPad、旋转、RTL、大字号矩阵、iOS 15/16 运行时及整个应用的其他 UI 测试。
- 库代码未改，本轮未重复运行库测试；历史库验证见其他验证记录。

## 自动检查

示例单元测试覆盖配置和布局代码是否一致、场景与方向组合是否合法、尺寸模式与轨道组合、Row 内容/方向身份、混合 Section 的边界归属、数量切换、轨道上限，以及单元格长文本测量与跨方向复用。

Layout Lab UI 测试覆盖：

1. 自定义 boundary kind 在两个外层方向中的位置与尺寸。
2. 轨道模式、宽高比、240 pt 容器、单项及空内容。
3. Cards、Tags、Banner、Centered、2×3 在两个外层方向中的真实拖动。
4. Cards 起始停靠与 Centered 居中停靠。
5. 2×3 页停靠和尾组尺寸。
6. 修改尺寸、三层间距与分组后，展示代码和实际尺寸/间距一致；切换方向保留轨道选择。
7. 自适应内容更新后高度增长、同组统一高度，以及横向 2×3 的代码输出。

## 修复与失败记录

保留中间失败，避免把重试结果误认为首次通过：

- 第一轮测试编译缺少 geometry 的 scrollDirection 参数，已补齐。
- 第二轮发现 UIKit 菜单可访问性名称包含副标题，原测试按纯标题定位失败。改用标题前缀定位，没有放宽布局断言。
- 第二至第四轮发现增加内容后仍保留旧高度。单元格补充多行测量宽度与复用状态重置，并显式声明 Row 内容刷新需要 `.reconfigure(layout: .invalidate)`。独立测量测试与真实 UI 高度增长共同验证该路径。
- 完整测试后的截图复核发现：240 pt 横向容器的底部填充约束拉伸了说明文字区域。降低底部填充优先级，使预览紧随控件显示，并补上预览位置断言。
- 第三轮 Cards 的滚动等待超时，当时可访问性查询出现长时间重试。保留结果并在最终完整 UI 回归中重新验证同一条断言，没有增加重试或放宽判定。

中间结果包：`/tmp/listkit-layout-lab-second.xcresult`、`/tmp/listkit-layout-lab-third.xcresult`、`/tmp/listkit-layout-lab-fourth.xcresult`。日志使用同前缀的 `.log` 文件。测试失败时 Xcode 会继续收集 simulator diagnostics，结果包可能在测试结束数分钟后才完成写入。

## 最终结果

- 完整回归：**51 项示例单元测试 + 7 项 Layout Lab UI 测试，58/58 通过**，无跳过、无运行时警告。结果包：`/tmp/listkit-layout-lab-fifth.xcresult`。
- 控件说明文字调整后：51 项单元测试 + 参数联动 UI 测试，52/52 通过。结果包：`/tmp/listkit-layout-lab-final-copy.xcresult`。
- 最后修复容器位置后：**51 项单元测试 + 2 项受影响 UI 测试，53/53 通过**，包含容器收窄、空内容、代码/几何一致性与新增位置断言。结果包：`/tmp/listkit-layout-lab-final.xcresult`。此轮没有重复运行其余 5 项 UI 测试。
- `git diff --check` 通过；文档本地链接及截图路径检查通过。
- 截图已检查：自适应文字实际换行，固定轨道尺寸与间距吻合，240 pt 横向预览紧随上方控件显示。代码、纵向、横向截图来自最后一轮；自适应截图来自完整回归轮。

编译仍有 Xcode 的 AppIntents 提取提示，以及测试框架最低系统版本高于 deployment target 的链接提示；不据此声称旧系统运行时通过。实际截图及使用方式见 [Layout Lab](Layout-Lab.md)。
