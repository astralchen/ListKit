import ListKit
import UIKit

@MainActor
final class LayoutLabParametersViewController: UIViewController, UITableViewDataSource, UITableViewDelegate {
    private var configuration: LayoutLabConfiguration
    private let onChange: (LayoutLabConfiguration) -> Void
    private let tabs = UISegmentedControl(items: ["参数", "代码"])
    private let table = UITableView(frame: .zero, style: .insetGrouped)
    private let code = UITextView()
    private enum Row {
        case explanation, sizing, alignment, maximum, lines, trackSpacing, lineSpacing, groupOverride, groupSpacing, pin, expanded
    }
    private var rows: [[Row]] {
        configuration.editsGrid
        ? [[.explanation], [.sizing, .alignment, .maximum, .lines], ([.trackSpacing, .lineSpacing, .groupOverride] + (configuration.groupSpacing == nil ? [] : [.groupSpacing])), [.pin, .expanded]]
        : [[.explanation], [.pin, .expanded]]
    }
    init(configuration: LayoutLabConfiguration, onChange: @escaping (LayoutLabConfiguration) -> Void) {
        self.configuration = configuration
        self.onChange = onChange
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        tabs.selectedSegmentIndex = 0
        tabs.accessibilityIdentifier = "lab-parameter-tabs"
        navigationItem.titleView = tabs
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "完成", primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })
        tabs.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.table.isHidden = self.tabs.selectedSegmentIndex == 1
            self.code.isHidden = self.tabs.selectedSegmentIndex == 0
            self.code.text = self.configuration.code
        }, for: .valueChanged)
        table.dataSource = self
        table.delegate = self
        table.accessibilityIdentifier = "lab-parameters"
        code.isEditable = false
        code.isSelectable = true
        code.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        code.adjustsFontForContentSizeCategory = true
        code.textContainerInset = .init(top: 16, left: 12, bottom: 24, right: 12)
        code.accessibilityIdentifier = "lab-code"
        code.backgroundColor = .secondarySystemGroupedBackground
        code.isHidden = true
        code.text = configuration.code
        for child in [table, code] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                child.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
                child.bottomAnchor.constraint(equalTo: view.bottomAnchor)
            ])
        }
    }
    func numberOfSections(in tableView: UITableView) -> Int { rows.count }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { rows[section].count }
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        if section == 0 { return configuration.scene.title }
        if !configuration.editsGrid { return "内容与边界" }
        return ["", "尺寸与轨道", "独立间距 · pt", "内容与边界"][section]
    }
    func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        if section == 0 { return "参数立即应用到预览；切换「代码」查看当前配置对应的布局片段，可选择复制。" }
        if configuration.editsGrid && section == 2 { return "trackSpacing：轨道之间；lineSpacing：组内与默认组间距。开启组间距覆盖后独立设置，关闭则恢复跟随 lineSpacing。" }
        return nil
    }
    private func change(_ update: (inout LayoutLabConfiguration) -> Void) {
        update(&configuration)
        onChange(configuration)
        code.text = configuration.code
        table.reloadData()
    }
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        cell.selectionStyle = .none
        cell.textLabel?.font = .preferredFont(forTextStyle: .subheadline)
        cell.detailTextLabel?.font = .preferredFont(forTextStyle: .caption1)
        cell.detailTextLabel?.numberOfLines = 0
        switch rows[indexPath.section][indexPath.row] {
        case .explanation:
            cell.textLabel?.text = configuration.axisDescription
            cell.detailTextLabel?.text = configuration.explanation
        case .sizing:
            cell.textLabel?.text = "itemMainAxisSize"
            let button = UIButton(type: .system)
            button.setTitle(configuration.sizing.rawValue, for: .normal)
            button.accessibilityIdentifier = "lab-sizing"
            button.showsMenuAsPrimaryAction = true
            button.menu = UIMenu(children: LayoutLabConfiguration.Sizing.available.map { mode in
                UIAction(title: mode.rawValue, state: configuration.sizing == mode ? .on : .off) { [weak self] _ in
                    self?.change { $0.sizing = mode }
                }
            })
            button.sizeToFit()
            cell.accessoryView = button
            cell.detailTextLabel?.text = "自适应使用默认 estimated(44)；同组统一需 iOS 17。"
        case .alignment:
            cell.textLabel?.text = "trackGroupAlignment"
            let selected: Int = configuration.alignment == .start ? 0 : configuration.alignment == .center ? 1 : 2
            let control = UISegmentedControl(items: ["起始", "居中", "末尾"])
            control.selectedSegmentIndex = selected
            control.accessibilityIdentifier = "lab-alignment"
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let control else { return }
                self?.change { $0.alignment = [.start, .center, .end][control.selectedSegmentIndex] }
            }, for: .valueChanged)
            cell.accessoryView = control
        case .maximum:
            cell.textLabel?.text = "弹性／自适应上限 112"
            cell.detailTextLabel?.text = "单轨道与固定轨道不受影响；混合模式弹性轨道上限仍为 100。"
            cell.accessoryView = toggle(id: "lab-maximum", value: configuration.limitMaximum) { $0.limitMaximum = $1 }
        case .lines:
            cell.textLabel?.text = "每组 \(configuration.lines) 行／列"
            cell.accessoryView = stepper(id: "lab-lines", value: Double(configuration.lines), range: 1...4, step: 1) { $0.lines = Int($1) }
        case .trackSpacing:
            cell.textLabel?.text = "trackSpacing · \(Int(configuration.trackSpacing))"
            cell.accessoryView = stepper(id: "lab-track-spacing", value: Double(configuration.trackSpacing)) { $0.trackSpacing = CGFloat($1) }
        case .lineSpacing:
            cell.textLabel?.text = "lineSpacing · \(Int(configuration.lineSpacing))"
            cell.accessoryView = stepper(id: "lab-line-spacing", value: Double(configuration.lineSpacing)) { $0.lineSpacing = CGFloat($1) }
        case .groupOverride:
            cell.textLabel?.text = "覆盖组间距"
            cell.detailTextLabel?.text = configuration.groupSpacing == nil ? "跟随 lineSpacing" : "独立设置 groupSpacing"
            cell.accessoryView = toggle(id: "lab-group-spacing-override", value: configuration.groupSpacing != nil) {
                $0.groupSpacing = $1 ? $0.lineSpacing : nil
            }
        case .groupSpacing:
            cell.textLabel?.text = "groupSpacing · \(Int(configuration.groupSpacing ?? configuration.lineSpacing))"
            cell.accessoryView = stepper(id: "lab-group-spacing", value: Double(configuration.groupSpacing ?? configuration.lineSpacing)) { $0.groupSpacing = CGFloat($1) }
        case .pin:
            cell.textLabel?.text = configuration.horizontal ? "边界标题吸附到起始侧" : "边界标题吸顶"
            cell.accessoryView = toggle(id: "lab-pin", value: configuration.pinHeaders) { $0.pinHeaders = $1 }
            cell.accessoryView?.isUserInteractionEnabled = configuration.scene != .nativeList
            cell.contentView.alpha = configuration.scene == .nativeList ? 0.4 : 1
        case .expanded:
            cell.textLabel?.text = "增加内容"
            cell.detailTextLabel?.text = "自适应／同组统一会重新测量；固定尺寸与宽高比保持不变。"
            cell.accessoryView = toggle(id: "lab-expanded", value: configuration.expanded) { $0.expanded = $1 }
        }
        return cell
    }
    private func toggle(id: String, value: Bool, update: @escaping (inout LayoutLabConfiguration, Bool) -> Void) -> UISwitch {
        let control = UISwitch()
        control.isOn = value
        control.accessibilityIdentifier = id
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let control else { return }
            self?.change { update(&$0, control.isOn) }
        }, for: .valueChanged)
        return control
    }
    private func stepper(id: String, value: Double, range: ClosedRange<Double> = 0...24, step: Double = 2,
                         update: @escaping (inout LayoutLabConfiguration, Double) -> Void) -> UIStepper {
        let control = UIStepper()
        control.minimumValue = range.lowerBound
        control.maximumValue = range.upperBound
        control.stepValue = step
        control.value = value
        control.accessibilityIdentifier = id
        control.addAction(UIAction { [weak self, weak control] _ in
            guard let control else { return }
            self?.change { update(&$0, control.value) }
        }, for: .valueChanged)
        return control
    }
}
