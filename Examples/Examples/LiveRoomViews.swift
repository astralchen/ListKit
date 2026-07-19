import UIKit

final class CapsuleLabel: UILabel {
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.masksToBounds = true
        if #available(iOS 13.0, *) {
            layer.cornerCurve = .continuous
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2
    }
}

@MainActor
private enum LiveRoomActionMenu {
    static func make(
        items: [LiveRoomMenuItem],
        onAction: @escaping @MainActor (LiveRoomMenuAction) -> Void
    ) -> UIMenu {
        func action(for item: LiveRoomMenuItem) -> UIAction {
            UIAction(
                title: item.title,
                image: UIImage(systemName: item.symbolName),
                attributes: item.role == .destructive ? .destructive : [],
                state: item.isSelected ? .on : .off
            ) { _ in
                onAction(item.action)
            }
        }

        let standardActions = items
            .filter { $0.role == .standard }
            .map { action(for: $0) }
        let destructiveActions = items
            .filter { $0.role == .destructive }
            .map { action(for: $0) }
        var children: [UIMenuElement] = standardActions
        if !destructiveActions.isEmpty {
            children.append(
                UIMenu(title: "", options: .displayInline, children: destructiveActions)
            )
        }
        return UIMenu(title: "Actions", children: children)
    }
}

class LiveConsoleHeaderCell: UICollectionViewCell {
    private let titleLabel = UILabel()
    private let subtitleLabel = UILabel()
    private let badgeLabel = CapsuleLabel()
    private let menuButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        titleLabel.font = UIFont.systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.lineBreakMode = .byTruncatingTail

        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true
        subtitleLabel.numberOfLines = 2

