import UIKit

@MainActor
final class LiveRoomDemoViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        tabBar.accessibilityIdentifier = "design-scheme-tabs"
        tabBar.tintColor = .systemBlue
        tabBar.unselectedItemTintColor = .secondaryLabel
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior = .onScrollDown
        }

        let liveConsole = makeNavigationController(
            rootViewController: LiveConsoleDesignViewController(),
            title: "Live Console",
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            selectedImage: UIImage(systemName: "dot.radiowaves.left.and.right")
        )

        let studioControl = makeNavigationController(
            rootViewController: StudioControlDesignViewController(),
            title: "Studio Control",
            image: UIImage(systemName: "slider.horizontal.3"),
            selectedImage: UIImage(systemName: "slider.horizontal.3")
        )

        let roomToolkit = makeNavigationController(
            rootViewController: RoomToolkitDesignViewController(),
            title: "Room Toolkit",
            image: UIImage(systemName: "wrench.and.screwdriver"),
            selectedImage: UIImage(systemName: "wrench.and.screwdriver.fill")
        )

        let adminTable = makeNavigationController(
            rootViewController: AdminTableDemoViewController(),
            title: "Admin Table",
            image: UIImage(systemName: "tablecells"),
            selectedImage: UIImage(systemName: "tablecells.fill")
        )

        viewControllers = [liveConsole, studioControl, roomToolkit, adminTable]
        selectedIndex = 0
    }

    private func makeNavigationController(
        rootViewController: UIViewController,
        title: String,
        image: UIImage?,
        selectedImage: UIImage?
    ) -> UINavigationController {
        let navigationController = UINavigationController(rootViewController: rootViewController)
        navigationController.navigationBar.prefersLargeTitles = true
        navigationController.navigationBar.tintColor = .systemBlue
        navigationController.navigationBar.accessibilityIdentifier = "\(title.lowercased().replacingOccurrences(of: " ", with: "-"))-navigation-bar"
        navigationController.tabBarItem = UITabBarItem(
            title: title,
            image: image,
            selectedImage: selectedImage
        )
        return navigationController
    }
}
