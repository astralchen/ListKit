import UIKit

/// 显示 collection 分组标题的触摸索引，支持点选、连续滑动与 VoiceOver 调整。
///
/// 将实例赋给 adapter 的 `sectionIndexView`，并由页面放在列表的语义尾侧。
/// adapter 提交数据后更新标题；没有可定位分组时隐藏。控件不管理列表布局或 inset。
/// `accessibilityLabel` 由调用方提供本地化描述，宽度建议至少 44 pt。
@MainActor
public final class CollectionSectionIndexView: UIControl {
    /// 当前已提交的非空分组标题，顺序与列表一致，允许不同分组使用相同标题。
    public private(set) var titles: [String] = []
    /// 最近一次由触摸或辅助功能选择的标题；更新标题后重置为 `nil`。
    public var selectedTitle: String? { selectedIndex.map { titles[$0] } }
    /// 控件坐标中应避开的区域，默认 `.zero`；修改后请求重新布局。
    ///
    /// 与列表等高布局时，可传入列表的 `adjustedContentInset`，避开导航栏和工具栏。
    /// 此属性不会修改列表本身的 inset。
    public var contentInsets: UIEdgeInsets = .zero {
        didSet {
            guard oldValue != contentInsets else { return }
            setNeedsDisplay()
            setNeedsLayout()
        }
    }
    private var selectedIndex: Int?
    private var selection: ((Int) -> Void)?
    private let indicator = UILabel()
    private let feedback = UISelectionFeedbackGenerator()

    public override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        isAccessibilityElement = true
        accessibilityTraits = .adjustable
        accessibilityIdentifier = "listkit.sectionIndex"
        indicator.font = .systemFont(ofSize: 32, weight: .semibold)
        indicator.textAlignment = .center
        indicator.adjustsFontSizeToFitWidth = true
        indicator.minimumScaleFactor = 0.5
        indicator.textColor = .label
        indicator.backgroundColor = .secondarySystemBackground
        indicator.layer.cornerRadius = 14
        indicator.clipsToBounds = true
        indicator.isUserInteractionEnabled = false
        indicator.isAccessibilityElement = false
        indicator.isHidden = true
        addSubview(indicator)
        isHidden = true
    }

    public required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(titles: [String], selection: ((Int) -> Void)?) {
        self.selection = selection
        if self.titles != titles {
            cancelTracking(with: nil)
            self.titles = titles
            selectedIndex = nil
            accessibilityValue = nil
            invalidateIntrinsicContentSize()
        }
        isHidden = titles.isEmpty
        setNeedsDisplay()
        setNeedsLayout()
    }

    public override var intrinsicContentSize: CGSize { CGSize(width: 44, height: CGFloat(titles.count) * 20 + 16) }

    private var viewport: CGRect {
        let rect = bounds.inset(by: contentInsets)
        return CGRect(x: rect.minX, y: rect.minY, width: max(0, rect.width), height: max(0, rect.height))
    }
    private var rowHeight: CGFloat {
        guard !titles.isEmpty else { return 0 }
        return min(22, max(0, viewport.height - 16) / CGFloat(titles.count))
    }
    private var startY: CGFloat { viewport.minY + (viewport.height - rowHeight * CGFloat(titles.count)) / 2 }

    /// 返回控件坐标中的标题区域；无效索引返回 `.zero`。
    public func rectForTitle(at index: Int) -> CGRect {
        guard titles.indices.contains(index) else { return .zero }
        return CGRect(x: viewport.minX, y: startY + CGFloat(index) * rowHeight, width: viewport.width, height: rowHeight)
    }

    func titleIndex(at point: CGPoint) -> Int? {
        guard !titles.isEmpty, rowHeight > 0 else { return nil }
        return min(titles.count - 1, max(0, Int(floor((point.y - startY) / rowHeight))))
    }

    private var interactionRect: CGRect {
        guard !titles.isEmpty, rowHeight > 0 else { return .zero }
        return CGRect(x: viewport.minX, y: startY - 8, width: viewport.width,
                      height: rowHeight * CGFloat(titles.count) + 16)
    }

    public override var accessibilityFrame: CGRect {
        get { UIAccessibility.convertToScreenCoordinates(interactionRect, in: self) }
        set { super.accessibilityFrame = newValue }
    }

    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        !titles.isEmpty && interactionRect.contains(point)
    }

    // 紧凑窗口稀疏展示字母，触摸映射和 VoiceOver 仍覆盖全部分组。
    var displayedTitleIndices: [Int] {
        guard !titles.isEmpty, rowHeight > 0 else { return [] }
        let step = max(1, Int(ceil(16 / rowHeight)))
        var indices = Array(stride(from: 0, to: titles.count, by: step))
        let last = titles.count - 1
        if let previous = indices.last, previous != last {
            if CGFloat(last - previous) * rowHeight < 16 { indices.removeLast() }
            indices.append(last)
        }
        return indices
    }

    public override func draw(_ rect: CGRect) {
        let scaled = UIFontMetrics(forTextStyle: .caption2).scaledValue(for: 12)
        let font = UIFont.systemFont(ofSize: min(scaled, 14), weight: .semibold)
        for index in displayedTitleIndices {
            let title = titles[index]
            let color: UIColor = index == selectedIndex ? tintColor : .secondaryLabel
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (title as NSString).size(withAttributes: attributes)
            let row = rectForTitle(at: index)
            (title as NSString).draw(at: CGPoint(x: row.midX - size.width / 2, y: row.midY - size.height / 2), withAttributes: attributes)
        }
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        // 索引触摸命中和浮动提示共用控件坐标；提示伸向列表，不占用额外列表空间。
        let x = effectiveUserInterfaceLayoutDirection == .rightToLeft ? bounds.width + 8 : -72
        let centerY = selectedIndex.map { rectForTitle(at: $0).midY } ?? bounds.midY
        indicator.frame = CGRect(x: x, y: max(viewport.minY, min(viewport.maxY - 64, centerY - 32)), width: 64, height: 64)
    }

    public override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard let index = titleIndex(at: touch.location(in: self)) else { return false }
        feedback.prepare()
        select(index, showingIndicator: true)
        return true
    }
    public override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        if let index = titleIndex(at: touch.location(in: self)), index != selectedIndex {
            select(index, showingIndicator: true)
        }
        return true
    }
    public override func endTracking(_ touch: UITouch?, with event: UIEvent?) { indicator.isHidden = true }
    public override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        indicator.isHidden = true
    }
    public override func accessibilityIncrement() {
        select(min(titles.count - 1, (selectedIndex ?? -1) + 1), showingIndicator: false)
    }
    public override func accessibilityDecrement() {
        select(max(0, (selectedIndex ?? titles.count) - 1), showingIndicator: false)
    }
    private func select(_ index: Int, showingIndicator: Bool) {
        guard titles.indices.contains(index) else { return }
        if selectedIndex != index, showingIndicator { feedback.selectionChanged() }
        selectedIndex = index
        accessibilityValue = titles[index]
        indicator.text = titles[index]
        indicator.isHidden = !showingIndicator
        setNeedsDisplay()
        setNeedsLayout()
        selection?(index)
        sendActions(for: .valueChanged)
    }
    public override func tintColorDidChange() { super.tintColorDidChange(); setNeedsDisplay() }
    public override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        setNeedsDisplay()
        setNeedsLayout()
    }
}

#if DEBUG && canImport(SwiftUI)
import SwiftUI

@available(iOS 17.0, *)
#Preview("分组索引") {
    let index = CollectionSectionIndexView()
    index.update(titles: ["A", "B", "C", "L", "Z", "#"], selection: nil)
    return index
}
#endif
