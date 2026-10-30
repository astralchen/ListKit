import Testing
import UIKit
@testable import Examples
@testable import ListKit

@MainActor
struct LayoutLabConfigurationTests {
    @Test func measuredBadgesRecipeAndCodeMatch() {
        var config = LayoutLabConfiguration()
        config.scene = .badges
        let grid = config.recipe(section: 0).makeGrid()
        #expect(grid.itemMainAxisSize == .estimated(44))
        #expect(grid.grouping == .count(lines: 3))
        #expect(grid.scrollingBehavior == .continuous)
        #expect(config.code.contains("ItemSupplementaryLayout(kind: \"lab.badge\""))
        #expect(config.code.contains("SectionSupplementary(LayoutLabBadge.self"))
    }

    @Test func parametersDriveLayoutAndCodeTogether() throws {
        var config = LayoutLabConfiguration()
        config.trackMode = .fixed
        config.sizing = .ratio
        config.trackSpacing = 12
        config.lineSpacing = 4
        config.groupSpacing = 18
        config.lines = 3
        config.alignment = .center
        config.pinHeaders = false
        let grid = config.recipe(section: 0).makeGrid()
        #expect(grid.itemMainAxisSize == .aspectRatio(1))
        #expect(grid.trackSpacing == 12 && grid.lineSpacing == 4 && grid.groupSpacing == 18)
        #expect(grid.grouping == .count(lines: 3))
        #expect(grid.crossAlignment == .center)
        let geometry = try grid.geometry(in: TestLayoutEnvironment(), scrollDirection: .vertical)
        #expect(geometry.tracks.map(\.extent) == [60, 60, 60])
        for fragment in [".aspectRatio(1)", ".trackSpacing(12)", ".lineSpacing(4)", ".groupSpacing(18)",
                         ".count(lines: 3)", ".trackGroupAlignment(.center)", ".pinToVisibleBounds(false)"] {
            #expect(config.code.contains(fragment))
        }
    }

    @Test func groupSpacingDefaultsToLineSpacingAndCanRestoreFollowing() {
        var config = LayoutLabConfiguration()
        let initial = config.recipe(section: 0).makeGrid()
        #expect(initial.trackSpacing == 10 && initial.lineSpacing == 10)
        #expect(initial.groupSpacing == nil)
        #expect(GridLayout(tracks: 1).trackSpacing == 0 && GridLayout(tracks: 1).lineSpacing == 0)
        #expect(GridLayout(tracks: 1).groupSpacing == nil)
        config.lineSpacing = 12
        #expect(config.recipe(section: 0).makeGrid().groupSpacing == nil)
        #expect(config.code.contains(".lineSpacing(12)"))
        #expect(!config.code.contains(".groupSpacing("))
        config.groupSpacing = 0
        config.lineSpacing = 18
        #expect(config.recipe(section: 0).makeGrid().groupSpacing == 0)
        #expect(config.code.contains(".groupSpacing(0)"))
        config.groupSpacing = nil
        let grid = config.recipe(section: 0).makeGrid()
        #expect(grid.groupSpacing == nil && grid.lineSpacing == 18)
        #expect(!config.code.contains(".groupSpacing("))
    }

