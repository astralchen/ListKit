import ListKit
import UIKit

final class LayoutLabCell: UICollectionViewCell {
    private let label = UILabel()
    private let measurement = UILabel()
    private var sizingAxis: ListLayoutScrollDirection?
    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 10
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.textAlignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(label)
        measurement.font = .monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        measurement.textColor = .white.withAlphaComponent(0.85)
        measurement.textAlignment = .center
        measurement.isAccessibilityElement = false
        contentView.addSubview(measurement)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -8),
            label.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22)
        ])
    }
    func configure(_ item: LayoutLabItem) {
        sizingAxis = item.sizingAxis
        label.text = item.text
        label.numberOfLines = item.sizingAxis == .vertical ? 0 : 1
        label.lineBreakMode = item.sizingAxis == .vertical ? .byWordWrapping : .byTruncatingTail
        label.preferredMaxLayoutWidth = 0
        let colors: [UIColor] = [.systemBlue, .systemTeal, .systemIndigo, .systemOrange, .systemPink, .systemPurple]
        contentView.backgroundColor = colors[item.index % colors.count]
        accessibilityLabel = item.text
    }
    override func preferredLayoutAttributesFitting(_ attributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        guard let sizingAxis else { return attributes }
        let result = attributes.copy() as! UICollectionViewLayoutAttributes
        let horizontal = sizingAxis == .horizontal
        // 在拟合前给多行文字确定交叉轴宽度，避免复用后的单行 intrinsic size 被当作最终高度。
        if !horizontal { label.preferredMaxLayoutWidth = max(1, attributes.size.width - 16) }
        let size = contentView.systemLayoutSizeFitting(
            CGSize(width: horizontal ? 0 : attributes.size.width, height: horizontal ? attributes.size.height : 0),
            withHorizontalFittingPriority: horizontal ? .fittingSizeLevel : .required,
            verticalFittingPriority: horizontal ? .required : .fittingSizeLevel)
        if horizontal { result.size.width = max(44, ceil(size.width)) }
        else { result.size.height = max(44, ceil(size.height)) }
        return result
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        measurement.frame = CGRect(x: 2, y: max(0, contentView.bounds.height - 17), width: max(0, contentView.bounds.width - 4), height: 13)
        measurement.text = "\(Int(bounds.width.rounded())) × \(Int(bounds.height.rounded()))"
        accessibilityValue = measurement.text
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

final class LayoutLabHeader: UICollectionReusableView {
    private let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 2
        label.frame = bounds.insetBy(dx: 8, dy: 0)
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
        isAccessibilityElement = true
    }
    func configure(text: String, identifier: String) {
        label.text = text
        accessibilityLabel = text
        accessibilityIdentifier = identifier
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

final class LayoutLabBackground: UICollectionReusableView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 12
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}

final class LayoutLabBadge: UICollectionReusableView {
    private let label = UILabel()
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemRed
        layer.cornerRadius = 12
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .white
        label.textAlignment = .center
        label.frame = bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .button
    }
    func configure(item: Int) {
        label.text = "\(item + 1)"
        accessibilityLabel = "徽标 \(item)"
        accessibilityIdentifier = "layout-badge-\(item)"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
}
