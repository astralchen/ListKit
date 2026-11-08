import ListKit
import UIKit

/// 标准 Row + WaterfallLayout：示例不实现任何测量闭包或尺寸拟合方法。
@MainActor
final class WaterfallDemoViewController: UIViewController {
    private struct Card: Hashable, Sendable {
        let id: Int
        var expanded = false
        var title: String { ["山间来信", "沿海散步", "城市片刻", "林中小径", "慢慢生活", "日落以后"][id % 6] }
        var detail: String {
            let sentences = ["把今天喜欢的瞬间留下。", "沿着海岸走一段路，听风吹过树梢，也看看远处的船。",
                "在熟悉的街角发现一家小店。窗边有阳光，桌上有一本还没读完的书。", "偶尔换一条路回家。"]
            return sentences[id % sentences.count] + (expanded ? "\n\n多留一点时间，观察身边细小的变化。点一下卡片可以再次收起这段文字。" : "")
        }
        var symbol: String { ["mountain.2.fill", "sun.horizon.fill", "building.2.fill", "leaf.fill", "cup.and.saucer.fill", "moon.stars.fill"][id % 6] }
    }

    private let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private lazy var adapter = CollectionListAdapter<Int>(collectionView: collection)
    private let modes = UISegmentedControl(items: ["纵向", "横向", "正交横向"])
    private let tracks = UISegmentedControl(items: ["自适应", "2 轨道", "3 轨道"])
    private let status = UILabel()
    private var cards = (0..<18).map { Card(id: $0) }
    private var isHorizontal: Bool { modes.selectedSegmentIndex != 0 }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Waterfall"
        navigationItem.largeTitleDisplayMode = .never
        view.backgroundColor = .systemGroupedBackground
        modes.selectedSegmentIndex = 0
        tracks.selectedSegmentIndex = 0
        modes.accessibilityIdentifier = "waterfall-axis"
        tracks.accessibilityIdentifier = "waterfall-tracks"
        collection.accessibilityIdentifier = "waterfall-collection"
        status.accessibilityIdentifier = "waterfall-status"
        modes.addAction(UIAction { [weak self] _ in self?.changeAxis() }, for: .valueChanged)
        tracks.addAction(UIAction { [weak self] _ in self?.render() }, for: .valueChanged)
        let append = UIBarButtonItem(title: "+6", primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            let start = cards.count
            cards.append(contentsOf: (start..<(start + 6)).map { Card(id: $0) })
            render()
        })
        append.accessibilityIdentifier = "waterfall-append"
        let reset = UIBarButtonItem(title: "重置", primaryAction: UIAction { [weak self] _ in
            self?.cards = (0..<18).map { Card(id: $0) }
            self?.render()
            self?.collection.setContentOffset(.zero, animated: false)
        })
        navigationItem.rightBarButtonItems = [append, reset]
        status.font = .preferredFont(forTextStyle: .footnote)
        status.adjustsFontForContentSizeCategory = true
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        collection.backgroundColor = .clear
        collection.contentInsetAdjustmentBehavior = .never
        let controls = UIStackView(arrangedSubviews: [modes, tracks, status])
        controls.axis = .vertical
        controls.spacing = 10
        for child in [controls, collection] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            controls.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            controls.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            collection.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 16),
            collection.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            collection.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            collection.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        ])
        changeAxis()
    }

    private func changeAxis() {
        collection.collectionViewLayout = adapter.makeCompositionalLayout(configuration: .init(
            scrollDirection: modes.selectedSegmentIndex == 1 ? .horizontal : .vertical,
            contentInsetsReference: .none))
        render()
        collection.setContentOffset(.zero, animated: false)
    }

    private func render() {
        let horizontal = isHorizontal
        let adaptive = tracks.selectedSegmentIndex == 0
        let count = tracks.selectedSegmentIndex == 1 ? 2 : 3
        let orthogonal = modes.selectedSegmentIndex == 2
        status.text = "\(cards.count) 张卡片 · \(adaptive ? "轨道数随容器变化" : "固定轨道数") · \(horizontal ? "固定行高，宽度随内容变化" : "固定列宽，高度随内容变化")\n点击卡片展开或收起；+6 追加内容。"
        let waterfall = adaptive
            ? WaterfallLayout(tracks: [ListGridTrack(.adaptive(minimum: horizontal ? 100 : 150))])
            : WaterfallLayout(tracks: count)
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                ForEach(cards, id: \.id) { card in
                    if horizontal {
                        Row(model: card, cell: WaterfallHorizontalCardCell.self) { cell, card, _ in
                            cell.configure(title: card.title, detail: card.expanded ? "沿着新的路线，记录更多喜欢的瞬间" : "片刻 \(card.id + 1)",
                                symbol: card.symbol, index: card.id)
                        }.refreshID(card).refresh(when: .refreshIDChanges)
                            .onSelect { [weak self] card, _ in self?.toggle(card.id) }
                    } else {
                        Row(model: card, cell: WaterfallCardCell.self) { cell, card, _ in
                            cell.configure(title: card.title, detail: card.detail, symbol: card.symbol, index: card.id)
                        }.refreshID(card).refresh(when: .refreshIDChanges)
                            .onSelect { [weak self] card, _ in self?.toggle(card.id) }
                    }
                }
            } layout: {
                waterfall
                    .trackSpacing(12)
                    .lineSpacing(12)
                    .sectionInsets(.init(12))
                    .crossAxisSize(horizontal && !adaptive ? CGFloat(count * 116 + (count - 1) * 12) : nil)
                    .orthogonalScrolling(orthogonal ? .continuous : nil)
            }
        }
    }

    private func toggle(_ id: Int) {
        guard let index = cards.firstIndex(where: { $0.id == id }) else { return }
        cards[index].expanded.toggle()
        render()
    }
}

