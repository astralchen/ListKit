import UIKit

/// 不依赖 ListKit 的原生指示器对照，便于复现 UIKit 的容器/手动边距差异。
@MainActor
final class NativeCollectionIndicatorViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    private lazy var collection: UICollectionView = {
        let layout = ProcessInfo.processInfo.arguments.contains("-NativeInitialCompositionalLayout") || isTriggerProbe
            ? makeLayout() : UICollectionViewFlowLayout()
        return isTriggerProbe ? NativeIndicatorProbeCollection(frame: .zero, collectionViewLayout: layout)
            : UICollectionView(frame: .zero, collectionViewLayout: layout)
    }()
    private var isTriggerProbe: Bool { ProcessInfo.processInfo.arguments.contains("-NativeIndicatorTriggerProbe") }
    private var probeConstraints: [NSLayoutConstraint] = []
    private var probeIndex = -1
    private var probeDisablesBarObservation = false
    private var probeBarQueries = 0
    private var probeSteps: [String] {
        if ProcessInfo.processInfo.arguments.contains("-NativeIndicatorTopProbe") {
            return ["baseline", "top-0-wide", "top-0-narrow", "top-1-wide", "top-1-narrow",
                    "top-61-wide", "top-149-wide", "top-150-wide", "full-again"]
        }
        if ProcessInfo.processInfo.arguments.contains("-NativeIndicatorBoundaryProbe") {
            return ["baseline", "window-top-underlap", "window-top-edge", "window-top-clear", "nav-underlap", "nav-edge", "nav-clear", "home-underlap", "home-edge",
                    "home-clear", "full-again", "disable-bar-observation", "enable-bar-observation"]
        }
        return ["baseline", "auto-off", "auto-on", "top-only", "zero-after-top",
                              "bottom-only", "zero-after-bottom", "both", "zero-after-both",
                              "horizontal-only", "zero-after-horizontal", "horizontal-indicator-only",
                              "horizontal-indicator-zero", "content-never", "content-auto", "embedded",
                              "embedded-safe-add", "embedded-safe-remove", "full-again"]
    }
    private let directions = UISegmentedControl(items: ["系统默认", "LTR", "RTL"])
    private var embeddedHost: UIViewController?
    private var usesMixedLayout: Bool { ProcessInfo.processInfo.arguments.contains("-NativeMixedLayout") }
    private var configurationCase: String? {
        let args = ProcessInfo.processInfo.arguments
        return args.firstIndex(of: "-NativeCompositionalCase").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.titleView = directions
        navigationItem.prompt = "原生 UICollectionView 对照"
        directions.accessibilityIdentifier = "layout-direction-control"
        if isTriggerProbe {
            let next = UIBarButtonItem(title: "探针", style: .plain, target: self, action: #selector(advanceIndicatorProbe))
            next.accessibilityIdentifier = "indicator-probe-next"
            navigationItem.leftBarButtonItem = next
        }
        directions.selectedSegmentIndex = ProcessInfo.processInfo.arguments.contains("-NativeSceneRTLBeforeWindow") ? 2 : 0
        directions.addTarget(self, action: #selector(changeDirection), for: .valueChanged)
        let flash = UIBarButtonItem(image: UIImage(systemName: "waveform"), style: .plain,
                                    target: self, action: #selector(flashIndicators))
        flash.accessibilityIdentifier = "direction-flash-indicators"
        navigationItem.rightBarButtonItem = flash
        collection.accessibilityIdentifier = "direction-grid"
        collection.backgroundColor = .systemBackground
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: "cell")
        collection.dataSource = self
        collection.delegate = self
        if !ProcessInfo.processInfo.arguments.contains("-NativeInitialCompositionalLayout") && !isTriggerProbe {
            collection.collectionViewLayout = makeLayout()
        }
        collection.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collection)
        setContentScrollView(collection, for: .all)
        let args = ProcessInfo.processInfo.arguments
        let mode = args.firstIndex(of: "-NativeIndicatorCase").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        if isTriggerProbe {
            setProbeGeometry(embedded: false)
        } else if mode == "child-safe-area" {
            let host = UIViewController()
            embeddedHost = host
            addChild(host)
            host.view.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(host.view)
            host.view.addSubview(collection)
            host.additionalSafeAreaInsets.top = 12
            NSLayoutConstraint.activate([
                host.view.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                host.view.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                host.view.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
                host.view.heightAnchor.constraint(equalToConstant: 320),
                collection.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                collection.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                collection.topAnchor.constraint(equalTo: host.view.topAnchor),
                collection.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            ])
            host.didMove(toParent: self)
        } else if args.contains("-EmbeddedNativeIndicator") || mode == "embedded" || mode == "content-inset" {
            NSLayoutConstraint.activate([
                collection.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
                collection.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
                collection.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
                collection.heightAnchor.constraint(equalToConstant: 320),
            ])
        } else if mode == "safe-area" {
            NSLayoutConstraint.activate([
                collection.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
                collection.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
                collection.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                collection.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            ])
        } else {
            let horizontalInset: CGFloat = mode == "narrow" ? 16 : 0
            NSLayoutConstraint.activate([
                collection.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: horizontalInset),
                collection.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -horizontalInset),
                mode == "below-bar"
                    ? collection.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24)
                    : collection.topAnchor.constraint(equalTo: view.topAnchor),
                mode == "short" ? collection.heightAnchor.constraint(equalToConstant: 320)
                    : collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        if args.contains("-CustomIndicatorInsets") {
            collection.automaticallyAdjustsScrollIndicatorInsets = false
            collection.verticalScrollIndicatorInsets = .init(top: 8, left: 4, bottom: 8, right: 12)
        }
        if mode == "manual-zero" { collection.automaticallyAdjustsScrollIndicatorInsets = false }
        if mode == "auto-custom" { collection.verticalScrollIndicatorInsets = .init(top: 8, left: 4, bottom: 8, right: 12) }
        if mode == "top-insets" { collection.verticalScrollIndicatorInsets = .init(top: 8, left: 0, bottom: 8, right: 0) }
        if mode == "zero-set" { collection.verticalScrollIndicatorInsets = .zero }
        if mode == "content-inset" { collection.contentInset.top = 12 }
        if configurationCase == "adjust-always" { collection.contentInsetAdjustmentBehavior = .always }
        if configurationCase == "adjust-never" { collection.contentInsetAdjustmentBehavior = .never }

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if ProcessInfo.processInfo.arguments.contains("-NativeSceneRTLBeforeWindow") || ProcessInfo.processInfo.arguments.contains("-NativeLanguageStartup") {
            // 只采集首次显示后的环境，不调用 changeDirection 或刷新布局/指示器。
            recordIndicatorMetrics()
        }
    }

    private func makeLayout() -> UICollectionViewLayout {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-NativeCollectionLayout"), index + 1 < args.count, args[index + 1] == "flow" {
            let layout = UICollectionViewFlowLayout()
            layout.scrollDirection = .vertical
            layout.minimumLineSpacing = 8
            layout.minimumInteritemSpacing = 8
            layout.estimatedItemSize = .zero
            layout.sectionInset = .init(top: 12, left: 20, bottom: 12, right: 40)
            return layout
        }
        if configurationCase == "list-factory" {
            var list = UICollectionLayoutListConfiguration(appearance: args.contains("-NativeGroupedList") ? .grouped : .plain)
            list.showsSeparators = false
            return UICollectionViewCompositionalLayout.list(using: list)
        }
        let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(72)), subitem: item, count: 3)
        group.interItemSpacing = .fixed(8)
        let section = NSCollectionLayoutSection(group: group)
        section.interGroupSpacing = 8
        section.contentInsets = .init(top: 12, leading: 20, bottom: 12, trailing: 40)
        if let index = args.firstIndex(of: "-NativeLayoutPolicy"), index + 1 < args.count {
            let direction: UITraitEnvironmentLayoutDirection = [.unspecified, .leftToRight, .rightToLeft][directions.selectedSegmentIndex]
            return NativeDirectionPolicyLayout(section: section, direction: direction, policy: args[index + 1])
        }
        let configuration = UICollectionViewCompositionalLayoutConfiguration()
        switch configurationCase {
        case "automatic": configuration.contentInsetsReference = .automatic
        case "none": configuration.contentInsetsReference = .none
        case "margins": configuration.contentInsetsReference = .layoutMargins
        case "readable": configuration.contentInsetsReference = .readableContent
        default: break
        }
        guard usesMixedLayout else { return UICollectionViewCompositionalLayout(section: section, configuration: configuration) }
        // 真正的正交 section；由 UIKit 管理横向滚动，不嵌套业务 UIScrollView。
        let includesList = configurationCase == "list-section"
        return UICollectionViewCompositionalLayout(sectionProvider: { index, environment in
            if includesList && index == 2 {
                var list = UICollectionLayoutListConfiguration(appearance: args.contains("-NativeGroupedList") ? .grouped : .plain)
                list.showsSeparators = false
                return NSCollectionLayoutSection.list(using: list, layoutEnvironment: environment)
            }
            guard index == 0 else { return section }
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: .init(widthDimension: .absolute(100), heightDimension: .absolute(72)), subitems: [item])
            let horizontal = NSCollectionLayoutSection(group: group)
            horizontal.orthogonalScrollingBehavior = .continuous
            horizontal.interGroupSpacing = 8
            horizontal.contentInsets = .init(top: 12, leading: 20, bottom: 12, trailing: 40)
            return horizontal
        }, configuration: configuration)
    }

    @objc private func changeDirection() {
        let args = ProcessInfo.processInfo.arguments
        let visibilityRefresh = args.firstIndex(of: "-NativeIndicatorVisibilityRefresh").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        let showsVertical = collection.showsVerticalScrollIndicator
        if visibilityRefresh != nil {
            collection.showsVerticalScrollIndicator = false
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
        }
        let offset = collection.contentOffset
        let direction: UITraitEnvironmentLayoutDirection = directions.selectedSegmentIndex == 2 ? .rightToLeft : .leftToRight
        let scope = args.firstIndex(of: "-NativeDirectionScope").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
        collection.semanticContentAttribute = scope != nil || directions.selectedSegmentIndex == 0 ? .unspecified : (direction == .rightToLeft ? .forceRightToLeft : .forceLeftToRight)
        if #available(iOS 17.0, *) {
            // 上层方向实验保持 Collection 无本地覆盖，只观察继承的 trait。
            if scope != nil || directions.selectedSegmentIndex == 0 { collection.traitOverrides.remove(UITraitLayoutDirection.self) }
            else { collection.traitOverrides.layoutDirection = direction }
            switch scope {
            case "scene":
                if directions.selectedSegmentIndex == 0 { view.window?.windowScene?.traitOverrides.remove(UITraitLayoutDirection.self) }
                else { view.window?.windowScene?.traitOverrides.layoutDirection = direction }
            case "window":
                if directions.selectedSegmentIndex == 0 { view.window?.traitOverrides.remove(UITraitLayoutDirection.self) }
                else { view.window?.traitOverrides.layoutDirection = direction }
            case "controller":
                if directions.selectedSegmentIndex == 0 { traitOverrides.remove(UITraitLayoutDirection.self) }
                else { traitOverrides.layoutDirection = direction }
            default: break
            }
            view.window?.updateTraitsIfNeeded()
            view.updateTraitsIfNeeded()
            collection.updateTraitsIfNeeded()
        }
        if scope != nil { view.window?.layoutIfNeeded() }
        collection.setCollectionViewLayout(makeLayout(), animated: false)
        collection.layoutIfNeeded()
        collection.contentOffset = offset
        if let visibilityRefresh {
            // 对照实验：隐藏跨越方向更新及布局，恢复业务原有的可见性。
            let restore: @MainActor @Sendable () -> Void = { [weak self] in
                guard let self else { return }
                self.collection.showsVerticalScrollIndicator = showsVertical
                self.collection.setNeedsLayout()
                self.collection.layoutIfNeeded()
            }
            if visibilityRefresh == "delayed" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: restore)
            } else {
                restore()
            }
        } else if scope == nil && !isTriggerProbe {
            // 同样使用 Table 已验证的公开刷新方法；保留原业务配置。
            let automatic = collection.automaticallyAdjustsScrollIndicatorInsets
            collection.automaticallyAdjustsScrollIndicatorInsets = !automatic
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
            collection.automaticallyAdjustsScrollIndicatorInsets = automatic
            collection.setNeedsLayout()
            collection.layoutIfNeeded()
        }
        if args.contains("-NativeIndicatorCase") || scope != nil || args.contains("-NativeCollectionLayout") || configurationCase != nil || usesMixedLayout {
            recordIndicatorMetrics()
        }
    }

    private func recordIndicatorMetrics() {
        collection.accessibilityLabel = "frame=\(collection.frame); safe=\(collection.safeAreaInsets); adjusted=\(collection.adjustedContentInset); content=\(collection.contentInset); offsetAtMeasurement=\(collection.contentOffset); auto=\(collection.automaticallyAdjustsScrollIndicatorInsets); vertical=\(collection.verticalScrollIndicatorInsets); trait=\(collection.traitCollection.layoutDirection.rawValue); effective=\(collection.effectiveUserInterfaceLayoutDirection.rawValue); controllerTrait=\(traitCollection.layoutDirection.rawValue); windowTrait=\(view.window?.traitCollection.layoutDirection.rawValue ?? -1); sceneTrait=\(view.window?.windowScene?.traitCollection.layoutDirection.rawValue ?? -1)"
        collection.accessibilityLabel! += "; preferredLanguage=\(Locale.preferredLanguages.first ?? "nil"); bundleLanguage=\(Bundle.main.preferredLocalizations.first ?? "nil"); applicationDirection=\(UIApplication.shared.userInterfaceLayoutDirection.rawValue)"
        if #available(iOS 17.0, *) {
            collection.accessibilityLabel! += "; sceneOverride=\(view.window?.windowScene?.traitOverrides.contains(UITraitLayoutDirection.self) ?? false); collectionOverride=\(collection.traitOverrides.contains(UITraitLayoutDirection.self)); semantic=\(collection.semanticContentAttribute.rawValue)"
        }
        collection.accessibilityLabel! += "; argumentLanguageOverride=\(UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)["AppleLanguages"] != nil)"
        collection.accessibilityLabel! += "; initialCompositional=\(ProcessInfo.processInfo.arguments.contains("-NativeInitialCompositionalLayout")); mixed=\(usesMixedLayout); configurationCase=\(configurationCase ?? "default"); adjustment=\(collection.contentInsetAdjustmentBehavior.rawValue)"
        let layout = collection.collectionViewLayout
        if let compositional = layout as? UICollectionViewCompositionalLayout {
            collection.accessibilityLabel! += "; contentInsetsReference=\(compositional.configuration.contentInsetsReference.rawValue)"
        }
        collection.accessibilityLabel! += "; layout=\(type(of: layout)); developmentDirection=\(layout.developmentLayoutDirection.rawValue); flips=\(layout.flipsHorizontallyInOppositeLayoutDirection); contentSize=\(collection.contentSize)"
        if let probe = collection as? NativeIndicatorProbeCollection {
            collection.accessibilityLabel! += "; probe=\(probeIndex < 0 ? "direction" : probeSteps[probeIndex]); horizontal=\(collection.horizontalScrollIndicatorInsets); windowRect=\(collection.convert(collection.bounds, to: view.window)); windowSafe=\(view.window?.safeAreaInsets ?? .zero); barObservationDisabled=\(probeDisablesBarObservation); barQueries=\(probeBarQueries); callbacks=\(probe.events.joined(separator: " | "))"
        }
    }

    override func contentScrollView(for edge: NSDirectionalRectEdge) -> UIScrollView? {
        if isTriggerProbe {
            probeBarQueries += 1
            if probeDisablesBarObservation { return nil }
        }
        return super.contentScrollView(for: edge)
    }

    private func setProbeGeometry(embedded: Bool, top: CGFloat? = nil, horizontalInset: CGFloat? = nil) {
        let inset = horizontalInset ?? (embedded ? 16 : 0)
        NSLayoutConstraint.deactivate(probeConstraints)
        probeConstraints = [
            collection.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: inset),
            collection.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -inset),
            collection.topAnchor.constraint(equalTo: view.topAnchor, constant: embedded ? (top ?? (view.safeAreaInsets.top + 24)) : 0),
            embedded ? collection.heightAnchor.constraint(equalToConstant: 320)
                : collection.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ]
        NSLayoutConstraint.activate(probeConstraints)
    }

    @objc private func advanceIndicatorProbe() {
        guard isTriggerProbe, probeIndex + 1 < probeSteps.count else { return }
        probeIndex += 1
        let probe = collection as? NativeIndicatorProbeCollection
        probe?.events.removeAll()
        probe?.record("before-" + probeSteps[probeIndex])
        switch probeSteps[probeIndex] {
        case "baseline": collection.setContentOffset(CGPoint(x: 0, y: 300), animated: false)
        case "auto-off": collection.automaticallyAdjustsScrollIndicatorInsets = false
        case "auto-on": collection.automaticallyAdjustsScrollIndicatorInsets = true
        case "top-only": collection.verticalScrollIndicatorInsets.top = 8
        case "bottom-only": collection.verticalScrollIndicatorInsets.bottom = 8
        case "both": collection.verticalScrollIndicatorInsets = .init(top: 8, left: 0, bottom: 8, right: 0)
        case "horizontal-only": collection.verticalScrollIndicatorInsets = .init(top: 0, left: 4, bottom: 0, right: 12)
        case "horizontal-indicator-only": collection.horizontalScrollIndicatorInsets = .init(top: 8, left: 4, bottom: 8, right: 12)
        case "horizontal-indicator-zero": collection.horizontalScrollIndicatorInsets = .zero
        case "content-never": collection.contentInsetAdjustmentBehavior = .never
        case "content-auto": collection.contentInsetAdjustmentBehavior = .automatic
        case "top-0-wide", "top-0-narrow", "top-1-wide", "top-1-narrow", "top-61-wide", "top-149-wide", "top-150-wide":
            let name = probeSteps[probeIndex]
            let top = CGFloat(Double(name.split(separator: "-")[1])!)
            setProbeGeometry(embedded: true, top: top, horizontalInset: name.hasSuffix("wide") ? 0 : 16)
        case "window-top-underlap", "window-top-edge", "window-top-clear":
            if let window = view.window {
                let boundary = view.convert(CGPoint(x: window.bounds.minX, y: window.bounds.minY + window.safeAreaInsets.top), from: window).y
                let delta: CGFloat = probeSteps[probeIndex] == "window-top-underlap" ? -1
                    : probeSteps[probeIndex] == "window-top-clear" ? 1 : 0
                setProbeGeometry(embedded: true, top: boundary + delta)
            }
        case "nav-underlap": setProbeGeometry(embedded: true, top: view.safeAreaInsets.top - 1)
        case "nav-edge": setProbeGeometry(embedded: true, top: view.safeAreaInsets.top)
        case "nav-clear": setProbeGeometry(embedded: true, top: view.safeAreaInsets.top + 1)
        case "home-underlap": setProbeGeometry(embedded: true, top: view.bounds.height - view.safeAreaInsets.bottom - 320 + 1)
        case "home-edge": setProbeGeometry(embedded: true, top: view.bounds.height - view.safeAreaInsets.bottom - 320)
        case "home-clear": setProbeGeometry(embedded: true, top: view.bounds.height - view.safeAreaInsets.bottom - 320 - 1)
        case "disable-bar-observation":
            probeDisablesBarObservation = true
            setContentScrollView(nil, for: .all)
        case "enable-bar-observation":
            probeDisablesBarObservation = false
            setContentScrollView(collection, for: .all)
        case "embedded": setProbeGeometry(embedded: true)
        case "embedded-safe-add": additionalSafeAreaInsets.top = 60
        case "embedded-safe-remove": additionalSafeAreaInsets = .zero
        case "full-again": setProbeGeometry(embedded: false)
        default: collection.verticalScrollIndicatorInsets = .zero
        }
        view.setNeedsLayout()
        view.layoutIfNeeded()
        collection.layoutIfNeeded()
        // 跨一轮主队列再采样，保留 UIKit 自己触发的回调；不手动调用通知方法。
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.layoutIfNeeded()
            probe?.record("settled-" + self.probeSteps[self.probeIndex])
            self.recordIndicatorMetrics()
        }
    }

    @objc private func flashIndicators() {
        collection.flashScrollIndicators()
        if ProcessInfo.processInfo.arguments.contains("-CollectionIndicatorScreenshot") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.collection.flashScrollIndicators()
            }
        }
    }

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        usesMixedLayout ? (configurationCase == "list-section" ? 3 : 2) : 1
    }
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if usesMixedLayout && section == 0 { return 20 }
        if configurationCase == "list-section" && section == 1 { return 6 }
        return 90
    }
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        // 与 Compositional 对照保持三列、行高 72、列间距 8、section 总水平边距 60。
        let available = collectionView.bounds.width - collectionView.adjustedContentInset.left - collectionView.adjustedContentInset.right
        return CGSize(width: max(1, (available - 60 - 16) / 3), height: 72)
    }
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath)
        let isList = configurationCase == "list-factory" || indexPath.section == 2
        // list 行延伸到边缘，使用浅色背景，便于截图明确区分原生灰色指示器。
        cell.backgroundColor = isList ? .systemBackground : [.systemBlue, .systemTeal, .systemIndigo][indexPath.item % 3]
        var content = UIListContentConfiguration.cell()
        content.text = String(indexPath.item + 1)
        content.textProperties.color = isList ? .label : .white
        cell.contentConfiguration = content
        let prefix = usesMixedLayout && indexPath.section == 0 ? "direction-horizontal"
            : indexPath.section == 2 ? "direction-list" : "direction-grid"
        cell.accessibilityIdentifier = "\(prefix)-\(indexPath.item)"
        return cell
    }
}

