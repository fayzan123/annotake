@testable import AnnotakeApp
import Foundation
import Testing

struct MoveToApplicationsTests {
    let home = URL(fileURLWithPath: "/Users/someone")

    @Test func staysInApplications() {
        for bundle in [URL(fileURLWithPath: "/Applications/Annotake.app"), home.appending(path: "Applications/Annotake.app")] {
            #expect(MoveToApplications.decision(bundleURL: bundle, home: home, systemApplicationsWritable: true) == .stay)
            #expect(MoveToApplications.decision(bundleURL: bundle, home: home, systemApplicationsWritable: false) == .stay)
        }
    }

    @Test func offersSystemApplicationsWhenWritable() {
        let decision = MoveToApplications.decision(bundleURL: home.appending(path: "Downloads/Annotake.app"), home: home,
                                                   systemApplicationsWritable: true)
        #expect(decision == .offer(destination: URL(fileURLWithPath: "/Applications/Annotake.app")))
    }

    @Test func offersUserApplicationsOtherwise() {
        let decision = MoveToApplications.decision(bundleURL: home.appending(path: "Downloads/Annotake.app"), home: home,
                                                   systemApplicationsWritable: false)
        #expect(decision == .offer(destination: home.appending(path: "Applications/Annotake.app")))
        let fromDiskImage = MoveToApplications.decision(
            bundleURL: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Annotake.app"), home: home,
            systemApplicationsWritable: false)
        #expect(fromDiskImage == .offer(destination: home.appending(path: "Applications/Annotake.app")))
    }

    @Test func detectsTranslocation() {
        #expect(MoveToApplications.isTranslocated(
            URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Annotake.app")))
        #expect(!MoveToApplications.isTranslocated(URL(fileURLWithPath: "/Volumes/Annotake/Annotake.app")))
        #expect(!MoveToApplications.isTranslocated(URL(fileURLWithPath: "/Applications/Annotake.app")))
    }
}
