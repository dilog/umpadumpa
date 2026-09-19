# 02: Delete Connection

**What to build:** A trash control on the Connection’s sidebar row asks for confirmation in English (destructive Delete). Confirming removes the Connection, its Keychain secrets, and Recipes whose source is that Connection. History rows are unchanged. Recipes on other Connections that used it only as destination remain. Parent spec: `.scratch/sidebar-pull-feedback/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Sidebar trash on a Connection row; confirm before delete
- [x] Connection and its Keychain secrets are gone
- [x] Recipes whose source was that Connection are gone
- [x] History is unchanged
- [x] Recipes that only used it as destination remain
- [x] Store tests cover the cascade; not SwiftUI identity

## Answer

Sidebar rows have a trash control and an English confirmation (Delete / Cancel). Confirming calls `DiskStore.deleteConnection`, which removes the Connection, Keychain/memory secrets, and Recipes whose source is that Connection. History is not rewritten. Recipes on other Connections that only used it as destination stay.

## Comments