        badgeLabel.font = UIFont.systemFont(ofSize: 13, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.textAlignment = .center
        badgeLabel.backgroundColor = .systemIndigo
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .label
        menuButton.backgroundColor = UIColor.tertiarySystemFill
        menuButton.layer.cornerRadius = 22
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = "More Actions"
        menuButton.accessibilityIdentifier = "live-console-header-menu"

        let titleRow = UIStackView(arrangedSubviews: [titleLabel, badgeLabel])
        titleRow.axis = .horizontal
        titleRow.alignment = .center
        titleRow.spacing = 10

        let textStack = UIStackView(arrangedSubviews: [titleRow, subtitleLabel])
        textStack.axis = .vertical
        textStack.spacing = 5

        let row = UIStackView(arrangedSubviews: [textStack, menuButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = 12
        row.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(row)

        NSLayoutConstraint.activate([
            badgeLabel.widthAnchor.constraint(equalToConstant: 64),
            badgeLabel.heightAnchor.constraint(equalToConstant: 24),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
            row.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            row.topAnchor.constraint(equalTo: contentView.topAnchor),
            row.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        accessibilityIdentifier = "live-console-header"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        menuButton.menu = nil
    }

    func setMenuAccessibilityIdentifier(_ identifier: String) {
        menuButton.accessibilityIdentifier = identifier
    }

    func configure(
        _ model: LiveConsoleHeaderViewModel,
        onMenuAction: @escaping @MainActor (LiveRoomMenuAction) -> Void
    ) {
        titleLabel.text = model.title
        subtitleLabel.text = model.subtitle
        badgeLabel.text = "  \(model.badge)  "
        menuButton.menu = LiveRoomActionMenu.make(items: model.menuItems, onAction: onMenuAction)
    }
}

final class StudioControlHeaderCell: LiveConsoleHeaderCell {
    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "studio-control-header"
        setMenuAccessibilityIdentifier("studio-control-header-menu")
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class LiveConsoleToolbarCell: UICollectionViewCell {
    var onAddMessage: (@MainActor () -> Void)?
    var onSendGift: (@MainActor () -> Void)?

    private let addMessageButton = UIButton(type: .system)
    private let sendGiftButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 16
        contentView.layer.masksToBounds = true

        styleActionButton(addMessageButton, symbolName: "text.bubble.fill")
        addMessageButton.accessibilityIdentifier = "live-console-add-message"
        addMessageButton.addTarget(self, action: #selector(addMessageTapped), for: .touchUpInside)

        styleActionButton(sendGiftButton, symbolName: "paperplane.fill")
        sendGiftButton.accessibilityIdentifier = "live-console-send-gift"
        sendGiftButton.addTarget(self, action: #selector(sendGiftTapped), for: .touchUpInside)

        let stack = UIStackView(arrangedSubviews: [addMessageButton, sendGiftButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.distribution = .fillEqually
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        accessibilityIdentifier = "live-console-toolbar"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onAddMessage = nil
        onSendGift = nil
    }

    func configure(_ model: LiveRoomToolbarViewModel) {
        addMessageButton.setDemoActionButtonTitle(model.messageButtonTitle)
        sendGiftButton.setDemoActionButtonTitle(model.giftButtonTitle)
        sendGiftButton.accessibilityValue = "Selected gift: \(model.selectedGiftName)"
    }

    private func styleActionButton(_ button: UIButton, symbolName: String) {
        button.applyDemoActionButtonStyle(symbolName: symbolName)
    }

    @objc private func addMessageTapped() {
        onAddMessage?()
    }

    @objc private func sendGiftTapped() {
        onSendGift?()
    }
}

extension UIButton {
    func applyDemoActionButtonStyle(symbolName: String) {
        titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel?.adjustsFontForContentSizeCategory = true

        if #available(iOS 26.0, *) {
            var configuration = UIButton.Configuration.prominentGlass()
            configuration.image = UIImage(systemName: symbolName)
            configuration.imagePadding = 6
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 11, leading: 12, bottom: 11, trailing: 12)
            configuration.baseForegroundColor = .white
            self.configuration = configuration
            backgroundColor = nil
            layer.cornerRadius = 0
            layer.masksToBounds = false
        } else {
            if #available(iOS 15.0, *) {
                self.configuration = nil
            }
            setImage(UIImage(systemName: symbolName), for: .normal)
            tintColor = .white
            setTitleColor(.white, for: .normal)
            backgroundColor = .systemBlue
            contentEdgeInsets = UIEdgeInsets(top: 11, left: 12, bottom: 11, right: 12)
            layer.cornerRadius = 12
            layer.masksToBounds = true
        }
    }

    func setDemoActionButtonTitle(_ title: String) {
        if #available(iOS 26.0, *) {
            var configuration = configuration ?? UIButton.Configuration.prominentGlass()
            configuration.title = title
            self.configuration = configuration
        } else {
            setTitle(" \(title)", for: .normal)
        }
    }
}

final class StudioControlPanelCell: UICollectionViewCell {
    var onModeChange: (@MainActor (Int) -> Void)?

    private let segmentControl = UISegmentedControl(items: ["Room", "Gifts", "Logs"])
    private let summaryLabel = UILabel()
    private let chipStack = UIStackView()
    private let audienceMetric = StudioMetricView(symbolName: "person.2.fill", tint: .systemBlue)
    private let heatMetric = StudioMetricView(symbolName: "heart.fill", tint: .systemPink)
    private let adminMetric = StudioMetricView(symbolName: "shield.fill", tint: .systemGreen)

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .secondarySystemGroupedBackground
        contentView.layer.cornerRadius = 16
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor
        contentView.layer.masksToBounds = true

        segmentControl.accessibilityIdentifier = "studio-control-segment"
        segmentControl.addTarget(self, action: #selector(segmentChanged), for: .valueChanged)

        chipStack.axis = .horizontal
        chipStack.alignment = .center
        chipStack.distribution = .fillProportionally
        chipStack.spacing = 8

        let titleLabel = UILabel()
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.text = "Room Overview"

        summaryLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        summaryLabel.textColor = .secondaryLabel
        summaryLabel.numberOfLines = 2
        summaryLabel.adjustsFontForContentSizeCategory = true

        audienceMetric.configure(value: "1,248", label: "Audience")
        heatMetric.configure(value: "8,932", label: "Heat")
        adminMetric.configure(value: "7", label: "Admin")

        let metricsStack = UIStackView(arrangedSubviews: [audienceMetric, heatMetric, adminMetric])
        metricsStack.axis = .horizontal
        metricsStack.alignment = .fill
        metricsStack.distribution = .fillEqually
        metricsStack.spacing = 8

        let contentStack = UIStackView(arrangedSubviews: [segmentControl, chipStack, titleLabel, summaryLabel, metricsStack])
        contentStack.axis = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(contentStack)

        NSLayoutConstraint.activate([
            segmentControl.heightAnchor.constraint(equalToConstant: 34),
            contentStack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            contentStack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            contentStack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            contentStack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])

        accessibilityIdentifier = "studio-control-panel"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onModeChange = nil
    }

    func configure(_ model: StudioControlPanelViewModel) {
        segmentControl.selectedSegmentIndex = model.selectedModeIndex
        summaryLabel.text = model.summary

        chipStack.arrangedSubviews.forEach { view in
            chipStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for chipTitle in model.chips {
            chipStack.addArrangedSubview(makeChip(title: chipTitle))
        }
    }

    private func makeChip(title: String) -> UIButton {
        let chip = UIButton(type: .system)
        chip.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        chip.setTitle(title, for: .normal)
        chip.setTitleColor(.label, for: .normal)
        chip.backgroundColor = .systemBackground
        chip.layer.cornerRadius = 12
        chip.contentEdgeInsets = UIEdgeInsets(top: 6, left: 10, bottom: 6, right: 10)
        return chip
    }

    @objc private func segmentChanged() {
        onModeChange?(segmentControl.selectedSegmentIndex)
    }
}

private final class StudioMetricView: UIView {
    private let iconView = UIImageView()
    private let valueLabel = UILabel()
    private let labelView = UILabel()

    init(symbolName: String, tint: UIColor) {
        super.init(frame: .zero)
        backgroundColor = .systemBackground
        layer.cornerRadius = 12

        iconView.image = UIImage(systemName: symbolName)
        iconView.tintColor = tint
        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false

        valueLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold)
        valueLabel.textColor = .label
        valueLabel.adjustsFontForContentSizeCategory = true

        labelView.font = UIFont.preferredFont(forTextStyle: .caption2)
        labelView.textColor = .secondaryLabel
        labelView.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [valueLabel, labelView])
        textStack.axis = .vertical
        textStack.spacing = 1

        let stack = UIStackView(arrangedSubviews: [iconView, textStack])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 18),
            iconView.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(value: String, label: String) {
        valueLabel.text = value
        labelView.text = label
    }
}

final class RoomHeroView: UIView {
    private let avatarView = UIImageView()
    private let titleLabel = UILabel()
    private let badgeLabel = CapsuleLabel()
    private let subtitleLabel = UILabel()
    private let statsLabel = UILabel()
    private let menuButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear

        avatarView.image = UIImage(systemName: "house.lodge.circle.fill")
        avatarView.tintColor = .systemGreen
        avatarView.contentMode = .scaleAspectFill
        avatarView.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        avatarView.layer.cornerRadius = 30
        avatarView.layer.masksToBounds = true
        avatarView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.systemFont(ofSize: 26, weight: .bold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.adjustsFontSizeToFitWidth = true
        titleLabel.minimumScaleFactor = 0.82
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        badgeLabel.font = UIFont.systemFont(ofSize: 14, weight: .bold)
        badgeLabel.textColor = .white
        badgeLabel.text = " LIVE  ● "
        badgeLabel.backgroundColor = .systemIndigo
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        subtitleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.adjustsFontForContentSizeCategory = true

        statsLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        statsLabel.textColor = .secondaryLabel
        statsLabel.adjustsFontForContentSizeCategory = true
        statsLabel.adjustsFontSizeToFitWidth = true
        statsLabel.minimumScaleFactor = 0.86

        menuButton.setImage(UIImage(systemName: "ellipsis"), for: .normal)
        menuButton.tintColor = .label
        menuButton.backgroundColor = UIColor.tertiarySystemFill
        menuButton.layer.cornerRadius = 22
        menuButton.translatesAutoresizingMaskIntoConstraints = false
        menuButton.showsMenuAsPrimaryAction = true
        menuButton.accessibilityLabel = "More Actions"
        menuButton.accessibilityIdentifier = "room-toolkit-header-menu"

        let titleStack = UIStackView(arrangedSubviews: [titleLabel, badgeLabel])
        titleStack.axis = .horizontal
        titleStack.alignment = .center
        titleStack.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [titleStack, subtitleLabel, statsLabel])
        textStack.axis = .vertical
        textStack.spacing = 4

        let stack = UIStackView(arrangedSubviews: [avatarView, textStack, menuButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            avatarView.widthAnchor.constraint(equalToConstant: 60),
            avatarView.heightAnchor.constraint(equalToConstant: 60),
            menuButton.widthAnchor.constraint(equalToConstant: 44),
            menuButton.heightAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 18),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        accessibilityIdentifier = "room-toolkit-hero"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        _ model: LiveRoomTitleViewModel,
        onMenuAction: @escaping @MainActor (LiveRoomMenuAction) -> Void
    ) {
        titleLabel.text = model.title
        subtitleLabel.text = model.subtitle
        statsLabel.text = "\(model.viewerText)    \(model.heatText) heat    \(model.liveEventCount) live events"
        menuButton.menu = LiveRoomActionMenu.make(items: model.menuItems, onAction: onMenuAction)
    }

    func clearMenu() {
        menuButton.menu = nil
    }
}

final class RoomHeroCell: UICollectionViewCell {
    private let heroView = RoomHeroView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        heroView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(heroView)

        NSLayoutConstraint.activate([
            heroView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            heroView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            heroView.topAnchor.constraint(equalTo: contentView.topAnchor),
            heroView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        heroView.clearMenu()
    }

    func configure(
        _ model: LiveRoomTitleViewModel,
        onMenuAction: @escaping @MainActor (LiveRoomMenuAction) -> Void
    ) {
        heroView.configure(model, onMenuAction: onMenuAction)
    }
}

final class RoomMetricStripView: UIView {
    private let liveMetric = StripMetricView(accent: .systemRed)
    private let qualityMetric = StripMetricView(accent: .systemGreen)
    private let hostMetric = StripMetricView(accent: .systemGreen)
    private let micMetric = StripMetricView(accent: .systemBlue)
    private let stageMetric = StripMetricView(accent: .label)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemBackground
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.05
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)

        let stack = UIStackView(arrangedSubviews: [liveMetric, qualityMetric, hostMetric, micMetric, stageMetric])
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -12)
        ])

