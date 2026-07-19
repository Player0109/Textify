import ApplicationServices
import AppKit
import Carbon.HIToolbox

public struct SystemInsertionTargetChecker: InsertionTargetChecking {
    public init() {}

    public func currentTargetIdentity() async -> InsertionTargetIdentity? {
        await MainActor.run {
            guard let application = NSWorkspace.shared.frontmostApplication else {
                return nil
            }
            return InsertionTargetIdentity(
                processIdentifier: application.processIdentifier,
                bundleIdentifier: application.bundleIdentifier
            )
        }
    }

    public func currentTargetStatus() async -> InsertionTargetStatus {
        guard !IsSecureEventInputEnabled() else {
            return .blocked(.secureInputEnabled)
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard result == .success, let focused else {
            return .allowed
        }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return .allowed
        }

        let focusedElement = focused as! AXUIElement
        if isSecureTextField(focusedElement) {
            return .blocked(.secureFieldFocused)
        }

        return .allowed
    }

    private func isSecureTextField(_ element: AXUIElement) -> Bool {
        let role = stringAttribute(kAXRoleAttribute as CFString, from: element)
        let subrole = stringAttribute(kAXSubroleAttribute as CFString, from: element)
        return role == kAXTextFieldRole as String && subrole == kAXSecureTextFieldSubrole as String
    }

    private func stringAttribute(_ attribute: CFString, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success else {
            return nil
        }
        return value as? String
    }
}
