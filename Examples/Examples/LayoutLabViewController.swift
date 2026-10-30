import ListKit
import UIKit

/// 仅负责页面与状态绑定；布局和代码由同一个 configuration 生成。
@MainActor
final class LayoutLabViewController: UIViewController {
    private let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private lazy var adapter = CollectionListAdapter<Int>(collectionView: collection)
    private var configuration = LayoutLabConfiguration()
    private let controls = UIStackView()
    private let modes = UISegmentedControl(items: LayoutLabConfiguration.TrackMode.allCases.map(\.rawValue))
    private let axisButton = UIButton(type: .system)
    private let sceneButton = UIButton(type: .system)
    private let widthButton = UIButton(type: .system)
    private let countButton = UIButton(type: .system)
    private let explanation = UILabel()
    private var compactWidth: NSLayoutConstraint!
    private var compactHeight: NSLayoutConstraint!

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Layout Lab"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.largeTitleDisplayMode = .never
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "参数 / 代码", primaryAction: UIAction { [weak self] _ in
            self?.showParameters()
        })
        controls.axis = .vertical
        controls.spacing = 8
        let actions = UIStackView(arrangedSubviews: [axisButton, sceneButton, widthButton, countButton])
        actions.distribution = .fillEqually
        actions.spacing = 4
        controls.addArrangedSubview(actions)
        controls.addArrangedSubview(modes)
        controls.addArrangedSubview(explanation)
        modes.accessibilityIdentifier = "layout-modes"
        modes.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.configuration.trackMode = LayoutLabConfiguration.TrackMode.allCases[self.modes.selectedSegmentIndex]
            self.render(resetOffset: true)
        }, for: .valueChanged)
        configureButton(axisButton, id: "Axis") { [weak self] in
            guard let self else { return }
            self.configuration.horizontal.toggle()
            self.collection.collectionViewLayout = self.adapter.makeCompositionalLayout(
                configuration: .init(scrollDirection: self.configuration.outerAxis))
            self.render(resetOffset: true)
        }
        configureButton(widthButton, id: "Width") { [weak self] in
            guard let self else { return }
            self.configuration.narrow.toggle()
            self.updateControls()
            self.view.setNeedsLayout()
            self.view.layoutIfNeeded() // 容器尺寸变化驱动 layout invalidation，不重复 apply 内容。
        }
        configureButton(countButton, id: "Count") { [weak self] in
            guard let self else { return }
            self.configuration.cycleCount()
            self.render(resetOffset: true)
        }
        sceneButton.accessibilityIdentifier = "Scenes"
        sceneButton.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        sceneButton.showsMenuAsPrimaryAction = true
        explanation.font = .preferredFont(forTextStyle: .caption1)
        explanation.adjustsFontForContentSizeCategory = true
        explanation.textColor = .secondaryLabel
        explanation.numberOfLines = 3
        explanation.accessibilityIdentifier = "lab-explanation"
        collection.backgroundColor = .secondarySystemGroupedBackground
        collection.layer.cornerRadius = 12
        collection.contentInsetAdjustmentBehavior = .never
        collection.accessibilityIdentifier = "layout-lab-collection"
        for child in [controls, collection] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        let safe = view.safeAreaLayoutGuide
        let fullWidth = collection.widthAnchor.constraint(equalTo: safe.widthAnchor, constant: -24)
        fullWidth.priority = .defaultHigh
        let fullHeight = collection.bottomAnchor.constraint(equalTo: safe.bottomAnchor, constant: -8)
        // 收窄高度时允许底部留白，不能拉伸上方说明文字来满足填满约束。
        fullHeight.priority = .init(249)
        compactWidth = collection.widthAnchor.constraint(equalToConstant: 240)
        compactHeight = collection.heightAnchor.constraint(equalToConstant: 240)
        compactWidth.priority = .init(999)
        compactHeight.priority = .init(999)
        NSLayoutConstraint.activate([
            controls.leadingAnchor.constraint(equalTo: safe.leadingAnchor, constant: 12),
            controls.trailingAnchor.constraint(equalTo: safe.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: safe.topAnchor, constant: 8),
            collection.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 12),
            collection.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            collection.widthAnchor.constraint(lessThanOrEqualTo: safe.widthAnchor, constant: -24),
            collection.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -8),
            fullWidth, fullHeight,
        ])
        collection.collectionViewLayout = adapter.makeCompositionalLayout(configuration: .init(scrollDirection: configuration.outerAxis))
        render(resetOffset: false)
    }

    private func configureButton(_ button: UIButton, id: String, action: @escaping () -> Void) {
        button.accessibilityIdentifier = id
        button.titleLabel?.font = .preferredFont(forTextStyle: .subheadline)
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
    }

    private func updateControls() {
        modes.selectedSegmentIndex = LayoutLabConfiguration.TrackMode.allCases.firstIndex(of: configuration.trackMode)!
        modes.setTitle(configuration.horizontal ? "3 rows" : "3 columns", forSegmentAt: 1)
        modes.isEnabled = configuration.editsGrid
        axisButton.setTitle(configuration.horizontal ? "横向" : "纵向", for: .normal)
        widthButton.setTitle(configuration.narrow ? "240 pt" : "容器自适应", for: .normal)
        widthButton.accessibilityValue = configuration.horizontal ? "高度" : "宽度"
        countButton.setTitle("\(configuration.count) 项", for: .normal)
        sceneButton.setTitle(configuration.scene.rawValue, for: .normal)
        sceneButton.menu = UIMenu(title: "布局场景", children: LayoutLabConfiguration.Scene.allCases.map { scene in
            UIAction(title: scene.rawValue, subtitle: scene.title, state: scene == configuration.scene ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.configuration.scene = scene
                self.render(resetOffset: true)
            }
        })
        explanation.text = configuration.axisDescription + "\n" + configuration.explanation
        compactWidth.isActive = configuration.narrow && !configuration.horizontal
        compactHeight.isActive = configuration.narrow && configuration.horizontal
    }

    private func showParameters() {
        let controller = LayoutLabParametersViewController(configuration: configuration) { [weak self] value in
            self?.configuration = value
            self?.render(resetOffset: false)
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .pageSheet
        if let sheet = navigation.sheetPresentationController { sheet.detents = [.large()] }
        present(navigation, animated: true)
    }

    private func render(resetOffset: Bool) {
        updateControls()
        let snapshot = configuration
        adapter.apply(transaction: .disabled) {
            for section in 0..<snapshot.sectionCount {
                makeSection(section, configuration: snapshot)
            }
        }
        if resetOffset { collection.setContentOffset(.zero, animated: false) }
    }

    private func makeSection(_ section: Int, configuration: LayoutLabConfiguration) -> ListSection<Int> {
        ListSection(section) {
            rows(in: section, configuration: configuration)
        }
        .layout {
            layout(in: section, configuration: configuration)
        }
        .supplementaries {
            boundaryContent(in: section, configuration: configuration)
            if configuration.scene == .badges {
                SectionSupplementary(LayoutLabBadge.self, kind: LayoutLabElementKind.badge, id: "badge") { view, context in
                    view.configure(item: context.indexPath.item)
                }.onTap { [weak self] context in
                    self?.explanation.text = "点击徽标：item \(context.indexPath.item)"
                }
            }
        }
        .decorations {
            if configuration.scene != .nativeList {
                SectionDecoration(LayoutLabBackground.self, kind: LayoutLabElementKind.card)
            }
        }
    }

    private func rows(in section: Int, configuration: LayoutLabConfiguration) -> RowGroup {
        RowGroup {
            for index in 0..<configuration.count {
                let item = configuration.item(index: index, section: section)
                Row(index, model: item, cell: LayoutLabCell.self) { cell, item, _ in
                    cell.configure(item)
                    cell.accessibilityIdentifier = section == 0 ? "layout-item-\(index)" : "mixed-\(section)-\(index)"
                }
                .refreshID(item)
                .refresh(when: .refreshIDChanges, action: .reconfigure(layout: .invalidate))
            }
        }
    }

    @ListSectionLayoutBuilder<Int>
    private func layout(in section: Int, configuration: LayoutLabConfiguration) -> ListSectionLayoutSource<Int>? {
        if configuration.scene == .nativeList {
            UIKitListLayout(appearance: .insetGrouped)
        } else {
            configuration.recipe(section: section).makeGrid()
                .itemSupplementaries {
                    if configuration.scene == .badges {
                        ItemSupplementaryLayout(kind: LayoutLabElementKind.badge,
                            size: .init(width: .absolute(24), height: .absolute(24)), itemAnchor: .topTrailing)
                            .zIndex(2)
                    }
                }
                .boundarySupplementaries {
                    if section == 0 {
                        BoundarySupplementaryLayout(
                            kind: LayoutLabElementKind.title,
                            mainAxisSize: .fixed(CGFloat(configuration.titleExtent)),
                            sizingAxis: configuration.outerAxis,
                            alignment: configuration.horizontal ? .leading : .top
                        )
                        .pinToVisibleBounds(configuration.pinHeaders)
                        BoundarySupplementaryLayout(
                            kind: LayoutLabElementKind.summary,
                            mainAxisSize: .fixed(CGFloat(configuration.summaryExtent)),
                            sizingAxis: configuration.outerAxis,
                            alignment: configuration.horizontal ? .trailing : .bottom
                        )
                    }
                }
                .decorationItems {
                    DecorationItemLayout(kind: LayoutLabElementKind.card)
                }
        }
    }

    @ListSectionSupplementaryBuilder<Int>
    private func boundaryContent(in section: Int, configuration: LayoutLabConfiguration) -> [ListSectionSupplementary<Int>] {
        if section == 0 && configuration.scene != .nativeList {
            SectionSupplementary(LayoutLabHeader.self, kind: LayoutLabElementKind.title, id: "title") { view, _ in
                view.configure(text: "lab.title · \(configuration.count)", identifier: "lab-title")
            }
            .refreshID(configuration.count)
            SectionSupplementary(LayoutLabHeader.self, kind: LayoutLabElementKind.summary, id: "footer") { view, _ in
                view.configure(text: "lab.summary", identifier: "lab-summary")
            }
        }
    }
}
