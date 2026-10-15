import Foundation
#if canImport(CoreGraphics)
import CoreGraphics // CGRect Hashable etc.; Linux Foundation provides these itself
#endif
/// Hold-open tokens (DD-929; architecture §6.5). While any is held the dock never hides on its own.
public enum HoldOpenToken: String, Codable, Sendable, Hashable, CaseIterable {
    case dragging, menuOpen, editing, pinnedByUser
    /// Reserved for Pillar A previews and later popovers / widget text fields.
    case previewOpen, popoverOpen, textFocus
}

/// Cross-feature contract, implemented by the Edge Dock manager. Used by the status menu now
/// and by previews, scripting and shortcuts later (architecture §6.6).
@MainActor public protocol EdgeDockControlling: AnyObject {
    /// `nil` = the docks on the pointer's display.
    func reveal(dock: DockID?)
    func hide(dock: DockID?, animated: Bool)
    func setHold(_ token: HoldOpenToken, _ on: Bool, dock: DockID?)
}
