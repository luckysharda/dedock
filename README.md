# dedock

A native macOS app (Swift 6 + SwiftUI hosted in AppKit, macOS 14+) that combines:

- **Edge Dock** — a second, customizable dock of apps, folders and live widget tiles that slides out from the left/right (optionally bottom/top) screen edge (CoolDock-class features).
- **Window previews** — hover any app in the native Dock or the Edge Dock to see its windows, plus a window switcher, ⌘Tab previews and window actions (DockDoor-class features).

dedock is clean-room: it reproduces features, not code or visual design. See `docs/`.

## Branches

- `main` — released
- `staging` — release candidates
- `develop` — integration; every feature is built in its own worktree under `.worktrees/` on a `feature/*` branch off `develop`.
