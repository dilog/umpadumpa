# 03: Reorder Connections

**What to build:** The developer can drag Connections in the sidebar. That order is saved and comes back after quit. A new Connection is appended. History and Settings stay pinned and are not in the drag list. Parent spec: `.scratch/sidebar-pull-feedback/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Connection order persists across launch
- [x] New Connection is appended
- [x] History and Settings are not reorderable
- [x] Store tests cover saved order; drag in the window is verified by using the app

## Comments

Implemented at the persisted workspace seam: `saveConnections` writes the Connection array as given; `saveConnection` still appends a new id. Sidebar Connections sit in a `List` with `onMove`; History and Settings stay pinned below that list.

## Answer

Connection order is the saved JSON array. Dragging the sidebar list writes that array. A new Connection is appended. History and Settings are not in the drag list.
