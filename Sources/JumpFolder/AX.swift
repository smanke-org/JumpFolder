import AppKit
import ApplicationServices

/// Small Accessibility helpers. Every call is a round trip to another process, so callers
/// keep element references instead of searching again.
enum AX {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func app(_ pid: pid_t) -> AXUIElement {
        let element = AXUIElementCreateApplication(pid)
        // A hung app must not hang JumpFolder.
        AXUIElementSetMessagingTimeout(element, 0.5)
        return element
    }

    static func value(_ element: AXUIElement, _ attribute: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = value(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    static func role(_ element: AXUIElement) -> String? { string(element, kAXRoleAttribute) }
    static func identifier(_ element: AXUIElement) -> String? { string(element, kAXIdentifierAttribute) }

    /// The element's frame in global top-left coordinates.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let value = value(element, "AXFrame"), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(value as! AXValue, .cgRect, &rect) ? rect : nil
    }

    static func pid(_ element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    @discardableResult
    static func set(_ element: AXUIElement, _ attribute: String, _ value: CFTypeRef) -> Bool {
        AXUIElementSetAttributeValue(element, attribute as CFString, value) == .success
    }

    @discardableResult
    static func perform(_ element: AXUIElement, _ action: String) -> Bool {
        AXUIElementPerformAction(element, action as CFString) == .success
    }

    /// Breadth-first search below `root`, looking at no more than `budget` elements and
    /// `maxDepth` levels, so a huge file list can't stall the app.
    static func first(below root: AXUIElement, maxDepth: Int = 20, budget: Int = 600,
                      where match: (AXUIElement) -> Bool) -> AXUIElement? {
        var queue: [(AXUIElement, Int)] = [(root, 0)]
        var seen = 0
        while !queue.isEmpty, seen < budget {
            let (element, depth) = queue.removeFirst()
            seen += 1
            if match(element) { return element }
            if depth < maxDepth { queue += children(element).map { ($0, depth + 1) } }
        }
        return nil
    }

    /// The element with this AXIdentifier below `root`.
    static func first(below root: AXUIElement, identifier: String, budget: Int = 600) -> AXUIElement? {
        first(below: root, budget: budget) { Self.identifier($0) == identifier }
    }

    /// One line per element, indented, for the debug hook.
    static func dump(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 4, into lines: inout [String]) {
        guard lines.count < 400 else { return }
        var parts = [role(element) ?? "?"]
        if let sub = string(element, kAXSubroleAttribute) { parts.append("[\(sub)]") }
        if let id = identifier(element), !id.isEmpty { parts.append("id=\(id)") }
        if let title = string(element, kAXTitleAttribute), !title.isEmpty { parts.append("title=\(title)") }
        if let value = value(element, kAXValueAttribute) { parts.append("value=\(String(describing: value).prefix(60))") }
        if let url = value(element, kAXURLAttribute) { parts.append("url=\(url)") }
        if let frame = frame(element) { parts.append("frame=\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))x\(Int(frame.height))") }
        parts.append("pid=\(pid(element))")
        lines.append(String(repeating: "  ", count: depth) + parts.joined(separator: " "))
        guard depth < maxDepth else { return }
        for child in children(element) { dump(child, depth: depth + 1, maxDepth: maxDepth, into: &lines) }
    }
}