    @Test func everySceneAndAxisProducesValidRecipe() {
        for scene in LayoutLabConfiguration.Scene.allCases {
            for horizontal in [false, true] {
                var config = LayoutLabConfiguration()
                config.scene = scene
                config.horizontal = horizontal
                for section in 0..<config.sectionCount {
                    #expect(config.recipe(section: section).makeGrid()
                        .environmentValidationErrors(in: TestLayoutEnvironment(), scrollDirection: config.outerAxis).isEmpty)
                }
                #expect(config.code.contains("scrollDirection: .\(horizontal ? "horizontal" : "vertical")"))
            }
        }
    }

    @Test func estimatedAndUniformModesMeasureContentAcrossTrackDefinitions() {
        for mode in LayoutLabConfiguration.TrackMode.allCases {
            for sizing in LayoutLabConfiguration.Sizing.available {
                var config = LayoutLabConfiguration()
                config.trackMode = mode
                config.sizing = sizing
                config.lines = 3
                #expect(config.recipe(section: 0).makeGrid().environmentValidationErrors(in: TestLayoutEnvironment()).isEmpty)
                #expect((config.item(index: 2, section: 0).sizingAxis != nil) == (sizing == .estimated || sizing == .uniform))
            }
        }
    }

    @Test func axisAndContentChangesArePartOfTheRowModel() {
        var config = LayoutLabConfiguration()
        config.scene = .tags
        let original = config.item(index: 0, section: 0)
        #expect(original.sizingAxis == .horizontal)
        config.expanded = true
        #expect(config.item(index: 0, section: 0) != original)
        #expect(config.item(index: 0, section: 0).text.count > original.text.count)
        config.horizontal = true
        #expect(config.item(index: 0, section: 0).sizingAxis == .vertical)
        config.scene = .cards
        #expect(config.item(index: 0, section: 0).sizingAxis == nil)
    }

    @Test func codeReflectsSectionOwnershipAndPaging() {
        var config = LayoutLabConfiguration()
        config.scene = .mixedSections
        #expect(config.sectionCount == 3)
        #expect(config.code.components(separatedBy: "ListSection(").count - 1 == 3)
        #expect(config.code.components(separatedBy: "BoundarySupplementaryLayout(kind: \"lab.title\"").count - 1 == 1)
        #expect(config.code.contains(".count(lines: 3, mainAxisSize: .fractionalViewport(1))"))
        config.scene = .nativeList
        #expect(config.code.contains("UIKitListLayout(appearance: .insetGrouped)"))
        #expect(!config.code.contains("BoundarySupplementaryLayout"))
        #expect(!config.code.contains("DecorationItemLayout"))
    }

    @Test func cellMeasuresExpandedTextAndResetsWhenReusedAcrossAxes() {
        var config = LayoutLabConfiguration()
        config.sizing = .estimated
        let cell = LayoutLabCell(frame: CGRect(x: 0, y: 0, width: 240, height: 44))
        let attributes = UICollectionViewLayoutAttributes(forCellWith: IndexPath(item: 0, section: 0))
        attributes.size = CGSize(width: 240, height: 44)
        cell.configure(config.item(index: 0, section: 0))
        let short = cell.preferredLayoutAttributesFitting(attributes).size
        config.expanded = true
        cell.configure(config.item(index: 0, section: 0))
        let long = cell.preferredLayoutAttributesFitting(attributes).size
        #expect(long.height > short.height)
        #expect(long.width == short.width)
        config.horizontal = true
        cell.configure(config.item(index: 0, section: 0))
        attributes.size = CGSize(width: 44, height: 80)
        let horizontal = cell.preferredLayoutAttributesFitting(attributes).size
        #expect(horizontal.width > 44)
        #expect(horizontal.height == 80)
        config.sizing = .fixed
        cell.configure(config.item(index: 0, section: 0))
        attributes.size = CGSize(width: 56, height: 80)
        #expect(cell.preferredLayoutAttributesFitting(attributes).size == attributes.size)
    }

    @Test func contentCountAndMaximumControlsKeepTheirScope() {
        var config = LayoutLabConfiguration()
        config.cycleCount(); #expect(config.count == 1)
        config.cycleCount(); #expect(config.count == 0)
        config.cycleCount(); #expect(config.count == 17)
        config.trackMode = .mixed
        config.limitMaximum = true
        let tracks = config.recipe(section: 0).tracks!
        #expect(tracks[0].size == .fixed(60))
        #expect(tracks[1].size == .flexible(minimum: 50, maximum: 100))
        #expect(tracks[2].size == .adaptive(minimumForCount: 50, maximum: 112))
    }
}
