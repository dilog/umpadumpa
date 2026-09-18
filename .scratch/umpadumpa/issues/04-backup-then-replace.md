# 04: Backup then replace

**What to build:** Strategy backup-then-replace copies the whole destination Database into a Backup first, then applies the chosen Replace mode (drop-database or import-in-place). Default Backup name is `{database}_backup_YYYYMMDD_HHMM`, editable on the Destination card and on confirm. If that Backup name already exists, the Pull does not start and the destination is untouched. There is no Restore. A Backup is a normal Database on the destination Connection.

**Blocked by:** 01 One-off Pull, import in place; 02 Replace mode drop-database

**Status:** ready-for-human

- [x] Choosing Backup and replace shows the Backup name field (default `{database}_backup_YYYYMMDD_HHMM`) and keeps Replace mode
- [x] Confirm dump shows Strategy, Replace mode, and Backup name; the name is still editable there
- [x] Source dump finishes before Backup or destination changes
- [x] Backup of the whole destination Database exists before Replace mode runs
- [x] After Backup, drop-database vs import-in-place behaves as in ticket 02
- [x] Existing Backup name aborts the Pull with no destination change
- [x] Failed import after Backup leaves the Backup in place and does not treat the destination as successful
- [x] Pull seam tests cover Backup-then-both-modes and name collision
