import CoreGraphics
import FlipbookCapture
import Testing

struct ContentSnapshotTests {
    static let own = "com.fayzanmalik.flipbook"
    static let notificationCenter = "com.apple.notificationcenterui"
    static let controlCenter = "com.apple.controlcenter"

    let main = DisplayInfo(id: 1, uuid: "MAIN", name: "Built-in Retina Display",
                           frame: CGRect(x: 0, y: 0, width: 1512, height: 982), pixelSize: CGSize(width: 3024, height: 1964))
    let left = DisplayInfo(id: 2, uuid: "LEFT", name: "E29w-20",
                           frame: CGRect(x: -2560, y: 0, width: 2560, height: 1080), pixelSize: CGSize(width: 2560, height: 1080))
    let statusItemFrame = CGRect(x: 1300, y: 0, width: 32, height: 24)

    func window(_ id: CGWindowID, owner: String?, frame: CGRect = CGRect(x: 100, y: 100, width: 400, height: 300),
                layer: Int = 0) -> WindowInfo {
        WindowInfo(id: id, frame: frame, title: "Window \(id)", layer: layer, isOnScreen: true,
                   ownerBundleID: owner, ownerName: owner ?? "")
    }

    func snapshot(windows: [WindowInfo] = [], apps: [String] = [own, notificationCenter]) -> ContentSnapshot {
        ContentSnapshot(displays: [main, left], windows: windows, appBundleIDs: apps)
    }

    @Test func cursorScreenPicksContainingDisplay() throws {
        let onLeft = try #require(TargetResolver.resolve(.cursorScreen, cursor: CGPoint(x: -100, y: 500), in: snapshot()))
        #expect(onLeft.target == .display(left))
        #expect(onLeft.note == nil)
        let nowhere = try #require(TargetResolver.resolve(.cursorScreen, cursor: CGPoint(x: 5000, y: 5000), in: snapshot()))
        #expect(nowhere.target == .display(main))
    }

    @Test func missingScreenFallsBack() throws {
        let resolved = try #require(TargetResolver.resolve(.screen(uuid: "gone"), cursor: CGPoint(x: -100, y: 500),
                                                           in: snapshot()))
        #expect(resolved.target == .display(left))
        #expect(resolved.note == TargetResolver.screenMissingNote)
        let present = try #require(TargetResolver.resolve(.screen(uuid: "MAIN"), cursor: CGPoint(x: -100, y: 500),
                                                          in: snapshot()))
        #expect(present.target == .display(main))
        #expect(present.note == nil)
    }

    @Test func windowResolvesById() throws {
        let doc = window(42, owner: "com.apple.TextEdit")
        let present = try #require(TargetResolver.resolve(.window(id: 42), cursor: CGPoint(x: 10, y: 10),
                                                          in: snapshot(windows: [doc])))
        #expect(present.target == .window(doc))
        #expect(present.note == nil)
        let missing = try #require(TargetResolver.resolve(.window(id: 43), cursor: CGPoint(x: 10, y: 10),
                                                          in: snapshot(windows: [doc])))
        #expect(missing.target == .display(main))
        #expect(missing.note == TargetResolver.windowMissingNote)
    }

    @Test func noDisplaysIsNil() {
        let empty = ContentSnapshot(displays: [], windows: [], appBundleIDs: [])
        #expect(TargetResolver.resolve(.cursorScreen, cursor: .zero, in: empty) == nil)
    }

    @Test func filterExcludesSelfAndNotificationCenter() {
        let plan = FilterPlan.make(ownBundleID: Self.own,
                                   snapshot: snapshot(windows: [window(77, owner: Self.own, frame: statusItemFrame, layer: 25)]),
                                   statusItemWindowNumber: 77, statusItemFrame: statusItemFrame)
        #expect(plan.excludedBundleIDs == [Self.own, Self.notificationCenter])
        #expect(plan.exceptingWindowIDs == [])
        #expect(plan.statusItem == .ownedByUs)
    }

    @Test func statusItemOwnedElsewhereIsExcluded() {
        let windows = [
            window(77, owner: Self.controlCenter, frame: statusItemFrame, layer: 25),
            window(78, owner: Self.controlCenter),
            window(79, owner: Self.controlCenter),
            window(90, owner: "com.apple.TextEdit"),
        ]
        let plan = FilterPlan.make(ownBundleID: Self.own,
                                   snapshot: snapshot(windows: windows, apps: [Self.own, Self.notificationCenter, Self.controlCenter]),
                                   statusItemWindowNumber: 77, statusItemFrame: statusItemFrame)
        #expect(plan.excludedBundleIDs == [Self.own, Self.notificationCenter, Self.controlCenter])
        #expect(plan.exceptingWindowIDs == [78, 79])
        #expect(plan.statusItem == .ownedBy(bundleID: Self.controlCenter))
    }

    @Test func statusItemFoundByFrame() {
        let windows = [
            window(80, owner: Self.controlCenter, frame: statusItemFrame.offsetBy(dx: 0.5, dy: -0.5), layer: 25),
            window(78, owner: Self.controlCenter),
            window(79, owner: Self.controlCenter),
        ]
        let plan = FilterPlan.make(ownBundleID: Self.own,
                                   snapshot: snapshot(windows: windows, apps: [Self.own, Self.notificationCenter, Self.controlCenter]),
                                   statusItemWindowNumber: 77, statusItemFrame: statusItemFrame)
        #expect(plan.excludedBundleIDs == [Self.own, Self.notificationCenter, Self.controlCenter])
        #expect(plan.exceptingWindowIDs == [78, 79])
        #expect(plan.statusItem == .ownedBy(bundleID: Self.controlCenter))
    }

    @Test func statusItemNotFound() {
        let windows = [
            window(78, owner: Self.controlCenter, frame: statusItemFrame.offsetBy(dx: 40, dy: 0), layer: 25),
            window(79, owner: Self.controlCenter, frame: statusItemFrame, layer: 0),
        ]
        let plan = FilterPlan.make(ownBundleID: Self.own,
                                   snapshot: snapshot(windows: windows, apps: [Self.own, Self.notificationCenter, Self.controlCenter]),
                                   statusItemWindowNumber: 77, statusItemFrame: statusItemFrame)
        #expect(plan.excludedBundleIDs == [Self.own, Self.notificationCenter])
        #expect(plan.exceptingWindowIDs == [])
        #expect(plan.statusItem == .notFound)
    }
}
