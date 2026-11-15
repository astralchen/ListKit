import ListKit
import UIKit

/// 切换时只修改 adapter.layoutDirection，便于观察同一列表的运行时更新。
@MainActor
final class LayoutDirectionOverviewViewController: UIViewController {
    private let grid = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let carousel = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let table = UITableView(frame: .zero, style: .plain)
    private lazy var gridAdapter = CollectionListAdapter<Int>(collectionView: grid)
    private lazy var carouselAdapter = CollectionListAdapter<Int>(collectionView: carousel)
    private lazy var tableAdapter = TableListAdapter<Int>(tableView: table)
    private let directionControl = UISegmentedControl(items: ["系统默认", "LTR", "RTL"])
    private let status = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "嵌入式方向对照"
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "滚动条", primaryAction: UIAction { [weak self] _ in
            self?.flashIndicators()
        })
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "direction-flash-indicators"
        view.backgroundColor = .systemGroupedBackground
        directionControl.selectedSegmentIndex = 0
        directionControl.accessibilityIdentifier = "layout-direction-control"
        directionControl.addAction(UIAction { [weak self] _ in self?.changeDirection() }, for: .valueChanged)
        status.font = .preferredFont(forTextStyle: .caption1)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        status.accessibilityIdentifier = "layout-direction-status"

        for (list, id) in [(grid, "direction-grid"), (carousel, "direction-carousel")] {
            list.backgroundColor = .secondarySystemGroupedBackground
            list.layer.cornerRadius = 12
            list.contentInsetAdjustmentBehavior = .never
            list.accessibilityIdentifier = id
        }
        // UI 回归分别覆盖系统默认边距与业务手动边距。
        if ProcessInfo.processInfo.arguments.contains("-CustomIndicatorInsets") {
            grid.automaticallyAdjustsScrollIndicatorInsets = false
            grid.verticalScrollIndicatorInsets = .init(top: 8, left: 4, bottom: 8, right: 12)
        }
        table.layer.cornerRadius = 12
        table.contentInsetAdjustmentBehavior = .never
        table.accessibilityIdentifier = "direction-table"
        let stack = UIStackView(arrangedSubviews: [
            directionControl, status,
            heading("混合布局 · 上下滚动，横向区左右滑动"), grid,
            heading("横向列表 · 左右滑动查看后续项目"), carousel,
            heading("表格 · 观察色块与箭头的位置"), table,
        ])
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        let safe = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: safe.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -12),
            grid.heightAnchor.constraint(equalTo: table.heightAnchor, multiplier: 1.5),
            carousel.heightAnchor.constraint(equalToConstant: 88),
        ])
        grid.collectionViewLayout = gridAdapter.makeCompositionalLayout(
            configuration: .init(contentInsetsReference: .none))
        carousel.collectionViewLayout = carouselAdapter.makeCompositionalLayout(
            configuration: .init(scrollDirection: .horizontal, contentInsetsReference: .none))
        gridAdapter.apply(transaction: .disabled) {
            ListSection(0) {
                for index in 0..<3 {
                    Row(index, model: index, cell: DirectionDemoCollectionCell.self) { cell, value, _ in
                        cell.configure(value, prefix: "grid")
                    }
                }
            } layout: {
                GridLayout(tracks: 3).itemMainAxisSize(.fixed(64)).trackSpacing(8).lineSpacing(8)
                    .sectionInsets(.init(top: 12, leading: 20, bottom: 12, trailing: 40))
            }
            ListSection(1) {
                for index in 0..<20 {
                    Row(index, model: index, cell: DirectionDemoCollectionCell.self) { cell, value, _ in
                        cell.configure(value, prefix: "mixed")
                    }
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(108)).crossAxisSize(.fixed(88))
                    .lineSpacing(8).orthogonalScrolling(.continuous)
                    .sectionInsets(.init(top: 8, leading: 20, bottom: 12, trailing: 40))
            }
            ListSection(2) {
                for index in 0..<30 {
                    Row(index, model: index, cell: DirectionDemoCollectionCell.self) { cell, value, _ in
                        cell.configure(value, prefix: "grid-tail")
                    }
                }
            } layout: {
                GridLayout(tracks: 3).itemMainAxisSize(.fixed(64)).trackSpacing(8).lineSpacing(8)
                    .sectionInsets(.init(top: 12, leading: 20, bottom: 12, trailing: 40))
            }
        }
        carouselAdapter.apply(transaction: .disabled) {
            ListSection(0) {
                for index in 0..<20 {
                    Row(index, model: index, cell: DirectionDemoCollectionCell.self) { cell, value, _ in
                        cell.configure(value, prefix: "carousel")
                    }
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(108)).lineSpacing(8)
                    .sectionInsets(.init(top: 8, leading: 20, bottom: 8, trailing: 40))
            }
        }
        tableAdapter.apply(transaction: .disabled) {
            TableSection(0) {
                for index in 0..<40 {
                    TableRow(index, model: index, cell: DirectionDemoTableCell.self) { cell, value, _ in
                        cell.configure(value)
                    }
                }
            }.layout { TableLayout().rowHeight(.fixed(60)) }
        }
        updateStatus()
    }

    private func heading(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        return label
    }

    private func changeDirection() {
        let direction: UITraitEnvironmentLayoutDirection = switch directionControl.selectedSegmentIndex {
        case 1: .leftToRight
        case 2: .rightToLeft
        default: .unspecified
        }
        gridAdapter.layoutDirection = direction
        carouselAdapter.layoutDirection = direction
        tableAdapter.layoutDirection = direction
        view.layoutIfNeeded()
        updateStatus()
        flashIndicators()
    }

    private func flashIndicators() {
        [grid, carousel, table].forEach { $0.flashScrollIndicators() }
    }

    private func updateStatus() {
        let direction = grid.effectiveUserInterfaceLayoutDirection == .rightToLeft ? "RTL" : "LTR"
        status.text = "当前生效：\(direction)。先滚动，再切换方向，观察排列、边距和内容位置。"
    }
}

