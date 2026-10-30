import UIKit

/// 有限数据的先测量后分页实验；不使用 ListKit，不接管 UIKit 滚动。
final class StablePagingProbeViewController: UIViewController, UICollectionViewDataSource {
    private let arguments = ProcessInfo.processInfo.arguments
    private var vertical: Bool { arguments.contains("-StableVertical") }
    private var envelopeOnly: Bool { arguments.contains("-StableEnvelopeOnly") }
    private var restorePage: Bool { arguments.contains("-StableRestorePage") }
    private let captions: [CGFloat] = [18,34,22,28,40,26,20,30,38,24,28,32,42,20,24,30,36,44]
    private var identityProbe: Bool { arguments.contains("-StableIdentity") }
    private var rtl: Bool { arguments.contains("-StableRTL") }
    private var deferredAnchor: Bool { arguments.contains("-StableDeferredAnchor") }
    private var tailInset: Bool { arguments.contains("-StableTailInset") }
    private var measuredEstimate: Bool { arguments.contains("-StableMeasuredEstimate") }
    private var logicalLeft: Bool { arguments.contains("-StableLogicalLeft") }
    private var badges: Bool { arguments.contains("-StableBadges") }
    private lazy var ids = Array(0..<(identityProbe ? 19 : 42))
    private var itemCount: Int { ids.count }
    private var lastRestoration: [String: Any] = [:]
    private var invalidBadgeRequests = 0
    private var tappedBadgeID: Int?
    private var nextInsertedID = 100
    private var revision = 0
    private var narrow = false
    private var crossExtent: CGFloat { narrow ? 170 : 210 }
    private var viewport: CGFloat { narrow ? 300 : 340 }
    private var trackExtent: CGFloat { (crossExtent - 10) / 2 }
    private var measured: [CGFloat] = []
    private var slots: [CGFloat] = []
    private var pageExtent: CGFloat = 0
    private var generation = 0
    private var collection: UICollectionView!
    private var width: NSLayoutConstraint!
    private var height: NSLayoutConstraint!
    private let state = UILabel()
    private let traceView = UILabel()
    private var events: [[String: Any]] = []
    private var offset = CGPoint.zero
    private var fits = 0
    private var providerCalls = 0
    private let epoch = CACurrentMediaTime()
    private var evidenceURL: URL!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Measured native paging"
        view.backgroundColor = .systemBackground
        view.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StablePagingProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        evidenceURL = folder.appendingPathComponent("\(vertical ? "vertical" : "horizontal")-\(envelopeOnly ? "envelope" : "slots")-\(restorePage ? "restore" : "raw").json")
        resolveMeasurements()
        collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collection.dataSource = self
        collection.semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        collection.contentInsetAdjustmentBehavior = .never
        collection.backgroundColor = .secondarySystemBackground
        collection.accessibilityIdentifier = "stable-collection"
        collection.register(StablePagingProbeCell.self, forCellWithReuseIdentifier: "cell")
        for line in 0..<3 {
            collection.register(StablePagingProbeBadge.self, forSupplementaryViewOfKind: "stable.badge.\(line)",
                                withReuseIdentifier: "badge")
        }
        collection.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collection)
        let snapshot = button("Snapshot", "stable-snapshot", #selector(snapshot))
        let update = button("Update content", "stable-update", #selector(updateContent))
        let resize = button("Resize container", "stable-resize", #selector(resizeContainer))
        state.accessibilityIdentifier = "stable-state"
        state.isAccessibilityElement = true
        state.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        state.numberOfLines = 2
        state.text = "Measured sizes ready"
        traceView.accessibilityIdentifier = "stable-trace"
        traceView.isAccessibilityElement = true
        traceView.text = "Read-only native trace"
        traceView.font = .systemFont(ofSize: 10)
        var controlViews: [UIView] = [snapshot, update, resize]
        if identityProbe {
            for entries: [(String, String, Selector)] in [
                [("Insert", "identity-insert", #selector(insertItems)), ("Delete anchor", "identity-delete", #selector(deleteAnchor)),
                 ("Reorder", "identity-reorder", #selector(reorderItems))],
                [("Trim tail", "identity-trim", #selector(trimTail)), ("One item", "identity-one", #selector(oneItem)),
                 ("Clear", "identity-clear", #selector(clearItems))]] {
                let row = UIStackView(arrangedSubviews: entries.map { button($0.0, $0.1, $0.2) })
                row.distribution = .fillEqually
                controlViews.append(row)
            }
        }
        controlViews += [state, traceView]
        let controls = UIStackView(arrangedSubviews: controlViews)
        controls.axis = .vertical
        controls.spacing = 4
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        width = collection.widthAnchor.constraint(equalToConstant: vertical ? crossExtent : viewport)
        height = collection.heightAnchor.constraint(equalToConstant: vertical ? viewport : crossExtent)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 4),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            collection.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            collection.centerXAnchor.constraint(equalTo: view.centerXAnchor), width, height,
        ])
        record("launch", ["system": UIDevice.current.systemVersion, "vertical": vertical,
                          "envelopeOnly": envelopeOnly, "restorePage": restorePage])
    }
    private func button(_ title: String, _ id: String, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = id
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    private func caption(_ item: Int) -> CGFloat { captions[ids[item] % captions.count] + CGFloat(revision * 24) }

    /// 独立测量实例不调用真实 dequeue 或业务 provider；相同内容约束也用于显示 cell。
    private func resolveMeasurements() {
        generation += 1
        let measurementCell = StablePagingProbeCell(frame: .zero)
        measured = (0..<itemCount).map { item in
            measurementCell.configure(item: item, caption: caption(item), vertical: vertical)
            let size = measurementCell.measure(cross: trackExtent)
            return vertical ? size.height : size.width
        }
        slots = (0..<3).map { line in
            (0..<itemCount).filter { ($0 / 2) % 3 == line }.map { measured[$0] }.max() ?? 44
        }
        let actualPages = stride(from: 0, to: itemCount, by: 6).map { first in
            (0..<3).reduce(CGFloat(20)) { sum, line in
                let start = min(first + line * 2, itemCount)
                let indices = start..<min(start + 2, itemCount)
                return sum + (indices.isEmpty ? 0 : indices.map { measured[$0] }.max()!)
            }
        }
        pageExtent = envelopeOnly ? (actualPages.max() ?? 152) : slots.reduce(20, +)
        record("measurement", ["generation": generation, "revision": revision, "track": trackExtent,
                               "measured": measured, "slots": slots, "naturalPages": actualPages,
                               "pageExtent": pageExtent, "viewport": viewport])
    }
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = vertical ? .horizontal : .vertical
        // 本次布局使用不可变的测量快照，不在 provider/滚动过程中修改尺寸。
        let page = pageExtent, lineExtents = slots, cross = crossExtent, track = trackExtent, viewExtent = viewport
        let resolvedGeneration = generation
        return StablePagingDirectionalLayout(sectionProvider: { [weak self] _, _ in
            guard let self else { return nil }
            providerCalls += 1
            record("provider", ["generation": resolvedGeneration, "pageExtent": page])
            @MainActor func size(_ main: NSCollectionLayoutDimension, _ cross: CGFloat) -> NSCollectionLayoutSize {
                .init(widthDimension: vertical ? .absolute(cross) : main,
                      heightDimension: vertical ? main : .absolute(cross))
            }
            let units = (0..<3).map { line in
                let items = (0..<2).map { _ in
                    let badge = NSCollectionLayoutSupplementaryItem(
                        layoutSize: .init(widthDimension: .absolute(18), heightDimension: .absolute(18)),
                        elementKind: "stable.badge.\(line)",
                        containerAnchor: .init(edges: [.top, .trailing]),
                        itemAnchor: .init(edges: [.top, .trailing]))
                    badge.zIndex = 2
                    return NSCollectionLayoutItem(layoutSize: size(.estimated(measuredEstimate ? lineExtents[line] : 44), track),
                                                  supplementaryItems: badges ? [badge] : [])
                }
                let unitSize = size(envelopeOnly ? .estimated(44) : .absolute(lineExtents[line]), cross)
                let group: NSCollectionLayoutGroup
                if badges {
                    if #available(iOS 16.0, *) {
                        group = vertical ? .horizontal(layoutSize: unitSize, repeatingSubitem: items[0], count: 2)
                                         : .vertical(layoutSize: unitSize, repeatingSubitem: items[0], count: 2)
                    } else {
                        group = vertical ? .horizontal(layoutSize: unitSize, subitem: items[0], count: 2)
                                         : .vertical(layoutSize: unitSize, subitem: items[0], count: 2)
                    }
                } else {
                    group = vertical ? .horizontal(layoutSize: unitSize, subitems: items)
                                     : .vertical(layoutSize: unitSize, subitems: items)
                }
                group.interItemSpacing = .fixed(10)
                return group
            }
            let pageSize = size(.absolute(page), cross)
            let group = vertical ? NSCollectionLayoutGroup.vertical(layoutSize: pageSize, subitems: units)
                                 : NSCollectionLayoutGroup.horizontal(layoutSize: pageSize, subitems: units)
            group.interItemSpacing = .fixed(10)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 20
            section.orthogonalScrollingBehavior = .groupPaging
            // 明确采用“末页也按页首对齐”的实验契约；空白属于 section 尾部，不增加虚假 item。
            if tailInset {
                let reserve = max(0, viewExtent - page)
                section.contentInsets = vertical ? .init(top: 0, leading: 0, bottom: reserve, trailing: 0)
                                                 : .init(top: 0, leading: 0, bottom: 0, trailing: reserve)
            }
            section.visibleItemsInvalidationHandler = { [weak self] items, offset, _ in
                guard let self else { return }
                self.offset = offset
                record("visible", ["offset": [offset.x, offset.y], "generation": resolvedGeneration,
                    "items": items.map { ["item": $0.indexPath.item,
                        "frame": [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height]] }])
            }
            return section
        }, configuration: configuration)
    }
    @objc private func updateContent() {
        revision = revision == 0 ? 1 : 0
        rebuild(reason: "content")
    }
    @objc private func resizeContainer() {
        narrow.toggle()
        rebuild(reason: "container")
    }
    /// 用屏幕中的 line 起点找当前页；不假定 RTL offset 的符号或原点。
    private func currentPage() -> Int {
        guard itemCount > 0, let collection else { return 0 }
        if !identityProbe { return max(0, min((itemCount - 1) / 6,
            Int(((vertical ? offset.y : offset.x) / (pageExtent + 20)).rounded()))) }
        let bounds = collection.convert(collection.bounds, to: nil)
        let edge = vertical ? bounds.minY : rtl ? bounds.maxX : bounds.minX
        let candidates = collection.indexPathsForVisibleItems.compactMap { path -> (Int, CGFloat)? in
            guard let cell = collection.cellForItem(at: path) else { return nil }
            let frame = cell.convert(cell.bounds, to: nil)
            let line = (path.item / 2) % 3
            let prefix = slots.prefix(line).reduce(0, +) + CGFloat(line) * 10
            let leading = vertical ? frame.minY - prefix : rtl ? frame.maxX + prefix : frame.minX - prefix
            return (path.item / 6, abs(leading - edge))
        }
        return candidates.min { $0.1 < $1.1 }?.0 ?? 0
    }
    @objc private func insertItems() {
        rebuild(reason: "insert") {
            ids.insert(contentsOf: Array(nextInsertedID..<(nextInsertedID + 3)), at: 0)
            nextInsertedID += 3
        }
    }
    @objc private func deleteAnchor() {
        let index = min(max(0, currentPage() * 6), max(0, itemCount - 1))
        rebuild(reason: "delete-anchor") { if !ids.isEmpty { ids.remove(at: index) } }
    }
    @objc private func reorderItems() {
        let index = min(max(0, currentPage() * 6), max(0, itemCount - 1))
        rebuild(reason: "reorder") {
            guard !ids.isEmpty else { return }
            let anchor = ids.remove(at: index)
            ids.reverse()
            ids.append(anchor)
        }
    }
    @objc private func trimTail() { rebuild(reason: "trim-tail") { if !ids.isEmpty { ids.removeLast() } } }
    @objc private func oneItem() {
        let id = ids.isEmpty ? 0 : ids[min(currentPage() * 6, itemCount - 1)]
        rebuild(reason: "one-item") { ids = [id] }
    }
    @objc private func clearItems() { rebuild(reason: "clear") { ids.removeAll() } }

    private func rebuild(reason: String, mutation: () -> Void = {}) {
        let oldIDs = ids
        let oldIndex = min(max(0, currentPage() * 6), max(0, oldIDs.count - 1))
        let anchorID = oldIDs.isEmpty ? nil : oldIDs[oldIndex]
        record("update-begin", ["reason": reason, "offset": [offset.x, offset.y],
                               "anchorID": anchorID as Any? ?? NSNull(), "oldIDs": oldIDs])
        mutation()
        var resolved = anchorID.flatMap { ids.contains($0) ? $0 : nil }
        var fallback = "same"
        if resolved == nil {
            resolved = oldIDs.dropFirst(oldIndex + 1).first { ids.contains($0) }
            fallback = "successor"
        }
        if resolved == nil {
            resolved = oldIDs.prefix(oldIndex).reversed().first { ids.contains($0) }
            fallback = "predecessor"
        }
        if resolved == nil { resolved = ids.first; fallback = resolved == nil ? "empty" : "first" }
        let resolvedIndex = resolved.flatMap { ids.firstIndex(of: $0) }
        let pageStart = resolvedIndex.map { ($0 / 6) * 6 }
        lastRestoration = ["reason": reason, "anchorID": anchorID as Any? ?? NSNull(),
                           "resolvedID": resolved as Any? ?? NSNull(), "fallback": fallback,
                           "pageStart": pageStart as Any? ?? NSNull(), "oldIDs": oldIDs]
        resolveMeasurements()
        width.constant = vertical ? crossExtent : viewport
        height.constant = vertical ? viewport : crossExtent
        view.layoutIfNeeded()
        collection.reloadData()
        collection.setCollectionViewLayout(makeLayout(), animated: false)
        collection.layoutIfNeeded()
        if restorePage, let pageStart {
            let restore = { [weak self, generation] in
                guard let self, self.generation == generation else { return }
                collection.layoutIfNeeded()
                // .left 对照用于启用 layout flipping 的 RTL；实际停靠用屏幕右边缘独立验收。
                // .right 和延后恢复仍可通过启动参数保留为失败对照，不是每次滚动后的纠偏。
                collection.scrollToItem(at: IndexPath(item: pageStart, section: 0),
                    at: vertical ? .top : (rtl && !logicalLeft) ? .right : .left, animated: false)
                collection.layoutIfNeeded()
                record("public-anchor-restoration", lastRestoration)
                snapshot()
            }
            if deferredAnchor { DispatchQueue.main.async(execute: restore) } else { restore() }
        }
        record("update-end", ["reason": reason, "offset": [offset.x, offset.y]])
        snapshot()
    }
    @objc private func snapshot() {
        collection.layoutIfNeeded()
        let frames = (0..<itemCount).compactMap { item -> [String: Any]? in
            guard let attr = collection.layoutAttributesForItem(at: IndexPath(item: item, section: 0)) else { return nil }
            return ["item": item, "frame": [attr.frame.minX, attr.frame.minY, attr.frame.width, attr.frame.height]]
        }
        let value: [String: Any] = ["vertical": vertical, "envelopeOnly": envelopeOnly,
            "revision": revision, "narrow": narrow, "generation": generation, "restorePage": restorePage,
            "offset": [offset.x, offset.y], "pageExtent": pageExtent, "stride": pageExtent + 20,
            "track": trackExtent, "viewport": viewport, "tailReserve": tailInset ? max(0, viewport - pageExtent) : 0,
            "measured": measured, "slots": slots,
            "fits": fits, "providers": providerCalls, "frames": frames,
            "visible": collection.indexPathsForVisibleItems.map(\.item).sorted(),
            "ids": ids, "currentPage": currentPage(), "rtl": rtl, "badges": badges, "deferredAnchor": deferredAnchor, "tailInset": tailInset, "logicalLeft": logicalLeft, "measuredEstimate": measuredEstimate,
            "restoration": lastRestoration, "badgeTapID": tappedBadgeID as Any? ?? NSNull(),
            "badgeViews": badgeSnapshots(), "invalidBadgeRequests": invalidBadgeRequests]
        state.accessibilityValue = json(value)
        state.text = "g\(generation) · page \(pageExtent) · track \(trackExtent) · \(envelopeOnly ? "envelope" : "slots")"
        record("snapshot", value)
        let trace = json(events)
        traceView.accessibilityValue = trace
        try? trace.write(to: evidenceURL, atomically: true, encoding: .utf8)
    }
    private func record(_ name: String, _ values: [String: Any]) {
        var event = values
        event["event"] = name
        event["time"] = CACurrentMediaTime() - epoch
        events.append(event)
    }
    private func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { itemCount }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! StablePagingProbeCell
        cell.configure(item: ids[indexPath.item], caption: caption(indexPath.item), vertical: vertical)
        cell.accessibilityIdentifier = "stable-item-\(indexPath.item)"
        cell.accessibilityValue = "id:\(ids[indexPath.item])"
        cell.onFit = { [weak self] size in
            guard let self else { return }
            fits += 1
            record("fit", ["generation": generation, "item": indexPath.item, "size": [size.width, size.height]])
        }
        return cell
    }
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String,
                        at indexPath: IndexPath) -> UICollectionReusableView {
        let line = Int(kind.split(separator: ".").last!)!
        let item = (indexPath.item / 2) * 6 + line * 2 + indexPath.item % 2
        let badge = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "badge", for: indexPath) as! StablePagingProbeBadge
        if !ids.indices.contains(item) {
            invalidBadgeRequests += 1
            record("invalid-badge-request", ["item": item, "count": ids.count, "kind": kind])
        }
        let id = ids.indices.contains(item) ? ids[item] : -1
        badge.configure(id: id) { [weak self] in
            self?.tappedBadgeID = id
            self?.record("badge-tap", ["id": id, "itemAtConfiguration": item])
            self?.snapshot()
        }
        return badge
    }
    private func badgeSnapshots() -> [[String: Any]] {
        guard badges else { return [] }
        return collection.indexPathsForVisibleItems.compactMap { path in
            let line = (path.item / 2) % 3
            let kind = "stable.badge.\(line)"
            let physical = IndexPath(item: (path.item / 6) * 2 + path.item % 2, section: 0)
            guard let badge = collection.supplementaryView(forElementKind: kind, at: physical) as? StablePagingProbeBadge,
                  let cell = collection.cellForItem(at: path) else { return nil }
            let b = badge.convert(badge.bounds, to: nil), c = cell.convert(cell.bounds, to: nil)
            return ["item": path.item, "id": badge.itemID, "kind": kind, "physicalItem": physical.item,
                    "badge": [b.minX, b.minY, b.width, b.height], "cell": [c.minX,c.minY,c.width,c.height]]
        }
    }

}

