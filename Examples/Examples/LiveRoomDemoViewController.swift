import UIKit

@MainActor
final class LiveRoomDemoViewController: UITabBarController {
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .systemGroupedBackground
        tabBar.accessibilityIdentifier = "design-scheme-tabs"
        tabBar.tintColor = .systemBlue
        tabBar.unselectedItemTintColor = .secondaryLabel

        let liveConsole = LiveConsoleDesignViewController()
        liveConsole.tabBarItem = UITabBarItem(
            title: "Live Console",
            image: UIImage(systemName: "dot.radiowaves.left.and.right"),
            selectedImage: UIImage(systemName: "dot.radiowaves.left.and.right")
        )

        let studioControl = StudioControlDesignViewController()
        studioControl.tabBarItem = UITabBarItem(
            title: "Studio Control",
            image: UIImage(systemName: "slider.horizontal.3"),
            selectedImage: UIImage(systemName: "slider.horizontal.3")
        )

        let roomToolkit = RoomToolkitDesignViewController()
        roomToolkit.tabBarItem = UITabBarItem(
            title: "Room Toolkit",
            image: UIImage(systemName: "wrench.and.screwdriver"),
            selectedImage: UIImage(systemName: "wrench.and.screwdriver.fill")
        )

        let adminTable = AdminTableDemoViewController()
        adminTable.tabBarItem = UITabBarItem(
            title: "Admin Table",
            image: UIImage(systemName: "tablecells"),
            selectedImage: UIImage(systemName: "tablecells.fill")
        )

        viewControllers = [liveConsole, studioControl, roomToolkit, adminTable]
        selectedIndex = 0
    }
}
