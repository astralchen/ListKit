import UIKit

/// 不依赖 ListKit 的原生指示器对照，便于复现 UIKit 的容器/手动边距差异。
@MainActor
final class NativeCollectionIndicatorViewController: UIViewController, UICollectionViewDataSource {
    private let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private let directions = UISegmentedControl(items: ["系统默认", "LTR", "RTL"])

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.titleView = directions
        navigationItem.prompt = "原生 UICollectionView 对照"
        directions.accessibilityIdentifier = "layout-direction-control"
        directions.selectedSegmentIndex = 0
        directions.addTarget(self, action: #selector(changeDirection), for: .valueChanged)
        let flash = UIBarButtonItem(image: UIImage(systemName: "waveform"), style: .plain,
                                    target: self, action: #selector(flashIndicators))
        flash.accessibilityIdentifier = "direction-flash-indicators"
        navigationItem.rightBarButtonItem = flash
        collection.accessibilityIdentifier = "direction-grid"
        collection.backgroundColor = .systemBackground
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.dataSource = self
        collection.collectionViewLayout = makeLayout()
        collection.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collection)
        setContentScrollView(collection, for: .all)
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-EmbeddedNativeIndicator") {
            NSLayoutConstraint.activate([
                collection.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                collection.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                collection.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
                collection.heightAnchor.constraint(equalToConstant: 320),
            ])
        } else {
            NSLayoutConstraint.activate([
                collection.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                collection.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                collection.topAnchor.constraint(equalTo: view.topAnchor),
                collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        if args.contains("-CustomIndicatorInsets") {
            collection.automaticallyAdjustsScrollIndicatorInsets = false
            collection.verticalScrollIndicatorInsets = .init(top: 8, left: 4, bottom: 8, right: 12)
        }
    }

    private func makeLayout() -> UICollectionViewCompositionalLayout {
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(72)), subitem: item, count: 3)
        group.interItemSpacing = .fixed(8)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 8
        section.contentInsets = .init(top: 12, leading: 20, bottom: 12, trailing: 40)
        return UICollectionViewCompositionalLayout(section: section)
    }

    @objc private func changeDirection() {
        let offset = collection.contentOffset
        let direction: UITraitEnvironmentLayoutDirection = directions.selectedSegmentIndex == 2 ? .rightToLeft : .leftToRight
        collection.semanticContentAttribute = directions.selectedSegmentIndex == 0 ? .unspecified : (direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight)
        if #available(iOS 17.0, *) {
            if directions.selectedSegmentIndex == 0 { collection.traitOverrides.remove(UITraitLayoutDirection.self) }
            else { collection.traitOverrides.layoutDirection = direction }
            collection.updateTraitsIfNeeded()
        }
        collection.setCollectionViewLayout(makeLayout(), animated: false)
        collection.layoutIfNeeded()
        collection.contentOffset = offset
        // 同样使用 Table 已验证的公开刷新方法；保留原业务配置。
        let automatic = collection.automaticallyAdjustsScrollIndicatorInsets
        collection.automaticallyAdjustsScrollIndicatorInsets = !automatic
        collection.setNeedsLayout()
        collection.layoutIfNeeded()
        collection.automaticallyAdjustsScrollIndicatorInsets = automatic
        collection.setNeedsLayout()
        collection.layoutIfNeeded()
    }

    @objc private func flashIndicators() {
        collection.flashScrollIndicators()
        if ProcessInfo.processInfo.arguments.contains("-CollectionIndicatorScreenshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.collection.flashScrollIndicators()
            }
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { 90 }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        cell.backgroundColor = [.systemBlue, .systemTeal, .systemIndigo][indexPath.item % 3]
        var content = UIListContentConfiguration.cell()
        content.text = String(indexPath.item + 1)
        content.textProperties.color = .white
        cell.contentConfiguration = content
        cell.accessibilityIdentifier = "direction-grid-\(indexPath.item)"
        return cell
    }
}