        liveMetric.configure(symbolName: "livephoto", title: "LIVE", detail: "12:34", usesBadge: true)
        qualityMetric.configure(symbolName: "chart.bar.fill", title: "Excellent", detail: "", usesBadge: false)
        hostMetric.configure(symbolName: "person.crop.circle.fill", title: "Host", detail: "Alex", usesBadge: false)
        micMetric.configure(symbolName: "mic.fill", title: "Mic On", detail: "", usesBadge: false)
        stageMetric.configure(symbolName: "person.2.fill", title: "5", detail: "On Stage", usesBadge: false)
        accessibilityIdentifier = "room-metric-strip"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: RoomStatusViewModel) {
        liveMetric.configure(symbolName: "livephoto", title: model.mode, detail: "12:34", usesBadge: true)
        qualityMetric.configure(symbolName: "chart.bar.fill", title: "Excellent", detail: "", usesBadge: false)
        hostMetric.configure(symbolName: "person.crop.circle.fill", title: "Host", detail: model.hostName, usesBadge: false)
        micMetric.configure(symbolName: "mic.fill", title: "Mic On", detail: "", usesBadge: false)
        stageMetric.configure(symbolName: "person.2.fill", title: "5", detail: "On Stage", usesBadge: false)
    }
}

final class RoomMetricStripCell: UICollectionViewCell {
    private let stripView = RoomMetricStripView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        stripView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stripView)

        NSLayoutConstraint.activate([
            stripView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stripView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stripView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stripView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: RoomStatusViewModel) {
        stripView.configure(model)
    }
}

