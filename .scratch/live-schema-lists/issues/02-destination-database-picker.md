# 02: Destination Database picker from a live list

**What to build:** The destination Connection loads its Databases the same way as the source. On first open (and when both ends need a fresh load), source then destination, not in parallel. Replace and Backup and replace use the picker. Create new and Backup name stay typed. Start dump stays off until a destination Database is chosen when Strategy needs an existing Database. Recipe destination names missing on that Connection stay selectable and marked absent. Refresh/Retry sit on this picker. Parent spec: `.scratch/live-schema-lists/spec.md`.

**Blocked by:** 01 Source Database picker from a live list

**Status:** resolved

- [x] Destination Database for Replace / Backup and replace is a live picker on the destination Connection
- [x] Create new Database name and Backup name remain typed
- [x] First-open (and dual load) runs source listing then destination listing
- [x] Missing Recipe destination Database name stays selectable and marked absent
- [x] Start dump disabled when Strategy needs an existing destination Database and none is chosen
- [x] Refresh/Retry/error/spinner match the source picker behaviour

## Comments

## Answer

Replace / Backup and replace pick the destination Database from a live list on the destination Connection. Create new and Backup name stay typed. First-open (and other dual loads) list source then destination, never in parallel. A Recipe destination name missing on that Connection stays selectable and marked absent. Start dump stays off until that existing Database is chosen. Refresh/Retry, spinner, and copyable error match the source picker.
