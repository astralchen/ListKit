import UIKit

/// 有限数据的先测量后分页实验；不使用 ListKit，不接管 UIKit 滚动。
final class StablePagingProbeViewController: UIViewController, UICollectionViewDataSource {
    private let arguments = ProcessInfo.processInfo.arguments
    private var vertical: Bool { arguments.contains("-StableVertical") }
    private var envelopeOnly: Bool { arguments.contains("-StableEnvelopeOnly") }
    private let captions: [CGFloat] = [18,34,22,28,40,26,20,30,38,24,28,32,42,20,24,30,36,44]
    private let itemCount = 42
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
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StablePagingProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        evidenceURL = folder.appendingPathComponent("\(vertical ? "vertical" : "horizontal")-\(envelopeOnly ? "envelope" : "slots").json")
        resolveMeasurements()
        collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collection.dataSource = self
        collection.contentInsetAdjustmentBehavior = .never
        collection.backgroundColor = .secondarySystemBackground
        collection.accessibilityIdentifier = "stable-collection"
        collection.register(StablePagingProbeCell.self, forCellWithReuseIdentifier: "cell")
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
        let controls = UIStackView(arrangedSubviews: [snapshot, update, resize, state, traceView])
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
                          "envelopeOnly": envelopeOnly])
    }
    private func button(_ title: String, _ id: String, _ action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = id
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }
    private func caption(_ item: Int) -> CGFloat { captions[item % captions.count] + CGFloat(revision * 24) }

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
            (0..<itemCount).filter { ($0 / 2) % 3 == line }.map { measured[$0] }.max()!
        }
        let actualPages = stride(from: 0, to: itemCount, by: 6).map { first in
            (0..<3).reduce(CGFloat(20)) { sum, line in
                sum + max(measured[first + line * 2], measured[first + line * 2 + 1])
            }
        }
        pageExtent = envelopeOnly ? actualPages.max()! : slots.reduce(20, +)
        record("measurement", ["generation": generation, "revision": revision, "track": trackExtent,
                               "measured": measured, "slots": slots, "naturalPages": actualPages,
                               "pageExtent": pageExtent, "viewport": viewport])
    }
    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = vertical ? .horizontal : .vertical
        // 本次布局使用不可变的测量快照，不在 provider/滚动过程中修改尺寸。
        let page = pageExtent, lineExtents = slots, cross = crossExtent, track = trackExtent
        return UICollectionViewCompositionalLayout(sectionProvider: { [weak self] _, _ in
            guard let self else { return nil }
            providerCalls += 1
            record("provider", ["generation": generation, "pageExtent": page])
            @MainActor func size(_ main: NSCollectionLayoutDimension, _ cross: CGFloat) -> NSCollectionLayoutSize {
                .init(widthDimension: vertical ? .absolute(cross) : main,
                      heightDimension: vertical ? main : .absolute(cross))
            }
            let units = (0..<3).map { line in
                let items = (0..<2).map { _ in
                    NSCollectionLayoutItem(layoutSize: size(.estimated(44), track))
                }
                let unitSize = size(envelopeOnly ? .estimated(44) : .absolute(lineExtents[line]), cross)
                let group = vertical ? NSCollectionLayoutGroup.horizontal(layoutSize: unitSize, subitems: items)
                                     : NSCollectionLayoutGroup.vertical(layoutSize: unitSize, subitems: items)
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
            section.visibleItemsInvalidationHandler = { [weak self] items, offset, _ in
                guard let self else { return }
                self.offset = offset
                record("visible", ["offset": [offset.x, offset.y], "generation": generation,
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
    private func rebuild(reason: String) {
        record("update-begin", ["reason": reason, "offset": [offset.x, offset.y]])
        resolveMeasurements()
        width.constant = vertical ? crossExtent : viewport
        height.constant = vertical ? viewport : crossExtent
        view.layoutIfNeeded()
        collection.reloadData()
        collection.setCollectionViewLayout(makeLayout(), animated: false)
        collection.layoutIfNeeded()
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
            "revision": revision, "narrow": narrow, "generation": generation,
            "offset": [offset.x, offset.y], "pageExtent": pageExtent, "stride": pageExtent + 20,
            "track": trackExtent, "viewport": viewport, "measured": measured, "slots": slots,
            "fits": fits, "providers": providerCalls, "frames": frames,
            "visible": collection.indexPathsForVisibleItems.map(\.item).sorted()]
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
        cell.configure(item: indexPath.item, caption: caption(indexPath.item), vertical: vertical)
        cell.accessibilityIdentifier = "stable-item-\(indexPath.item)"
        cell.onFit = { [weak self] size in
            guard let self else { return }
            fits += 1
            record("fit", ["generation": generation, "item": indexPath.item, "size": [size.width, size.height]])
        }
        return cell
    }
}

private final class StablePagingProbeCell: UICollectionViewCell {
    private let tile = UILabel()
    private let captionLabel = UILabel()
    private var constraints: [NSLayoutConstraint] = []
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
        NSLayoutConstraint.deactivate(constraints)
        if vertical {
            constraints = [tile.topAnchor.constraint(equalTo: contentView.topAnchor),
                tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                tile.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                tile.heightAnchor.constraint(equalTo: tile.widthAnchor, multiplier: 0.35),
                captionLabel.topAnchor.constraint(equalTo: tile.bottomAnchor),
                captionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                captionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
                captionLabel.heightAnchor.constraint(equalToConstant: caption),
                captionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)]
        } else {
            constraints = [tile.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
                tile.topAnchor.constraint(equalTo: contentView.topAnchor),
                tile.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                tile.widthAnchor.constraint(equalTo: tile.heightAnchor, multiplier: 0.35),
                captionLabel.leadingAnchor.constraint(equalTo: tile.trailingAnchor),
                captionLabel.topAnchor.constraint(equalTo: contentView.topAnchor),
                captionLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
                captionLabel.widthAnchor.constraint(equalToConstant: caption),
                captionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor)]
        }
        NSLayoutConstraint.activate(constraints)
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
