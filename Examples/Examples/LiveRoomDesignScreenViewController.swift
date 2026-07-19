import UIKit
import ListKit

@MainActor
class LiveRoomDesignScreenViewController: UIViewController {
    let viewModel: LiveRoomViewModel

    private var renderTask: Task<Void, Never>?

    init(viewModel: LiveRoomViewModel = LiveRoomViewModel()) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    final override func viewDidLoad() {
        super.viewDidLoad()
        precondition(
            view is UICollectionView || view is UITableView,
            "Design screens must install a UICollectionView or UITableView as their root view."
        )
        view.backgroundColor = .systemGroupedBackground
        configureNavigation()
        buildContent()
        render(
            transaction: .disabled,
            applicationMode: .reloadData
        )
    }

    func buildContent() {
        preconditionFailure("Subclasses must build their screen content.")
    }

    func configureNavigation() {
        preconditionFailure("Subclasses must configure their navigation item.")
    }

    func render(
        transaction: ListTransaction = .automatic,
        applicationMode: ListSnapshotApplicationMode = .differences
    ) {
        preconditionFailure("Subclasses must render ListKit output.")
    }

    final func scheduleRender(_ operation: @escaping @MainActor () async -> Void) {
        renderTask?.cancel()
        renderTask = Task { @MainActor in
            await operation()
        }
    }

    final func applyNavigationText(
        title: String,
        inlineSubtitle: String,
        largeSubtitle: String
    ) {
        navigationItem.title = title
        navigationItem.largeTitleDisplayMode = .always
        if #available(iOS 26.0, *) {
            navigationItem.subtitle = inlineSubtitle
            navigationItem.largeSubtitle = largeSubtitle
        }
    }
}
