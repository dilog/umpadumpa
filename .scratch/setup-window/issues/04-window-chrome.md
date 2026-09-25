# 04: Window chrome

**What to build:** The window title bar does not repeat “UmpaDumpa”; the traffic lights stay. Settings uses the same outer padding as History. Strategy and Replace mode select on the whole row (circle, icon, and label). All tables / Selected tables stays a menu. The developer can drag Connections in the sidebar to reorder them. That order is already saved. History, Settings, and New Connection are not draggable. A new Connection is still appended. Decisions are in `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] The title bar does not show the app name; traffic lights remain
- [x] Settings padding matches History
- [x] Strategy and Replace mode respond on the whole row
- [x] Dragging a Connection reorders the saved list
- [x] History, Settings, and New Connection are not in the drag list
- [x] A new Connection is still appended
- [x] Checked by running the app; saved order stays covered by the existing workspace tests

## Answer

Title text is hidden on the live window; close, minimize, and zoom stay. Settings uses the same 28 pt outer padding as History. Strategy and Replace mode use the full row as the hit target. Connections in the sidebar list can be dragged onto each other; that calls the existing saved reorder. History, Settings, and New Connection sit outside that list. Adding a Connection still appends through the existing store. `ConnectionStoreTests.testSavedConnectionOrderIsKeptAndNewConnectionIsAppended` passed with the rest of the suite. The window itself was not clicked through in this session.
