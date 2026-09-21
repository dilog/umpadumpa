# 01: Edit and Delete Connection from context menu

**What to build:** Sidebar Connection rows get a context menu with Edit… and Delete…. Remove the trash icon. Edit opens a sheet with the same fields as New Connection; blank password/SSH secret fields leave Keychain unchanged. Delete from the menu and from the Edit sheet uses today’s confirm (Connection, secrets, source Recipes; History unchanged). Parent spec: `.scratch/trial-ux-fixes/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Context menu: Edit… and Delete… only
- [x] Trash icon removed from sidebar row
- [x] Edit sheet: all New Connection fields; blank secrets = keep Keychain
- [x] Delete from menu and Edit sheet; same confirm as today
- [x] Store/update tests for Connection + secret keep/replace; not SwiftUI identity

## Answer

Sidebar Connection rows use a context menu (Edit… / Delete…); the trash icon is gone. Edit reuses the New Connection sheet fields via `AppModel.beginEditConnection` / `updateConnectionFromForm`. `DiskStore.updateConnection` writes Connection fields and only calls Keychain set when a secret field is non-empty. Delete from the menu or Edit sheet uses the same confirmation copy as before.

## Comments