private final class StablePagingProbeCell: UICollectionViewCell {
    private let tile = UILabel()
    private let captionLabel = UILabel()
    private var contentConstraints: [NSLayoutConstraint] = []
    private var vertical = false
    var onFit: ((CGSize) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        for label in [tile, captionLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.textAlignment = .center
            label.textColor = .white
            label.font = .systemFont(ofSize: 12)
            contentView.addSubview(label)
        }
        contentView.layer.cornerRadius = 7
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(item: Int, caption: CGFloat, vertical: Bool) {
        self.vertical = vertical
        tile.text = "\(item)"
        captionLabel.text = "\(Int(caption))"
        contentView.backgroundColor = [.systemBlue, .systemOrange, .systemPurple][(item / 6) % 3]
        NSLayoutConstraint.deactivate(contentConstraints)
        if vertical {
            contentConstraints = [tile.topAnchor.constraint(equalTo: contentView.topAnchor),
                tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                tile.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                tile.heightAnchor.constraint(equalTo: tile.widthAnchor, multiplier: 0.35),
                captionLabel.topAnchor.constraint(equalTo: tile.bottomAnchor),
                captionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                captionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                captionLabel.heightAnchor.constraint(equalToConstant: caption),
                captionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)]
        } else {
            contentConstraints = [tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                tile.topAnchor.constraint(equalTo: contentView.topAnchor),
                tile.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                tile.widthAnchor.constraint(equalTo: tile.heightAnchor, multiplier: 0.35),
                captionLabel.leadingAnchor.constraint(equalTo: tile.trailingAnchor),
                captionLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
                captionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                captionLabel.widthAnchor.constraint(equalToConstant: caption),
                captionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)]
        }
        NSLayoutConstraint.activate(contentConstraints)
    }
    func measure(cross: CGFloat) -> CGSize {
        let target = CGSize(width: vertical ? cross : 0, height: vertical ? 0 : cross)
        return contentView.systemLayoutSizeFitting(target,
            withHorizontalFittingPriority: vertical ? .required : .fittingSizeLevel,
            verticalFittingPriority: vertical ? .fittingSizeLevel : .required)
    }
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        attributes.size = measure(cross: vertical ? layoutAttributes.size.width : layoutAttributes.size.height)
        onFit?(attributes.size)
        return attributes
    }
}

private final class StablePagingDirectionalLayout: UICollectionViewCompositionalLayout {
    override var flipsHorizontallyInOppositeLayoutDirection: Bool { true }
    override var developmentLayoutDirection: UIUserInterfaceLayoutDirection { .leftToRight }
}
private final class StablePagingProbeBadge: UICollectionReusableView {
    private let label = UILabel()
    private var action: (() -> Void)?
    private(set) var itemID = -1
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemRed
        layer.cornerRadius = 9
        label.font = .systemFont(ofSize: 8)
        label.textColor = .white
        label.textAlignment = .center
        label.frame = bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(id: Int, action: @escaping () -> Void) {
        itemID = id
        self.action = action
        label.text = String(id)
        accessibilityIdentifier = "stable-badge-\(id)"
        accessibilityLabel = "Badge \(id)"
    }
    @objc private func tap() { action?() }
}
