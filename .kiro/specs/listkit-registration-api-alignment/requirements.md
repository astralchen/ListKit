# ListKit Registration API Alignment Requirements

## Summary

ListKit should expose modern UICollectionView registration helpers in ListKit's own `.lk` namespace while keeping the existing declarative DSL unchanged. The helpers are intended for hand-written data sources and provider escape hatches, not for normal `Row`, `Header`, `Footer`, or `SectionSupplementary` usage.

## Requirements

- WHEN a page uses standard ListKit DSL THE SYSTEM SHALL keep the current `Row(... cell:)`, `Header(...)`, `Footer(...)`, and `SectionSupplementary(...)` APIs unchanged.
- WHEN collection code needs a `UICollectionView.CellRegistration` THE SYSTEM SHALL provide a ListKit-named helper from `collectionView.lk`.
- WHEN collection code needs a `UICollectionView.SupplementaryRegistration` THE SYSTEM SHALL provide a ListKit-named helper from `collectionView.lk`.
- WHEN a same-name nib exists for the registered reusable type THE SYSTEM SHALL use the nib-backed UIKit registration initializer; otherwise it SHALL use class-backed registration.
- WHEN adding these helpers THE SYSTEM SHALL NOT add old CellKit-style `UICollectionView.CellRegistration.create(...)` or `UICollectionView.SupplementaryRegistration.create(...)` APIs.
- WHEN table code uses ListKit THE SYSTEM SHALL keep `tableView.lk.register/dequeue` and `tableView.lk.registerHeaderFooter/dequeueHeaderFooter` as the table registration surface.
- WHEN implementing registration logic THE SYSTEM SHALL share nib lookup behavior across cell, supplementary, decoration, and registration helper paths.

## Validation

- ListKit tests cover class fallback for the new cell and supplementary registration helpers.
- Existing table reusable tests continue to pass without API changes.
- The ListKit scheme builds for iOS Simulator.
