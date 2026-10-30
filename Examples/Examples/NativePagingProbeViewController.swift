import UIKit

/// 独立 UIKit 实验：不使用 ListKit adapter，不写入 offset，也不接管正交 scroll view。
final class NativePagingProbeViewController: UIViewController, UICollectionViewDataSource {
    private let arguments = ProcessInfo.processInfo.arguments
    private var vertical: Bool { arguments.contains("-ProbeVertical") }
    private var single: Bool { arguments.contains("-ProbeSingle") }
    private var fixed: Bool { arguments.contains("-ProbeFixed") }
    private var mode: String {
        guard let index = arguments.firstIndex(of: "-ProbeMode"), arguments.indices.contains(index + 1) else { return "baseline" }
        return arguments[index + 1]
    }
    private let extents: [CGFloat] = [40, 100, 60, 70, 110, 90, 50, 80, 90, 100, 60, 70,
                                     120, 60, 70, 40, 90, 100, 60, 80, 100, 70, 90, 60,
                                     90, 110, 70, 80, 60, 100]
    private var collection: UICollectionView!
    private let state = UILabel()
    private let traceView = UILabel()
    private var events: [[String: Any]] = []
    private var offset = CGPoint.zero
    private var providers = 0
    private var fits = 0
    private var interventionCount = 0
    private let startTime = CACurrentMediaTime()
    private var evidenceURL: URL!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Native paging probe"
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NativePagingProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        evidenceURL = directory.appendingPathComponent("\(mode)-\(vertical ? "vertical" : "horizontal")-\(single ? "single" : fixed ? "fixed" : "nested").json")
        collection = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collection.dataSource = self
        collection.backgroundColor = .secondarySystemBackground
        collection.contentInsetAdjustmentBehavior = .never
        collection.accessibilityIdentifier = "probe-collection"
        collection.register(NativePagingProbeCell.self, forCellWithReuseIdentifier: "cell")
        collection.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collection)
        let snapshot = UIButton(type: .system)
        snapshot.setTitle("Snapshot", for: .normal)
        snapshot.accessibilityIdentifier = "probe-snapshot"
        snapshot.addTarget(self, action: #selector(takeSnapshot), for: .touchUpInside)
        let intervention = UIButton(type: .system)
        intervention.setTitle("Apply \(mode)", for: .normal)
        intervention.accessibilityIdentifier = "probe-intervention"
        intervention.addTarget(self, action: #selector(intervene), for: .touchUpInside)
        state.accessibilityIdentifier = "probe-state"
        state.isAccessibilityElement = true
        state.text = "Use Snapshot to inspect geometry"
        state.numberOfLines = 3
        state.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
        traceView.accessibilityIdentifier = "probe-trace"
        traceView.isAccessibilityElement = true
        traceView.text = "Native event trace"
        traceView.font = .systemFont(ofSize: 10)
        let controls = UIStackView(arrangedSubviews: [snapshot, intervention, state, traceView])
        controls.axis = .vertical
        controls.spacing = 6
        controls.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            collection.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 16),
            collection.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            collection.widthAnchor.constraint(equalToConstant: vertical ? 210 : 340),
            collection.heightAnchor.constraint(equalToConstant: vertical ? 340 : 210),
        ])
        record("launch", ["mode": mode, "vertical": vertical, "single": single, "fixed": fixed,
                          "system": UIDevice.current.systemVersion])
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        configuration.scrollDirection = vertical ? .horizontal : .vertical
        return UICollectionViewCompositionalLayout(sectionProvider: { [weak self] _, _ in
            guard let self else { return nil }
            providers += 1
            record("provider", ["count": providers])
            let lineCount = single ? 1 : 3
            let trackCount = single ? 1 : 2
            let cross: CGFloat = single ? 210 : 100
            @MainActor func size(_ main: NSCollectionLayoutDimension, _ cross: CGFloat) -> NSCollectionLayoutSize {
                .init(widthDimension: vertical ? .absolute(cross) : main,
                      heightDimension: vertical ? main : .absolute(cross))
            }
            let units = (0..<lineCount).map { _ in
                let items = (0..<trackCount).map { _ in
                    NSCollectionLayoutItem(layoutSize: size(fixed ? .absolute(100) : .estimated(44), cross))
                }
                let unitSize = size(fixed ? .absolute(100) : .estimated(44), 210)
                let unit = vertical
                    ? NSCollectionLayoutGroup.horizontal(layoutSize: unitSize, subitems: items)
                    : NSCollectionLayoutGroup.vertical(layoutSize: unitSize, subitems: items)
                unit.interItemSpacing = .fixed(10)
                return unit
            }
            let group: NSCollectionLayoutGroup
            if single { group = units[0] }
            else {
                let groupSize = size(fixed ? .absolute(320) : .estimated(152), 210)
                group = vertical ? .vertical(layoutSize: groupSize, subitems: units)
                                 : .horizontal(layoutSize: groupSize, subitems: units)
                group.interItemSpacing = .fixed(10)
            }
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 20
            section.orthogonalScrollingBehavior = .groupPaging
            section.visibleItemsInvalidationHandler = { [weak self] items, offset, _ in
                guard let self else { return }
                self.offset = offset
                record("visible", ["offset": [offset.x, offset.y], "items": items.map {
                    ["item": $0.indexPath.item, "frame": [$0.frame.minX, $0.frame.minY, $0.frame.width, $0.frame.height]]
                }])
            }
            return section
        }, configuration: configuration)
    }

    @objc private func intervene() {
        interventionCount += 1
        record("intervention-begin", ["mode": mode, "offset": [offset.x, offset.y]])
        switch mode {
        case "invalidate": collection.collectionViewLayout.invalidateLayout()
        case "full": collection.collectionViewLayout.invalidateLayout(with: NativePagingFullInvalidation())
        case "rebuild": collection.setCollectionViewLayout(makeLayout(), animated: false)
        default: break
        }
        collection.layoutIfNeeded()
        record("intervention-end", ["providers": providers, "offset": [offset.x, offset.y]])
        takeSnapshot()
    }

    @objc private func takeSnapshot() {
        collection.layoutIfNeeded()
        let frames = (0..<extents.count).compactMap { item -> [String: Any]? in
            guard let attr = collection.layoutAttributesForItem(at: IndexPath(item: item, section: 0)) else { return nil }
            return ["item": item, "frame": [attr.frame.minX, attr.frame.minY, attr.frame.width, attr.frame.height]]
        }
        let value: [String: Any] = ["mode": mode, "vertical": vertical, "single": single, "fixed": fixed,
            "offset": [offset.x, offset.y], "providers": providers, "fits": fits,
            "interventions": interventionCount, "frames": frames]
        state.accessibilityValue = json(value)
        state.text = "\(mode) · \(vertical ? "vertical" : "horizontal") · fits \(fits) · providers \(providers)"
        record("snapshot", value)
        let trace = json(events)
        traceView.accessibilityValue = trace
        try? trace.write(to: evidenceURL, atomically: true, encoding: .utf8)
    }

    private func record(_ name: String, _ values: [String: Any]) {
        var event = values
        event["event"] = name
        event["time"] = CACurrentMediaTime() - startTime
        events.append(event)
    }
    private func json(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let result = String(data: data, encoding: .utf8) else { return "{}" }
        return result
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { extents.count }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! NativePagingProbeCell
        cell.accessibilityIdentifier = "probe-item-\(indexPath.item)"
        cell.configure(item: indexPath.item, extent: fixed ? 100 : extents[indexPath.item], vertical: vertical)
        cell.onFit = { [weak self] size in
            guard let self else { return }
            fits += 1
            record("fit", ["item": indexPath.item, "size": [size.width, size.height]])
        }
        return cell
    }
}

