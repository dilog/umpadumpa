# 02: Workspace file export and import

**What to build:** From Settings the developer can export and import a Workspace file: Connections, Recipes, and the client paths. Passwords, SSH passphrases, and History are not in the file. SSH key paths travel with the Connection. Connection ids are kept, so Keychain secrets on this Mac still match. On another Mac the developer enters passwords again with Edit. Import replaces the whole set after confirm. It does not merge. A Connection missing from the file is deleted with its Keychain secrets and with Recipes whose source is that Connection. Client paths in the file overwrite the current ones, including when empty. An unreadable file changes nothing. Import is unavailable while a Pull is running. Export stays available. A failed Import stays on Settings until the developer closes it or starts another Import. A successful Import shows a brief “Workspace imported.” This is not a Backup, and it does not restore one. Respect ADR 0007. Decisions are in `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Export writes Connections, Recipes, and client paths, and omits passwords, passphrases, and History
- [x] Import replaces that set after confirm and keeps Connection ids
- [x] A Connection absent from the file is deleted with its Keychain secrets and its source Recipes
- [x] History is unchanged by Import
- [x] An unreadable file leaves Connections, Recipes, client paths, and secrets unchanged
- [x] Import is refused while a Pull is running; Export is not
- [x] Failed Import stays on Settings until dismissed or another Import; success is a brief “Workspace imported.”
- [x] Workspace tests cover the file round-trip, replace, secrets, History, and a bad file

## Answer

Settings can export and import a JSON Workspace file. The file holds Connections (including SSH key paths), Recipes, and the two client paths. Passwords, passphrases, and History stay out. Import asks for confirm, then replaces that set and keeps Connection ids so Keychain secrets on this Mac still match. A Connection missing from the file loses its Keychain secrets and Recipes that use it as source. Empty paths in the file overwrite the saved ones. The first-open sheet flag is left alone. A bad file or a running Pull changes nothing. A failed Import stays on Settings until Close or another Import. Success shows “Workspace imported.” for a few seconds. `WorkspaceTests` covers the file behavior. The Settings buttons are checked by running the app.
