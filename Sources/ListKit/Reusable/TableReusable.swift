import UIKit

// MARK: - Table Reusable

extension UITableViewCell: ReusableView {}
extension UITableViewHeaderFooterView: ReusableView {}

/// `tableView.lk` 命名空间，负责自动注册 class/nib 和类型安全 dequeue。
public struct ListKitTableViewNamespace {
    let tableView: UITableView

    /// 自动注册 table cell class 或同名 nib。
    ///
    /// - Parameter cellType: 要注册的 cell 类型。
    @MainActor public func register<Cell>(_ cellType: Cell.Type) where Cell: UITableViewCell {
        let metadata = listReusableMetadata(for: cellType)
        if let nib = metadata.makeNib() {
            tableView.register(nib, forCellReuseIdentifier: metadata.identifier)
        } else {
            tableView.register(cellType, forCellReuseIdentifier: metadata.identifier)
        }
    }

    /// 自动注册 header/footer view class 或同名 nib。
    ///
    /// - Parameter viewType: 要注册的 header/footer view 类型。
    @MainActor public func registerHeaderFooter<View>(_ viewType: View.Type) where View: UITableViewHeaderFooterView {
        let metadata = listReusableMetadata(for: viewType)
        if let nib = metadata.makeNib() {
            tableView.register(nib, forHeaderFooterViewReuseIdentifier: metadata.identifier)
        } else {
            tableView.register(viewType, forHeaderFooterViewReuseIdentifier: metadata.identifier)
        }
    }

    /// 类型安全 dequeue table cell。
    ///
    /// - Parameters:
    ///   - cellType: 要 dequeue 的 cell 类型。
    ///   - indexPath: cell 所在 index path。
    /// - Returns: 强类型 cell。
    @MainActor public func dequeue<Cell>(_ cellType: Cell.Type, for indexPath: IndexPath) -> Cell where Cell: UITableViewCell {
        tableView.dequeueReusableCell(withIdentifier: Cell.listReuseIdentifier, for: indexPath) as! Cell
    }

    /// 类型安全 dequeue header/footer view。
    ///
    /// - Parameter viewType: 要 dequeue 的 header/footer view 类型。
    /// - Returns: 强类型 header/footer view。
    @MainActor public func dequeueHeaderFooter<View>(_ viewType: View.Type) -> View where View: UITableViewHeaderFooterView {
        tableView.dequeueReusableHeaderFooterView(withIdentifier: View.listReuseIdentifier) as! View
    }
}

public extension UITableView {
    /// ListKit 注册和 dequeue 命名空间。
    var lk: ListKitTableViewNamespace { ListKitTableViewNamespace(tableView: self) }
}
