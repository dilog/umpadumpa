# 01: One-off Pull, import in place

**What to build:** A developer can add Connections, pick one in the sidebar as the locked source, choose a destination Connection and Database, confirm, and run a one-off Pull of the entire source Database with Replace mode import-in-place. umpadumpa dumps to a temp file first, then imports into the existing destination without DROP DATABASE. Extra tables on the destination stay. Passwords go in the Keychain. History records when, source, destination, and outcome. Only one Pull at a time. Start dump is the real action; Cancel on confirm does nothing. Parent spec: `.scratch/umpadumpa/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] New Connection can be saved (name, host, port, user) with password in Keychain, not on disk
- [x] Sidebar lists Connections; the selected one is the source and is locked on the Source card
- [x] Start dump opens Confirm dump (source, destination, Strategy replace, Replace mode import-in-place, all tables); Cancel leaves destination untouched
- [x] After confirm, source `mysqldump` finishes before any destination `mysql` command
- [x] Import-in-place issues no DROP DATABASE; dumped tables are overwritten; other destination tables remain
- [x] Dump failure never touches the destination; History records failed
- [x] A second Pull is refused while one is running; Start dump is disabled
- [x] Successful and failed Pulls appear in the History table; a History row cannot be re-run
- [x] Tests drive Pull at the domain seam with a stubbed process runner, Keychain, and clock — not SwiftUI

## Answer

`PullEngine` is the domain seam: `confirm` then `run`, with stubbed process runner, Keychain, and clock. A one-off entire-Database Pull writes `mysqldump` (`--add-drop-table`) to a temp file, then `mysql` import-in-place (no DROP DATABASE). Passwords stay in Keychain; Connections/History persist without secrets. UI: New Connection, locked source, Confirm dump, one Pull at a time, History log.

Not in this ticket: live SHOW DATABASES, drop-database, backup/create-new, table subset, SSH, Recipe persistence.