private final class NativePagingFullInvalidation: UICollectionViewLayoutInvalidationContext {
    override var invalidateEverything: Bool { true }
}

private final class NativePagingProbeContent: UILabel {
    var vertical = false
    var extent: CGFloat = 44
    override var intrinsicContentSize: CGSize {
        vertical ? CGSize(width: UIView.noIntrinsicMetric, height: extent)
                 : CGSize(width: extent, height: UIView.noIntrinsicMetric)
    }
}

private final class NativePagingProbeCell: UICollectionViewCell {
    private let label = NativePagingProbeContent()
    private var vertical = false
    var onFit: ((CGSize) -> Void)?
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.textColor = .white
        contentView.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            label.topAnchor.constraint(equalTo: contentView.topAnchor),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
        contentView.layer.cornerRadius = 8
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(item: Int, extent: CGFloat, vertical: Bool) {
        self.vertical = vertical
        label.vertical = vertical
        label.extent = extent
        label.text = "\(item)\n\(Int(extent))"
        label.numberOfLines = 2
        label.invalidateIntrinsicContentSize()
        contentView.backgroundColor = [.systemBlue, .systemOrange, .systemPurple][(item / 6) % 3]
    }
    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attributes = layoutAttributes.copy() as! UICollectionViewLayoutAttributes
        let target = CGSize(width: vertical ? layoutAttributes.size.width : 0,
                            height: vertical ? 0 : layoutAttributes.size.height)
        attributes.size = contentView.systemLayoutSizeFitting(target,
            withHorizontalFittingPriority: vertical ? .required : .fittingSizeLevel,
            verticalFittingPriority: vertical ? .fittingSizeLevel : .required)
        onFit?(attributes.size)
        return attributes
    }
}
