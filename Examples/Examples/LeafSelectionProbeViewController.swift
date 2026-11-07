import UIKit
import ListKit

/// 真实触摸回归页面。仅记录 UIKit 状态与回调，不手动提交选择或调用 delegate。
@MainActor
final class LeafSelectionProbeViewController: UIViewController {
    private let collection = UICollectionView(frame: .zero, collectionViewLayout: UICollectionViewFlowLayout())
    private lazy var adapter = CollectionListAdapter<Int>(collectionView: collection)
    private let status = UILabel()
    private var primaryDelegate: UICollectionViewDelegate?
    private let actionKind = ProcessInfo.processInfo.environment["LEAF_ACTION"] ?? "none"
    private var events: [String] = []
    private var callbackSelections: [[String]] = []
    private var phase = 0
    private var ready = false
    private let modeName = ProcessInfo.processInfo.environment["LEAF_MODE"] ?? "single"
    private let companion = ProcessInfo.processInfo.environment["LEAF_COMPANION"] == "1"
    private var mode: ListSelectionMode {
        switch modeName { case "automatic": .automatic; case "multiple": .multiple; default: .single }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "\(modeName) · \(companion ? 2 : 1) section(s)"
        view.backgroundColor = .systemBackground
        if actionKind.hasPrefix("dynamic-") {
            navigationItem.rightBarButtonItem = UIBarButtonItem(
                title: "Advance", primaryAction: UIAction { [weak self] _ in self?.advance() })
            navigationItem.rightBarButtonItem?.accessibilityIdentifier = "gesture-advance"
        }
        if #available(iOS 16.0, *) {
            let action: (IndexPath) -> Void = { [weak self] path in
                guard let self, let id = self.adapter.rowIdentifier(at: path, as: String.self) else { return }
                self.record("delegate-primary-\(id)")
            }
            if actionKind == "delegate" { primaryDelegate = ProbePrimaryDelegate(action: action) }
            if ["delegate-policy", "dynamic-policy"].contains(actionKind) {
                let policy = ProbePrimaryPolicyDelegate(action: action)
                if actionKind == "dynamic-policy" { policy.allowedPath = nil }
                primaryDelegate = policy
            }
            adapter.collectionDelegate = primaryDelegate
        }
        collection.accessibilityIdentifier = "gesture-collection"
        collection.setCollectionViewLayout(adapter.makeCompositionalLayout(), animated: false)
        status.accessibilityIdentifier = "gesture-state"
        status.isAccessibilityElement = true
        status.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        status.numberOfLines = 0
        status.text = "Preparing…"
        let stack = UIStackView(arrangedSubviews: [collection, status])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -12),
            status.heightAnchor.constraint(equalToConstant: 240)
        ])
        adapter.apply(transaction: .disabled, completion: { [weak self] _ in
            self?.ready = true
            self?.publish()
        }) { self.sections() }
    }

    @ListSectionBuilder<Int>
    private func sections() -> [ListSection<Int>] {
        ListSection(0) {
            DisclosureGroup(
                Row("parent", model: (), cell: UICollectionViewListCell.self) { cell, _, _ in
                    var content = cell.defaultContentConfiguration()
                    content.text = "Collapsed parent"
                    cell.contentConfiguration = content
                    cell.accessibilityIdentifier = "gesture-parent"
                }.outlineDisclosure().outlineAnimation(.disabled),
                isExpanded: false
            ) {
                Row("hidden-child", model: (), cell: UICollectionViewListCell.self) { cell, _, _ in
                    cell.accessibilityIdentifier = "gesture-hidden-child"
                }
            }
            ForEach(["first", "second"], id: \.self) { id in
                self.leaf(id)
            }
        } layout: {
            UIKitListLayout(appearance: .insetGrouped)
        }
        .selectionMode(mode)
        .onExpansionChange { [weak self] _, _ in self?.record("UNEXPECTED-expansion") }
        if companion {
            ListSection(1) {
                Row("other", model: (), cell: UICollectionViewListCell.self) { cell, _, _ in
                    var content = cell.defaultContentConfiguration()
                    content.text = "Other section"
                    cell.contentConfiguration = content
                    cell.accessibilityIdentifier = "gesture-other"
                }
            } layout: {
                UIKitListLayout(appearance: .insetGrouped)
            }.selectionMode(.single)
        }
    }

    private func leaf(_ id: String) -> Row<String, Void, UICollectionViewListCell> {
        var row = Row(id, model: (), cell: UICollectionViewListCell.self) { cell, _, _ in
            var content = cell.defaultContentConfiguration()
            content.text = id == "first" ? "First leaf" : "Second leaf"
            content.secondaryText = "Disclosure row without children"
            cell.contentConfiguration = content
            cell.accessibilityIdentifier = "gesture-\(id)"
        }
        .outlineDisclosure()
        .onSelect { [weak self] _ in self?.record("\(id)-selected") }
        .onDeselect { [weak self] _ in self?.record("\(id)-deselected") }
        .onSelectionChange { [weak self] selected, _ in self?.record("\(id)-changed-\(selected)") }
        let hasAction = ["row", "delegate-policy", "dynamic-policy"].contains(actionKind)
            || (actionKind == "dynamic-row" && phase == 1)
        if #available(iOS 16.0, *), id == "second", hasAction {
            row = row.onPrimaryAction { [weak self] _ in self?.record("second-primary") }
        }
        return row
    }

    private func advance() {
        phase += 1
        if actionKind == "dynamic-row" {
            ready = false
            publish()
            adapter.apply(transaction: .disabled, completion: { [weak self] _ in
                self?.ready = true
                self?.publish()
            }) { self.sections() }
        } else if #available(iOS 16.0, *) {
            if actionKind == "dynamic-delegate" {
                if phase == 1 {
                    primaryDelegate = ProbePrimaryDelegate { [weak self] path in
                        guard let self, let id = self.adapter.rowIdentifier(at: path, as: String.self) else { return }
                        self.record("delegate-primary-\(id)")
                    }
                    adapter.collectionDelegate = primaryDelegate
                } else {
                    // 只释放拥有者引用，确认 adapter 的 weak 属性自动失效。
                    primaryDelegate = nil
                }
            } else if let policy = primaryDelegate as? ProbePrimaryPolicyDelegate {
                policy.allowedPath = phase == 1 ? IndexPath(item: 2, section: 0) : nil
            }
            publish()
        }
    }

    private func selected() -> [String] {
        (collection.indexPathsForSelectedItems ?? []).compactMap {
            adapter.rowIdentifier(at: $0, as: String.self)
        }.sorted()
    }
    private func record(_ event: String) {
        events.append(event)
        callbackSelections.append(selected())
        publish()
    }
    private func publish() {
        let state: [String: Any] = ["phase": phase, "adapterHasDelegate": adapter.collectionDelegate != nil, "ready": ready, "mode": modeName, "companion": companion,
            "selected": selected(), "events": events, "callbackSelections": callbackSelections,
            "allowsMultiple": collection.allowsMultipleSelection]
        let data = try! JSONSerialization.data(withJSONObject: state, options: [.sortedKeys])
        status.accessibilityValue = String(decoding: data, as: UTF8.self)
        status.text = "Selected: \(selected().joined(separator: ", "))\n\n" + events.joined(separator: "\n")
        print("LEAF_GESTURE_STATE " + String(decoding: data, as: UTF8.self))
    }
}

@available(iOS 16.0, *)
@MainActor
private class ProbePrimaryDelegate: NSObject, UICollectionViewDelegate {
    let action: (IndexPath) -> Void
    init(action: @escaping (IndexPath) -> Void) { self.action = action }
    func collectionView(_ collectionView: UICollectionView, performPrimaryActionForItemAt indexPath: IndexPath) {
        action(indexPath)
    }
}

@available(iOS 16.0, *)
@MainActor
private final class ProbePrimaryPolicyDelegate: ProbePrimaryDelegate {
    // 默认允许 first、否决 second；动态场景会切换为允许 second，再全部否决。
    var allowedPath: IndexPath? = IndexPath(item: 1, section: 0)
    func collectionView(_ collectionView: UICollectionView, canPerformPrimaryActionForItemAt indexPath: IndexPath) -> Bool {
        indexPath == allowedPath
    }
}
