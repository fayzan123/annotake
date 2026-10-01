import AnnotakeCore
import AnnotakeInput
import Foundation
import Testing

/// An Accessibility element in a hand-built tree. It counts reads of `value`.
final class FakeNode: AXNode {
    let role: String
    let subrole: String
    let roleDescription: String
    let title: String
    let descriptionText: String
    let placeholder: String
    private let storedValue: String
    private(set) var valueReads = 0
    weak var parentNode: FakeNode?
    private(set) var childNodes: [FakeNode] = []
    var titleNode: FakeNode?

    init(_ role: String, subrole: String = "", roleDescription: String = "", title: String = "",
         description: String = "", placeholder: String = "", value: String = "") {
        self.role = role
        self.subrole = subrole
        self.roleDescription = roleDescription
        self.title = title
        descriptionText = description
        self.placeholder = placeholder
        storedValue = value
    }

    var value: String {
        valueReads += 1
        return storedValue
    }

    var titleElement: AXNode? { titleNode }
    var parent: AXNode? { parentNode }
    var children: [AXNode] { childNodes }

    /// Adds the child and returns it.
    @discardableResult
    func add(_ child: FakeNode) -> FakeNode {
        child.parentNode = self
        childNodes.append(child)
        return child
    }
}

struct LabelResolverTests {
    @Test func titledButton() {
        let button = FakeNode("AXButton", roleDescription: "button", title: "Save")
        #expect(LabelResolver.label(atHit: button) == ElementLabel(role: "button", label: "Save"))
    }

    @Test func describedButton() {
        let button = FakeNode("AXButton", roleDescription: "button", description: "Go back")
        #expect(LabelResolver.label(atHit: button) == ElementLabel(role: "button", label: "Go back"))
    }

    @Test func staticTextInLink() {
        let link = FakeNode("AXLink", roleDescription: "link", title: "Docs")
        let text = link.add(FakeNode("AXStaticText", roleDescription: "text", value: "Do"))
        #expect(LabelResolver.label(atHit: text) == ElementLabel(role: "link", label: "Docs"))
        #expect(text.valueReads == 0)
    }

    @Test func stopsAtWebArea() {
        let web = FakeNode("AXWebArea", roleDescription: "HTML content", title: "Page")
        let group = web.add(FakeNode("AXGroup", roleDescription: "group"))
        let text = group.add(FakeNode("AXStaticText", roleDescription: "text", value: "fragment"))
        #expect(LabelResolver.label(atHit: text) == nil)
    }

    @Test func stopsAtWindow() {
        let window = FakeNode("AXWindow", roleDescription: "standard window", title: "Who's using Chrome?")
        let group = window.add(FakeNode("AXGroup", roleDescription: "group"))
        #expect(LabelResolver.label(atHit: group) == nil)
    }

    /// Checkpoint 1: Chrome's tab strip is a group titled with the whole window title.
    @Test func groupTitledLikeItsWindowIsNoLabel() {
        let title = "Inbox (8) - Gmail - Google Chrome - Fayzan"
        let window = FakeNode("AXWindow", roleDescription: "standard window", title: title)
        let browser = window.add(FakeNode("AXGroup", roleDescription: "group"))
        let strip = browser.add(FakeNode("AXGroup", roleDescription: "group", title: title))
        #expect(LabelResolver.label(atHit: strip) == nil)
        let inside = strip.add(FakeNode("AXGroup", roleDescription: "group"))
        #expect(LabelResolver.label(atHit: inside) == nil)
    }

    @Test func controlNamedLikeItsWindowKeepsItsLabel() {
        let window = FakeNode("AXWindow", roleDescription: "standard window", title: "Downloads")
        let sidebar = window.add(FakeNode("AXOutline", roleDescription: "outline"))
        let row = sidebar.add(FakeNode("AXRow", roleDescription: "row", title: "Downloads"))
        #expect(LabelResolver.label(atHit: row) == ElementLabel(role: "row", label: "Downloads"))
    }

    @Test func finderCell() {
        let cell = FakeNode("AXCell", roleDescription: "cell")
        cell.add(FakeNode("AXTextField", roleDescription: "text field", value: "report.pdf"))
        #expect(LabelResolver.label(atHit: cell) == ElementLabel(role: "cell", label: "report.pdf"))
    }

    @Test func settingsSwitch() {
        let row = FakeNode("AXGroup", roleDescription: "group")
        row.add(FakeNode("AXStaticText", roleDescription: "text", value: "Wi-Fi"))
        let toggle = row.add(FakeNode("AXCheckBox", subrole: "AXSwitch", roleDescription: "switch"))
        #expect(LabelResolver.label(atHit: toggle) == ElementLabel(role: "switch", label: "Wi-Fi"))

        toggle.titleNode = FakeNode("AXStaticText", roleDescription: "text", title: "Bluetooth")
        #expect(LabelResolver.label(atHit: toggle) == ElementLabel(role: "switch", label: "Bluetooth"))
    }

    @Test func secureFieldValueNeverRead() {
        let field = FakeNode("AXTextField", subrole: "AXSecureTextField", roleDescription: "secure text field",
                             title: "Password", value: "hunter2")
        #expect(LabelResolver.label(atHit: field) == ElementLabel(role: "secure text field", label: "Password"))
        #expect(field.valueReads == 0)
    }

    @Test func labelsAreNormalized() {
        let button = FakeNode("AXButton", roleDescription: "button", title: "Save\n  changes\tnow")
        #expect(LabelResolver.label(atHit: button)?.label == "Save changes now")

        let long = LabelResolver.normalize(String(repeating: "a", count: 300))
        #expect(long.count == 120)
        #expect(long.hasSuffix("…"))
        #expect(LabelResolver.normalize("  short  ") == "short")
    }

    @Test func fieldLabels() {
        let email = FakeNode("AXTextField", roleDescription: "text field", placeholder: "Email", value: "me@example.com")
        #expect(LabelResolver.fieldLabel(focused: email) == ElementLabel(role: "text field", label: "Email"))
        #expect(email.valueReads == 0)

        let password = FakeNode("AXTextField", subrole: "AXSecureTextField", roleDescription: "secure text field",
                                title: "Password", value: "hunter2")
        #expect(LabelResolver.fieldLabel(focused: password)?.label == "Password")
        #expect(password.valueReads == 0)

        #expect(LabelResolver.fieldLabel(focused: FakeNode("AXTextArea", roleDescription: "text entry area")) == nil)
    }
}
