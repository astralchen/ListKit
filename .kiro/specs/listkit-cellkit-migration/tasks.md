# ListKit CellKit Migration Tasks

- [x] Task 1: 新增 Kiro requirements/design/tasks。
- [x] Task 2: 补齐 ListKit UIKit reusable helpers、separator layout、迁移测试。
- [x] Task 3: 迁移 Explore/Search 模块和仅依赖注册 helper 的页面。
- [x] Task 4: 迁移 Own/Profile/Setting 模块。
- [x] Task 5: 迁移 Community 模块。
- [x] Task 6: 迁移 Channel/Room/Gift/Ranking 模块。
- [x] Task 7: 移除 Rebirth 工程和文档中的 CellKit 引用。
- [x] Task 8: 运行残留搜索、ListKit 测试、Rebirth workspace build。

## Verification

```bash
xcodebuild -scheme ListKit -destination 'id=714D7775-9CE5-4F6A-8036-C0B93E45FA04' test
xcodebuild -scheme ListKit -destination 'generic/platform=iOS Simulator' build
xcodebuild -workspace Rebirth.xcworkspace -scheme Rebirth -destination 'generic/platform=iOS Simulator' build CODE_SIGNING_ALLOWED=NO
rg -n '(^import CellKit$|\bCellKit\b|SharePackage/CellKit|\bCollectionViewController\b|\bCollectionViewCellItem\b|\bCollectionViewSupplementary\b|\bAnyCollectionViewCellItem\b|\bCollectionViewSectionType\b|\bCellItemsBuilder\b|\bSectionsBuilder\b)' Rebirth Rebirth.xcodeproj/project.pbxproj AGENTS.md CLAUDE.md
```