@MainActor private func waterfallColor(_ index: Int) -> UIColor {
    [.systemTeal, .systemOrange, .systemIndigo, .systemGreen, .systemPink, .systemBlue][index % 6]
}

@MainActor private final class WaterfallCardCell: UICollectionViewCell {
    private let cover = UIView()
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var ratio: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 16
        contentView.clipsToBounds = true
        icon.contentMode = .scaleAspectFit
        icon.tintColor = .white
        icon.translatesAutoresizingMaskIntoConstraints = false
        cover.addSubview(icon)
        titleLabel.numberOfLines = 0
        detailLabel.numberOfLines = 0
        detailLabel.textColor = .secondaryLabel
        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 6
        text.isLayoutMarginsRelativeArrangement = true
        text.directionalLayoutMargins = .init(top: 12, leading: 12, bottom: 14, trailing: 12)
        let stack = UIStackView(arrangedSubviews: [cover, text])
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            icon.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
            icon.widthAnchor.constraint(equalTo: cover.widthAnchor, multiplier: 0.35),
            icon.heightAnchor.constraint(equalTo: icon.widthAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func configure(title: String, detail: String, symbol: String, index: Int) {
        titleLabel.font = .preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        titleLabel.text = title
        detailLabel.text = detail
        cover.backgroundColor = waterfallColor(index)
        icon.image = UIImage(systemName: symbol)
        ratio?.isActive = false
        ratio = cover.heightAnchor.constraint(equalTo: cover.widthAnchor, multiplier: [0.7, 1.0, 1.25][index % 3])
        ratio.isActive = true
        accessibilityIdentifier = "waterfall-card-\(index)"
    }
}

@MainActor private final class WaterfallHorizontalCardCell: UICollectionViewCell {
    private let icon = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 16
        icon.contentMode = .scaleAspectFit
        detailLabel.textColor = .secondaryLabel
        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 8
        let stack = UIStackView(arrangedSubviews: [icon, text])
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            icon.widthAnchor.constraint(equalToConstant: 44),
            icon.heightAnchor.constraint(equalToConstant: 44)
        ])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    func configure(title: String, detail: String, symbol: String, index: Int) {
        titleLabel.font = .preferredFont(forTextStyle: .headline, compatibleWith: traitCollection)
        detailLabel.font = .preferredFont(forTextStyle: .subheadline, compatibleWith: traitCollection)
        titleLabel.text = title + String(repeating: " · 散步", count: index % 3)
        detailLabel.text = detail
        icon.image = UIImage(systemName: symbol)
        icon.tintColor = waterfallColor(index)
        accessibilityIdentifier = "waterfall-card-\(index)"
    }
}