/// 仅用于原生对照页的坐标基准实验，不用于 ListKit 布局。
private final class NativeDirectionPolicyLayout: UICollectionViewCompositionalLayout {
    private let direction: UITraitEnvironmentLayoutDirection
    private let policy: String

    init(section: NSCollectionLayoutSection, direction: UITraitEnvironmentLayoutDirection, policy: String) {
        self.direction = direction
        self.policy = policy
        super.init(section: section, configuration: .init())
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override var developmentLayoutDirection: UIUserInterfaceLayoutDirection {
        guard direction != .unspecified else { return super.developmentLayoutDirection }
        return policy.hasPrefix("target") && direction == .rightToLeft ? .rightToLeft : .leftToRight
    }
    override var flipsHorizontallyInOppositeLayoutDirection: Bool {
        guard direction != .unspecified else { return super.flipsHorizontallyInOppositeLayoutDirection }
        return policy.hasSuffix("true")
    }
}

/// 仅观测公开回调；所有 UIKit override 都先调用 super，不改指示器或坐标。
private final class NativeIndicatorProbeCollection: UICollectionView {
    var events: [String] = []

    func record(_ event: String) {
        events.append("\(event): safe=\(safeAreaInsets), adjusted=\(adjustedContentInset), auto=\(automaticallyAdjustsScrollIndicatorInsets), vertical=\(verticalScrollIndicatorInsets)")
        if events.count > 24 { events.removeFirst(events.count - 24) }
    }
    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        record("safeAreaInsetsDidChange")
    }
    override func adjustedContentInsetDidChange() {
        super.adjustedContentInsetDidChange()
        record("adjustedContentInsetDidChange")
    }
}
