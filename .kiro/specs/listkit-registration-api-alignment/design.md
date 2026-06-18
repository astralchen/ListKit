# ListKit Registration API Alignment Design

## API Shape

New helpers live on `ListKitCollectionViewNamespace`:

```swift
collectionView.lk.cellRegistration(UserCell.self) { cell, indexPath, user in
    cell.configure(user)
}

collectionView.lk.supplementaryRegistration(TitleHeaderView.self, ofKind: UICollectionView.elementKindSectionHeader) { view, kind, indexPath in
    view.titleLabel.text = "Users"
}
```

The helper names follow existing ListKit namespace style. They do not use `create`, and they do not extend UIKit's nested registration types.

## DSL Integration

`Row`, `Header`, `Footer`, and `SectionSupplementary` keep their existing public syntax and internal register/dequeue flow. This preserves ListKit's ownership of `ListContext`, visible refresh, provider rows, and migration bridges. The new registration helpers are available for hand-written collection data sources and provider escape hatches that want UIKit registration objects while still using ListKit's nib/class lookup convention.

## Reusable Internals

`CollectionReusable.swift` owns a private reusable metadata helper that derives:

- the ListKit reuse identifier from `ReusableView.listReuseIdentifier`
- the bundle from `Bundle(for:)`
- an optional same-name `UINib`

Existing cell, supplementary, and decoration registration paths use this helper, and the new registration helpers use it as well. This keeps nib detection consistent without changing existing public behavior.

## UITableView

UITableView does not receive a registration-object API because the current UIKit SDK does not expose a matching `UITableView.CellRegistration` or header/footer registration type. Table DSL continues to use the existing `tableView.lk` register/dequeue namespace.