private final class DirectionDemoCollectionCell: UICollectionViewCell {
    private let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        label.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        label.textAlignment = .center
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        contentView.layer.cornerRadius = 8
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])
        isAccessibilityElement = true
    }
    func configure(_ index: Int, prefix: String) {
        label.text = (prefix == "mixed" ? "横 " : "") + String(format: "%02d", index + 1)
        contentView.backgroundColor = [.systemBlue, .systemTeal, .systemIndigo][index % 3]
        accessibilityLabel = "项目 \(index + 1)"
        accessibilityIdentifier = "direction-\(prefix)-\(index)"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

private final class DirectionDemoTableCell: UITableViewCell {
    private let marker = UIView()
    private let label = UILabel()
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        marker.backgroundColor = .systemTeal
        marker.layer.cornerRadius = 6
        label.font = .preferredFont(forTextStyle: .body)
        for child in [marker, label] {
            child.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(child)
        }
        NSLayoutConstraint.activate([
            marker.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            marker.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            marker.widthAnchor.constraint(equalToConstant: 28),
            marker.heightAnchor.constraint(equalToConstant: 28),
            label.leadingAnchor.constraint(equalTo: marker.trailingAnchor, constant: 12),
            label.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),
        ])
        accessoryType = .disclosureIndicator
    }
    func configure(_ index: Int) {
        label.text = "项目 \(index + 1) · Item \(index + 1)"
        accessibilityIdentifier = "direction-table-\(index)"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}


/// 使用 UIKit 管理的完整滚动页面，验证系统安全区、原生指示器和正交 section。
@MainActor
final class LayoutDirectionDemoViewController: UICollectionViewController {
    private lazy var adapter = CollectionListAdapter<Int>(collectionView: collectionView)
    private let directionControl = UISegmentedControl(items: ["系统默认", "LTR", "RTL"])

