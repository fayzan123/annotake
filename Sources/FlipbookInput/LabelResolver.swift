import FlipbookCore
import Foundation

/// An Accessibility element, as the label rules read it. Real elements read each attribute lazily.
public protocol AXNode {
    /// e.g. "AXButton"
    var role: String { get }
    var subrole: String { get }
    /// e.g. "button"
    var roleDescription: String { get }
    var title: String { get }
    var descriptionText: String { get }
    var placeholder: String { get }
    /// Read only where the rules say, and never on an AXSecureTextField.
    var value: String { get }
    var titleElement: AXNode? { get }
    var parent: AXNode? { get }
    var children: [AXNode] { get }
}

/// What a click or a typing run is labeled with (spec §4.4; M0's label rules). Typed text and a secure
/// field's value are never read.
public enum LabelResolver {
    public static let maxLength = 120
    /// How many parents the walk from the hit element may climb.
    static let maxDepth = 8
    /// How deep a cell or row is searched for its text.
    static let cellSearchDepth = 2
    static let secureSubrole = "AXSecureTextField"
    /// A label found at or above these is really the page's or window's title, so it counts as none.
    static let stopRoles: Set<String> = ["AXWebArea", "AXWindow", "AXApplication"]
    static let fieldRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    static let ellipsis = "…"

    /// Whitespace runs become one space, the ends are trimmed, and anything over 120 characters is cut
    /// to 119 plus "…", so a caption and a steps.md line stay readable.
    public static func normalize(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        let joined = words.joined(separator: " ")
        guard joined.count > maxLength else { return joined }
        return String(joined.prefix(maxLength - 1)) + ellipsis
    }

    /// The label for a click on `hit`, or nil: then the caption says `Clicked at (x, y)`.
    public static func label(atHit hit: AXNode) -> ElementLabel? {
        var node: AXNode? = hit
        var depth = 0
        while let current = node, depth <= maxDepth {
            if stopRoles.contains(current.role) { return nil }
            if let label = ownLabel(current) { return label }
            node = current.parent
            depth += 1
        }
        return nil
    }

    /// The label for typing into the focused element: title, description, placeholder, or its title
    /// element's title. Never its value.
    public static func fieldLabel(focused: AXNode) -> ElementLabel? {
        guard fieldRoles.contains(focused.role) || fieldRoles.contains(focused.subrole)
                || focused.subrole == secureSubrole else { return nil }
        let text = [focused.title, focused.descriptionText, focused.placeholder]
            .lazy.map(normalize).first { !$0.isEmpty }
            ?? focused.titleElement.map { normalize($0.title) }
        guard let text, !text.isEmpty else { return nil }
        return ElementLabel(role: focused.roleDescription.lowercased(), label: text)
    }

    /// The label this element has by itself, before looking at its parents.
    private static func ownLabel(_ node: AXNode) -> ElementLabel? {
        let role = node.roleDescription.lowercased()
        if let text = [node.title, node.descriptionText].lazy.map(normalize).first(where: { !$0.isEmpty }) {
            return ElementLabel(role: role, label: text)
        }
        switch node.role {
        case "AXCell", "AXRow":
            // Finder puts a file's name in a child of its cell.
            return firstText(below: node).map { ElementLabel(role: role, label: $0) }
        case "AXCheckBox":
            // System Settings switches have no text of their own; it sits beside them in the row.
            if let titled = node.titleElement,
               let text = [titled.title, readableValue(titled)].lazy.map(normalize).first(where: { !$0.isEmpty }) {
                return ElementLabel(role: role, label: text)
            }
            let siblings = node.parent?.children ?? []
            let text = siblings.lazy.filter { $0.role == "AXStaticText" }.map { normalize(readableValue($0)) }
                .first { !$0.isEmpty }
            return text.map { ElementLabel(role: role, label: $0) }
        default:
            return nil
        }
    }

    /// The first descendant, breadth-first and at most `cellSearchDepth` levels down, with a title or value.
    private static func firstText(below node: AXNode) -> String? {
        var level = node.children
        for _ in 0..<cellSearchDepth {
            for child in level {
                let text = [child.title, readableValue(child)].lazy.map(normalize).first { !$0.isEmpty }
                if let text { return text }
            }
            level = level.flatMap(\.children)
        }
        return nil
    }

    /// The value, except for a secure text field's, which is never read.
    private static func readableValue(_ node: AXNode) -> String {
        node.subrole == secureSubrole ? "" : node.value
    }
}