final class RoomActivityTitleCell: UICollectionViewCell {
    private let titleLabel = UILabel()
    private let filterButton = UIButton(type: .system)
    private var onFilterChange: ((RoomActivityFilter) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear

        titleLabel.font = UIFont.preferredFont(forTextStyle: .title2)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        filterButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .subheadline)
        filterButton.tintColor = .systemBlue
        filterButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        filterButton.showsMenuAsPrimaryAction = true
        filterButton.accessibilityIdentifier = "room-toolkit-activity-filter"

        let stack = UIStackView(arrangedSubviews: [titleLabel, UIView(), filterButton])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        accessibilityIdentifier = "room-toolkit-activity-title"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onFilterChange = nil
        filterButton.menu = nil
    }

    func configure(
        _ model: RoomActivityTitleViewModel,
        onFilterChange: @escaping (RoomActivityFilter) -> Void
    ) {
        self.onFilterChange = onFilterChange
        titleLabel.text = model.title
        filterButton.setTitle(model.buttonTitle, for: .normal)
        filterButton.setImage(UIImage(systemName: model.symbolName), for: .normal)
        filterButton.accessibilityLabel = "Filter Live Activity"
        filterButton.accessibilityValue = model.selectedFilter.title
        let actions = RoomActivityFilter.allCases.map { [weak self] filter in
            UIAction(
                title: filter.title,
                image: UIImage(systemName: filter.symbolName),
                state: filter == model.selectedFilter ? .on : .off
            ) { _ in
                self?.selectFilter(filter)
            }
        }
        let options: UIMenu.Options
        if #available(iOS 15.0, *) {
            options = .singleSelection
        } else {
            options = []
        }
        filterButton.menu = UIMenu(
            title: "Show",
            image: nil,
            identifier: nil,
            options: options,
            children: actions
        )
    }

    private func selectFilter(_ filter: RoomActivityFilter) {
        filterButton.menu?.children
            .compactMap { $0 as? UIAction }
            .forEach { action in
                action.state = action.title == filter.title ? .on : .off
            }
        filterButton.accessibilityValue = filter.title
        onFilterChange?(filter)
    }
}

final class LiveSectionBackgroundView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemGroupedBackground
        layer.cornerRadius = 8
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class LiveActivityBackgroundView: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.secondarySystemGroupedBackground
        layer.cornerRadius = 16
        layer.borderWidth = 1
        layer.borderColor = UIColor.separator.cgColor
        layer.masksToBounds = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

final class SectionHeaderView: UICollectionReusableView {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        detailLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .right

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String) {
        titleLabel.text = title
        detailLabel.text = detail
        accessibilityIdentifier = "section-\(title.lowercased().replacingOccurrences(of: " ", with: "-"))"
    }
}

final class LiveRoomStatusCell: UICollectionViewCell {
    private let badgeLabel = CapsuleLabel()
    private let titleLabel = UILabel()
    private let hostLabel = UILabel()
    private let viewerMetric = MetricView(symbolName: "person.2.fill")
    private let heatMetric = MetricView(symbolName: "bolt.fill")
    private let moderationMetric = MetricView(symbolName: "shield.lefthalf.filled")

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.masksToBounds = true
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor

        badgeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        badgeLabel.adjustsFontForContentSizeCategory = true
        badgeLabel.textColor = .systemGreen
        badgeLabel.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
        badgeLabel.textAlignment = .center

        titleLabel.font = UIFont.preferredFont(forTextStyle: .title3)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 1
        titleLabel.lineBreakMode = .byTruncatingTail

        hostLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        hostLabel.adjustsFontForContentSizeCategory = true
        hostLabel.textColor = .secondaryLabel

        let metricStack = UIStackView(arrangedSubviews: [viewerMetric, heatMetric, moderationMetric])
        metricStack.axis = .horizontal
        metricStack.alignment = .fill
        metricStack.distribution = .fillEqually
        metricStack.spacing = 8

        let headerStack = UIStackView(arrangedSubviews: [badgeLabel, UIView()])
        headerStack.axis = .horizontal
        headerStack.alignment = .leading
        badgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 88).isActive = true
        badgeLabel.heightAnchor.constraint(equalToConstant: 26).isActive = true

        let stack = UIStackView(arrangedSubviews: [headerStack, titleLabel, hostLabel, metricStack])
        stack.axis = .vertical
        stack.alignment = .fill
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12)
        ])

        accessibilityIdentifier = "live-room-status"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: RoomStatusViewModel) {
        badgeLabel.text = "  \(model.mode)  "
        titleLabel.text = model.roomName
        hostLabel.text = "Host \(model.hostName)"
        viewerMetric.configure(title: model.viewerText, detail: "Audience")
        heatMetric.configure(title: model.heatText, detail: "Heat")
        moderationMetric.configure(title: model.moderationText, detail: "Admin")
    }
}

final class MicSeatCell: UICollectionViewCell {
    private let avatarLabel = UILabel()
    private let nameLabel = UILabel()
    private let roleLabel = UILabel()
    private let statusLabel = UILabel()

    override var isSelected: Bool {
        didSet { updateSelectionStyle(isSelected: isSelected) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor

        avatarLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        avatarLabel.adjustsFontForContentSizeCategory = true
        avatarLabel.textAlignment = .center
        avatarLabel.textColor = .white
        avatarLabel.backgroundColor = .systemIndigo
        avatarLabel.layer.cornerRadius = 22
        avatarLabel.layer.masksToBounds = true
        avatarLabel.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail

        roleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        roleLabel.adjustsFontForContentSizeCategory = true
        roleLabel.textColor = .secondaryLabel
        roleLabel.textAlignment = .center

        statusLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        statusLabel.adjustsFontForContentSizeCategory = true
        statusLabel.textAlignment = .center
        statusLabel.layer.cornerRadius = 4
        statusLabel.layer.masksToBounds = true

        let stack = UIStackView(arrangedSubviews: [avatarLabel, nameLabel, roleLabel, statusLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            avatarLabel.widthAnchor.constraint(equalToConstant: 44),
            avatarLabel.heightAnchor.constraint(equalToConstant: 44),
            statusLabel.widthAnchor.constraint(equalTo: contentView.widthAnchor, constant: -14),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 7),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -7),
            stack.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: MicSeat) {
        avatarLabel.text = String(model.nickname.prefix(1))
        nameLabel.text = model.nickname
        roleLabel.text = model.role
        statusLabel.text = model.isMuted ? "Muted" : (model.isSpeaking ? "Live" : "Ready")
        statusLabel.textColor = model.isSpeaking ? .systemGreen : .secondaryLabel
        statusLabel.backgroundColor = model.isSpeaking ? UIColor.systemGreen.withAlphaComponent(0.12) : UIColor.tertiarySystemFill
        accessibilityIdentifier = "mic-seat-\(model.id)"
        updateSelectionStyle(isSelected: model.isSpeaking || isSelected)
    }

    private func updateSelectionStyle(isSelected: Bool) {
        contentView.layer.borderColor = (isSelected ? UIColor.systemGreen : UIColor.separator).cgColor
        contentView.layer.borderWidth = isSelected ? 2 : 1
    }
}

final class LiveMessageCell: UICollectionViewCell {
    private let avatarLabel = UILabel()
    private let onlineDot = UIView()
    private let senderLabel = UILabel()
    private let timeLabel = UILabel()
    private let messageLabel = UILabel()
    private let replyLabel = UILabel()
    private let likeLabel = UILabel()
    private let giftImageView = UIImageView()
    private let giftBadgeLabel = UILabel()
    private var giftImageWidthConstraint: NSLayoutConstraint!
    private var giftImageHeightConstraint: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 0