    init() { super.init(collectionViewLayout: UICollectionViewFlowLayout()) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.accessibilityIdentifier = "direction-grid"
        collectionView.backgroundColor = .systemGroupedBackground
        directionControl.accessibilityIdentifier = "layout-direction-control"
        directionControl.selectedSegmentIndex = 0
        directionControl.addTarget(self, action: #selector(changeDirection), for: .valueChanged)
        navigationItem.titleView = directionControl
        navigationItem.prompt = "布局方向 · 系统默认"
        let flash = UIBarButtonItem(image: UIImage(systemName: "waveform"), style: .plain, target: self, action: #selector(flashIndicators))
        flash.accessibilityIdentifier = "direction-flash-indicators"
        flash.accessibilityLabel = "滚动条"
        let table = UIBarButtonItem(image: UIImage(systemName: "tablecells"), style: .plain, target: self, action: #selector(showTable))
        table.accessibilityIdentifier = "direction-table-page"
        table.accessibilityLabel = "表格方向测试"
        navigationItem.rightBarButtonItems = [table, flash]
        if ProcessInfo.processInfo.arguments.contains("-CustomIndicatorInsets") {
            collectionView.automaticallyAdjustsScrollIndicatorInsets = false
            collectionView.verticalScrollIndicatorInsets = .init(top: 8, left: 4, bottom: 8, right: 12)
        }
        collectionView.collectionViewLayout = adapter.makeCompositionalLayout()
        adapter.apply(transaction: .disabled) {
            ListSection(0) {
                for index in 0..<3 {
                    Row(index, model: index, cell: DirectionDemoCollectionCell.self) { cell, value, _ in
                        cell.configure(value, prefix: "grid")
                    }
                }
            } layout: {
                GridLayout(tracks: 3).itemMainAxisSize(.fixed(84)).trackSpacing(8).lineSpacing(8)
                    .sectionInsets(.init(top: 12, leading: 20, bottom: 16, trailing: 40))
            }
            ListSection(1) {
                for index in 0..<20 {
                    Row(index, model: index, cell: DirectionDemoCollectionCell.self) { cell, value, _ in
                        cell.configure(value, prefix: "mixed")
                    }
                }
            } layout: {
                GridLayout(tracks: 1).itemMainAxisSize(.fixed(108)).crossAxisSize(.fixed(100))
                    .lineSpacing(8).orthogonalScrolling(.continuous)
                    .sectionInsets(.init(top: 8, leading: 20, bottom: 16, trailing: 40))
            }
            ListSection(2) {
                for index in 0..<60 {
                    Row(index, model: index, cell: DirectionDemoCollectionCell.self) { cell, value, _ in
                        cell.configure(value, prefix: "grid-tail")
                    }
                }
            } layout: {
                GridLayout(tracks: 3).itemMainAxisSize(.fixed(84)).trackSpacing(8).lineSpacing(8)
                    .sectionInsets(.init(top: 12, leading: 20, bottom: 16, trailing: 40))
            }
        }
    }

    @objc private func changeDirection() {
        adapter.layoutDirection = [.unspecified, .leftToRight, .rightToLeft][directionControl.selectedSegmentIndex]
        navigationItem.prompt = "布局方向 · \(["系统默认", "LTR", "RTL"][directionControl.selectedSegmentIndex])"
        flashIndicators()
    }
    @objc private func flashIndicators() { collectionView.flashScrollIndicators() }
    @objc private func showTable() {
        navigationController?.pushViewController(DirectionTableDemoViewController(direction: adapter.layoutDirection), animated: true)
    }
}

@MainActor
private final class DirectionTableDemoViewController: UITableViewController {
    private lazy var adapter = TableListAdapter<Int>(tableView: tableView)
    private let initialDirection: UITraitEnvironmentLayoutDirection
    private let directionControl = UISegmentedControl(items: ["系统默认", "LTR", "RTL"])

    init(direction: UITraitEnvironmentLayoutDirection) {
        initialDirection = direction
        super.init(style: .plain)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.accessibilityIdentifier = "direction-table"
        directionControl.accessibilityIdentifier = "layout-direction-control"
        directionControl.selectedSegmentIndex = initialDirection == .rightToLeft ? 2 : (initialDirection == .leftToRight ? 1 : 0)
        directionControl.addTarget(self, action: #selector(changeDirection), for: .valueChanged)
        navigationItem.titleView = directionControl
        navigationItem.prompt = "UITableView 布局方向"
        let flash = UIBarButtonItem(image: UIImage(systemName: "waveform"), style: .plain,
                                    target: self, action: #selector(flashIndicators))
        flash.accessibilityIdentifier = "direction-flash-indicators"
        flash.accessibilityLabel = "滚动条"
        navigationItem.rightBarButtonItem = flash
        if ProcessInfo.processInfo.arguments.contains("-CustomTableIndicatorInsets") {
            tableView.automaticallyAdjustsScrollIndicatorInsets = false
            tableView.verticalScrollIndicatorInsets = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 12)
        }
        adapter.apply(transaction: .disabled) {
            TableSection(0) {
                for index in 0..<40 {
                    TableRow(index, model: index, cell: DirectionDemoTableCell.self) { cell, value, _ in cell.configure(value) }
                }
            }.layout { TableLayout().rowHeight(.fixed(60)) }
        }
        adapter.layoutDirection = initialDirection
    }
    @objc private func changeDirection() {
        adapter.layoutDirection = [.unspecified, .leftToRight, .rightToLeft][directionControl.selectedSegmentIndex]
        tableView.flashScrollIndicators()
    }
    @objc private func flashIndicators() {
        tableView.flashScrollIndicators()
        if ProcessInfo.processInfo.arguments.contains("-TableIndicatorScreenshot") {
            // 让原生闪现覆盖 XCTest 的空闲等待；不修改指示器布局或显示开关。
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.tableView.flashScrollIndicators()
            }
        }
    }
}
