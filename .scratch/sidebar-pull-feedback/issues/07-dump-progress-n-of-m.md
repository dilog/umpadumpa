# 07: Dump progress N of M

**What to build:** While a Pull runs, status sits by the footer in English: spinner plus phase. Dumping source and dumping a Backup also show “N of M tables” (tables reached, not bytes or ETA) and dump file size in MB when cheap. For an entire Database, M comes from `SHOW TABLES` (system Databases hidden as in the glossary). For a subset, M is the Pull’s table list. Importing destination is spinner plus phase only. Success and “Recipe saved.” are brief, not a sticky green banner. Failures stay visible and copyable. Selected-tables checkboxes stay prototype names. Parent spec: `.scratch/sidebar-pull-feedback/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Entire-Database dump uses `SHOW TABLES` for M and reports N of M during dump
- [x] Subset dump uses the Pull’s tables as M and does not need `SHOW TABLES` for M
- [x] Backup dump reports table progress the same way
- [x] Import does not report table N of M
- [x] No percent bar and no time remaining
- [x] Pull seam tests drive progress from stubbed processes; footer copy is English in the window

## Answer

Dumping source and dumping a Backup report English “N of M tables” at the Pull seam (`onProgress`), plus dump file size in MB when the file is at least 1 MB. Entire-Database M comes from `SHOW TABLES` after the source (or destination, for Backup) tunnel is up; a subset Pull uses the Pull’s table list and does not run `SHOW TABLES`. Import is spinner plus phase only. `mysqldump --verbose` stderr drives N. Success copy clears after a few seconds; failures stay copyable.