        avatarLabel.font = UIFont.systemFont(ofSize: 18, weight: .semibold)
        avatarLabel.textColor = .white
        avatarLabel.textAlignment = .center
        avatarLabel.backgroundColor = .systemGray2
        avatarLabel.layer.cornerRadius = 22
        avatarLabel.layer.masksToBounds = true
        avatarLabel.translatesAutoresizingMaskIntoConstraints = false

        onlineDot.backgroundColor = .systemGreen
        onlineDot.layer.cornerRadius = 6
        onlineDot.layer.borderWidth = 2
        onlineDot.layer.borderColor = UIColor.secondarySystemGroupedBackground.cgColor
        onlineDot.translatesAutoresizingMaskIntoConstraints = false

        senderLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        senderLabel.adjustsFontForContentSizeCategory = true
        senderLabel.textColor = .label
        senderLabel.lineBreakMode = .byTruncatingTail

        timeLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        timeLabel.adjustsFontForContentSizeCategory = true
        timeLabel.textColor = .tertiaryLabel
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        messageLabel.font = UIFont.preferredFont(forTextStyle: .body)
        messageLabel.adjustsFontForContentSizeCategory = true
        messageLabel.textColor = .label
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping

        replyLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        replyLabel.adjustsFontForContentSizeCategory = true
        replyLabel.textColor = .secondaryLabel
        replyLabel.text = "Reply"

        likeLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        likeLabel.adjustsFontForContentSizeCategory = true
        likeLabel.textColor = .systemRed
        likeLabel.textAlignment = .right

        giftImageView.image = UIImage(systemName: "paperplane.circle.fill")
        giftImageView.tintColor = .systemRed
        giftImageView.contentMode = .scaleAspectFit
        giftImageView.translatesAutoresizingMaskIntoConstraints = false

        giftBadgeLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        giftBadgeLabel.textColor = .systemPink
        giftBadgeLabel.text = "Top Gifter"
        giftBadgeLabel.textAlignment = .center
        giftBadgeLabel.backgroundColor = UIColor.systemPink.withAlphaComponent(0.12)
        giftBadgeLabel.layer.cornerRadius = 10
        giftBadgeLabel.layer.masksToBounds = true

        let nameStack = UIStackView(arrangedSubviews: [senderLabel, timeLabel])
        nameStack.axis = .horizontal
        nameStack.alignment = .firstBaseline
        nameStack.spacing = 8

        let textStack = UIStackView(arrangedSubviews: [nameStack, messageLabel, giftBadgeLabel, replyLabel])
        textStack.axis = .vertical
        textStack.spacing = 6
        textStack.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textStack.setContentHuggingPriority(.defaultLow, for: .horizontal)

        let avatarContainer = UIView()
        avatarContainer.addSubview(avatarLabel)
        avatarContainer.addSubview(onlineDot)

        let stack = UIStackView(arrangedSubviews: [avatarContainer, textStack, giftImageView, likeLabel])
        stack.axis = .horizontal
        stack.alignment = .top
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        giftImageWidthConstraint = giftImageView.widthAnchor.constraint(equalToConstant: 86)
        giftImageWidthConstraint.priority = .defaultHigh
        giftImageHeightConstraint = giftImageView.heightAnchor.constraint(equalToConstant: 76)

        NSLayoutConstraint.activate([
            avatarContainer.widthAnchor.constraint(equalToConstant: 48),
            avatarContainer.heightAnchor.constraint(equalToConstant: 48),
            avatarLabel.widthAnchor.constraint(equalToConstant: 44),
            avatarLabel.heightAnchor.constraint(equalToConstant: 44),
            avatarLabel.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            avatarLabel.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            onlineDot.widthAnchor.constraint(equalToConstant: 12),
            onlineDot.heightAnchor.constraint(equalToConstant: 12),
            onlineDot.trailingAnchor.constraint(equalTo: avatarLabel.trailingAnchor),
            onlineDot.bottomAnchor.constraint(equalTo: avatarLabel.bottomAnchor),
            giftImageWidthConstraint,
            giftImageHeightConstraint,
            likeLabel.widthAnchor.constraint(equalToConstant: 44),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: LiveMessage) {
        avatarLabel.text = String(model.sender.prefix(1))
        avatarLabel.backgroundColor = color(for: model.tone)
        senderLabel.text = model.sender
        timeLabel.text = timeText(for: model.id)
        messageLabel.text = model.text
        messageLabel.numberOfLines = model.tone == "gift" ? 2 : 0
        likeLabel.text = model.tone == "hot" ? "12" : (model.tone == "gift" ? "x 10" : "7")
        likeLabel.textColor = model.tone == "gift" ? .systemPurple : (model.tone == "hot" ? .systemRed : .secondaryLabel)
        let isGift = model.tone == "gift"
        giftImageWidthConstraint.isActive = false
        giftImageHeightConstraint.isActive = false
        giftImageView.isHidden = !isGift
        giftBadgeLabel.isHidden = !isGift
        replyLabel.isHidden = isGift
        if isGift {
            NSLayoutConstraint.activate([
                giftImageWidthConstraint,
                giftImageHeightConstraint
            ])
        }
        accessibilityIdentifier = "live-message-\(model.id)"
    }

    private func color(for tone: String) -> UIColor {
        switch tone {
        case "host": return .systemBlue
        case "gift": return .systemPink
        case "hot": return .systemGreen
        case "system": return .systemGreen
        default: return .systemGray2
        }
    }

    private func timeText(for id: String) -> String {
        switch id {
        case "msg-1": return "just now"
        case "msg-2": return "30s ago"
        case "msg-3": return "1m ago"
        default: return "2m ago"
        }
    }
}

final class GiftCell: UICollectionViewCell {
    var onSend: (@MainActor () -> Void)?

