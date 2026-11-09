import UIKit

/// 标准 Row 自动生成的内部能力；不通过 data source dequeue，也不调用展示事件绑定器。
struct ListCellMeasurement {
    let makeCell: @MainActor () throws -> UICollectionViewCell
    let configure: @MainActor (UICollectionViewCell, ListContext) -> Void
}

@MainActor
final class ListCellMeasurementCache: NSObject {
    private struct Key: Hashable {
        let identity: AnyListIdentity
        let crossExtent: CGFloat
        let axis: ListAxis
        let indexPath: IndexPath
        let selected: Bool
    }
    private struct Entry {
        let version: AnyListID?
        let traits: UITraitCollection
        let direction: UIUserInterfaceLayoutDirection
        let extent: CGFloat
    }
    private var sizes: [Key: Entry] = [:]
    private var cells: [ObjectIdentifier: UICollectionViewCell] = [:]
    private let parent = UIViewController()
    private let host = UIViewController()

    override init() {
        super.init()
        parent.addChild(host)
        parent.view.addSubview(host.view)
        host.didMove(toParent: parent)
        NotificationCenter.default.addObserver(self, selector: #selector(clear),
            name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    @objc func clear() {
        sizes.removeAll()
        cells.removeAll()
        host.view.subviews.forEach { $0.removeFromSuperview() }
    }

    /// 只在接受新一轮 apply 后调用。无内容版本的 Row 每轮重新测量；移除的数据立即释放缓存。
    func synchronize(rows: [AnyListRow], reload: Bool) {
        if reload { clear(); return }
        let versions = Dictionary(rows.map { ($0.identity, $0.refreshID) }, uniquingKeysWith: { _, new in new })
        sizes = sizes.filter { key, entry in
            guard let version = versions[key.identity], let version else { return false }
            return entry.version == version
        }
        let types = Set(rows.map { $0.identity.presentationID })
        cells = cells.filter { types.contains($0.key) }
    }

    func extent(
        for row: AnyListRow, crossExtent: CGFloat, axis: ListAxis,
        context: ListContext, environment: any NSCollectionLayoutEnvironment
    ) throws -> CGFloat {
        guard let measurement = row.measurement else {
            throw ListWaterfallError("automatic measurement requires a typed Row; ProviderRow is unsupported")
        }
        let collection = context.collectionView
        let selected = row.isSelected ?? (collection.indexPathsForSelectedItems?.contains(context.indexPath) == true)
        let direction = collection.effectiveUserInterfaceLayoutDirection
        let traits = environment.traitCollection
        let key = Key(identity: row.identity, crossExtent: crossExtent, axis: axis,
            indexPath: context.indexPath, selected: selected)
        if let cached = sizes[key], cached.version == row.refreshID,
            cached.traits == traits, cached.direction == direction { return cached.extent }

        // 挂到真实 trait 层级中的隐藏容器，保证 iOS 15+ 的字体/方向环境传播。
        // 不注册、不 dequeue，不参与 data source 或展示生命周期。
        parent.view.isHidden = true
        parent.view.isUserInteractionEnabled = false
        collection.addSubview(parent.view)
        defer { parent.view.removeFromSuperview() }
        parent.setOverrideTraitCollection(traits, forChild: host)
        host.view.semanticContentAttribute = direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
        let cell: UICollectionViewCell
        if let existing = cells[row.identity.presentationID] {
            cell = existing
            cell.prepareForReuse()
        } else {
            var created: UICollectionViewCell?
            var failure: Error?
            traits.performAsCurrent {
                do { created = try measurement.makeCell() } catch { failure = error }
            }
            if let failure { throw failure }
            guard let created else { throw ListWaterfallError("could not create measurement cell") }
            cell = created
            cells[row.identity.presentationID] = cell
        }
        host.view.addSubview(cell)
        if #available(iOS 17.0, *) {
            parent.view.updateTraitsIfNeeded()
            host.view.updateTraitsIfNeeded()
            cell.updateTraitsIfNeeded()
        }
        defer {
            cell.prepareForReuse()
            cell.removeFromSuperview()
        }
        let vertical = axis == .vertical
        cell.bounds = CGRect(origin: .zero, size: vertical
            ? CGSize(width: crossExtent, height: 1000) : CGSize(width: 1000, height: crossExtent))
        cell.contentView.frame = cell.bounds
        cell.isSelected = selected
        cell.isHighlighted = false
        var fitted = CGSize.zero
        traits.performAsCurrent {
            measurement.configure(cell, context)
            cell.setNeedsUpdateConstraints()
            cell.updateConstraintsIfNeeded()
            fitted = cell.systemLayoutSizeFitting(
                vertical ? CGSize(width: crossExtent, height: 0) : CGSize(width: 0, height: crossExtent),
                withHorizontalFittingPriority: vertical ? .required : .fittingSizeLevel,
                verticalFittingPriority: vertical ? .fittingSizeLevel : .required)
        }
        let raw = vertical ? fitted.height : fitted.width
        let scale = max(1, traits.displayScale)
        let extent = ceil(raw * scale) / scale
        guard extent.isFinite, extent > 0 else {
            throw ListWaterfallError("Row \(row.identity) must provide a finite positive Auto Layout size")
        }
        // 防止连续窗口尺寸变化产生无限量历史宽度记录。
        if sizes.count >= 4096 { sizes.removeAll(keepingCapacity: true) }
        sizes[key] = Entry(version: row.refreshID, traits: traits, direction: direction, extent: extent)
        return extent
    }
}