    private let symbolView = UIImageView()
    private let titleLabel = UILabel()
    private let metaLabel = UILabel()
    private let sendButton = UIButton(type: .system)

    override var isSelected: Bool {
        didSet { updateSelectionStyle(isSelected: isSelected) }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .systemBackground
        contentView.layer.cornerRadius = 8
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor

        symbolView.contentMode = .scaleAspectFit
        symbolView.tintColor = .systemPink
        symbolView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        metaLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        metaLabel.adjustsFontForContentSizeCategory = true
        metaLabel.textColor = .secondaryLabel

        sendButton.setImage(UIImage(systemName: "paperplane.fill"), for: .normal)
        sendButton.setTitle(" Send", for: .normal)
        sendButton.titleLabel?.font = UIFont.preferredFont(forTextStyle: .caption1)
        sendButton.addTarget(self, action: #selector(sendTapped), for: .touchUpInside)

        let textStack = UIStackView(arrangedSubviews: [titleLabel, metaLabel, sendButton])
        textStack.axis = .vertical
        textStack.alignment = .leading
        textStack.spacing = 4

        let stack = UIStackView(arrangedSubviews: [symbolView, textStack])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            symbolView.widthAnchor.constraint(equalToConstant: 30),
            symbolView.heightAnchor.constraint(equalToConstant: 30),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        onSend = nil
    }

    func configure(_ model: GiftItem) {
        symbolView.image = UIImage(systemName: model.symbolName)
        titleLabel.text = model.name
        metaLabel.text = "\(model.price) coins · sent \(model.sentCount)"
        accessibilityIdentifier = "gift-\(model.id)"
        sendButton.accessibilityIdentifier = "gift-send-\(model.id)"
        updateSelectionStyle(isSelected: model.isSelected || isSelected)
    }

    private func updateSelectionStyle(isSelected: Bool) {
        contentView.layer.borderColor = (isSelected ? UIColor.systemPink : UIColor.separator).cgColor
        contentView.layer.borderWidth = isSelected ? 2 : 1
        contentView.backgroundColor = isSelected ? UIColor.systemPink.withAlphaComponent(0.08) : .systemBackground
    }

    @objc private func sendTapped() {
        onSend?()
    }
}

final class DiagnosticsCell: UICollectionViewCell {
    private let titleLabel = UILabel()
    private let summaryLabel = UILabel()
    private let refreshLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = UIColor.systemGray6
        contentView.layer.cornerRadius = 8

        titleLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .secondaryLabel
        titleLabel.text = "ListKit apply summary"

        summaryLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        summaryLabel.textColor = .label
        summaryLabel.adjustsFontForContentSizeCategory = true

        refreshLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        refreshLabel.textColor = .secondaryLabel
        refreshLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, summaryLabel, refreshLabel])
        stack.axis = .vertical
        stack.spacing = 3
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8)
        ])

        accessibilityIdentifier = "listkit-diagnostics"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: ApplyDiagnostics) {
        summaryLabel.text = model.summaryText
        refreshLabel.text = model.refreshText
    }
}

final class AdminEventTableCell: UITableViewCell {
    private let selectionImageView = UIImageView()
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let chevronView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        contentView.backgroundColor = .systemBackground

        selectionImageView.contentMode = .scaleAspectFit
        selectionImageView.translatesAutoresizingMaskIntoConstraints = false

        iconContainer.layer.cornerRadius = 22
        iconContainer.translatesAutoresizingMaskIntoConstraints = false

        iconView.contentMode = .scaleAspectFit
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.addSubview(iconView)

        titleLabel.font = UIFont.preferredFont(forTextStyle: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        detailLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel

        chevronView.image = UIImage(systemName: "chevron.right")
        chevronView.tintColor = .tertiaryLabel
        chevronView.contentMode = .scaleAspectFit
        chevronView.translatesAutoresizingMaskIntoConstraints = false

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 3

        let stack = UIStackView(arrangedSubviews: [selectionImageView, iconContainer, textStack, chevronView])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            selectionImageView.widthAnchor.constraint(equalToConstant: 24),
            selectionImageView.heightAnchor.constraint(equalToConstant: 24),
            iconContainer.widthAnchor.constraint(equalToConstant: 44),
            iconContainer.heightAnchor.constraint(equalToConstant: 44),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 24),
            iconView.heightAnchor.constraint(equalToConstant: 24),
            chevronView.widthAnchor.constraint(equalToConstant: 16),
            chevronView.heightAnchor.constraint(equalToConstant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -10)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(_ model: ModerationEvent) {
        selectionImageView.image = UIImage(systemName: model.isSelected ? "checkmark.circle.fill" : "circle")
        selectionImageView.tintColor = model.isSelected ? .systemBlue : .systemGray3
        titleLabel.text = model.title
        detailLabel.text = model.detail
        iconView.image = UIImage(systemName: iconName(for: model.kind))
        iconView.tintColor = iconColor(for: model.kind)
        iconContainer.backgroundColor = iconColor(for: model.kind).withAlphaComponent(0.14)
        accessibilityIdentifier = "admin-event-\(model.id)"
    }

    private func iconName(for kind: ModerationEventKind) -> String {
        switch kind {
        case .moderator: return "shield.fill"
        case .flaggedMessage: return "flag.fill"
        case .muted: return "person.crop.circle.badge.xmark"
        case .topGifter: return "star.fill"
        case .announcement: return "megaphone.fill"
        case .userLeft: return "rectangle.portrait.and.arrow.right"
        case .goalReached: return "gift.fill"
        }
    }

    private func iconColor(for kind: ModerationEventKind) -> UIColor {
        switch kind {
        case .moderator, .goalReached: return .systemGreen
        case .flaggedMessage: return .systemOrange
        case .muted: return .systemIndigo
        case .topGifter: return .systemYellow
        case .announcement: return .systemBlue
        case .userLeft: return .systemPink
        }
    }
}

final class AdminHeaderView: UITableViewHeaderFooterView {
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = .systemGroupedBackground

        titleLabel.font = UIFont.preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .label

        detailLabel.font = UIFont.preferredFont(forTextStyle: .caption1)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .right

        let stack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        accessibilityIdentifier = "moderation-header"
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String) {
        titleLabel.text = title
        detailLabel.text = detail
    }
}

private final class MetricView: UIView {
    private let imageView = UIImageView()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()

    init(symbolName: String) {
        super.init(frame: .zero)
        imageView.image = UIImage(systemName: symbolName)
        imageView.tintColor = .systemBlue
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.adjustsFontForContentSizeCategory = true

        detailLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        detailLabel.textColor = .secondaryLabel
        detailLabel.adjustsFontForContentSizeCategory = true

        let textStack = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        textStack.axis = .vertical
        textStack.spacing = 1

        let stack = UIStackView(arrangedSubviews: [imageView, textStack])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            imageView.widthAnchor.constraint(equalToConstant: 18),
            imageView.heightAnchor.constraint(equalToConstant: 18),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, detail: String) {
        titleLabel.text = title
        detailLabel.text = detail
    }
}

private final class StripMetricView: UIView {
    private let iconContainer = UIView()
    private let iconView = UIImageView()
    private let titleLabel = CapsuleLabel()
    private let detailLabel = UILabel()
    private let accent: UIColor

    init(accent: UIColor) {
        self.accent = accent
        super.init(frame: .zero)

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = accent
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.translatesAutoresizingMaskIntoConstraints = false
        iconContainer.accessibilityIdentifier = "room-metric-icon-container"
        iconContainer.addSubview(iconView)

        titleLabel.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .label
        titleLabel.textAlignment = .center
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        detailLabel.font = UIFont.preferredFont(forTextStyle: .caption2)
        detailLabel.textColor = .secondaryLabel
        detailLabel.textAlignment = .center
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconContainer)
        addSubview(titleLabel)
        addSubview(detailLabel)

        NSLayoutConstraint.activate([
            iconContainer.widthAnchor.constraint(equalToConstant: 26),
            iconContainer.heightAnchor.constraint(equalToConstant: 26),
            iconContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconContainer.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            iconView.widthAnchor.constraint(equalToConstant: 26),
            iconView.heightAnchor.constraint(equalToConstant: 26),
            iconView.centerXAnchor.constraint(equalTo: iconContainer.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconContainer.centerYAnchor),
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            titleLabel.topAnchor.constraint(equalTo: iconContainer.bottomAnchor, constant: 4),
            detailLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            detailLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 4),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(symbolName: String, title: String, detail: String, usesBadge: Bool) {
        iconView.image = UIImage(systemName: symbolName)
        titleLabel.text = usesBadge ? "  \(title)  " : title
        detailLabel.text = detail.isEmpty ? " " : detail
        titleLabel.textColor = usesBadge ? .white : .label
        titleLabel.backgroundColor = usesBadge ? accent : .clear
    }
}
