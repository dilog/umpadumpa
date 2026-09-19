# 03: Live Selected tables

**What to build:** Selected tables loads names from the source Database with `SHOW TABLES` (base tables and views). No session cache: entering Selected tables, Refresh on the checklist, and changing source Database in that mode each list again. Changing source Database keeps Selected tables, clears checks, and reloads (union with Recipe names if a Recipe is applied). Recipe table names missing on the server stay checked and marked absent. Check all / Uncheck all; at least one check or the Pull does not start. Empty `tables` is still All tables. A subset Pull stays import in place. Listing failures are copyable on the checklist; listing is not a Pull and does not run during a Pull. Dump progress for an entire Database still does its own `SHOW TABLES` at Pull time. Parent spec: `.scratch/live-schema-lists/spec.md`.

**Blocked by:** 01 Source Database picker from a live list

**Status:** resolved

- [x] Selected tables checklist is live names (tables and views), not prototype strings
- [x] Each enter / Refresh / source Database change in this mode hits the server again
- [x] Source Database change stays on Selected tables, clears checks, and reloads (Recipe union if applicable)
- [x] Missing Recipe table names stay checked and marked absent
- [x] Check all / Uncheck all; empty selection refuses to start; empty `tables` remains entire Database
- [x] Subset Pull remains import in place; entire-Database dump progress still lists tables at Pull time
- [x] Pull seam tests cover list Tables (including stubbed views), tunnel close, no History, refused while Pull runs

## Comments

## Answer

`PullEngine.listTables(on:database:)` lists tables and views with `SHOW TABLES`, the same `mysql` client, Keychain, and SSH open/query/close as listing Databases. It does not write History and is refused while a Pull is running. Selected tables has no session cache: entering the mode, Refresh/Retry, and changing source Database each list again. Changing source Database stays on Selected tables, clears checks, then unions Recipe table names if a Recipe is applied; missing names stay checked and marked absent. Entire-Database dump progress still runs its own `SHOW TABLES` at Pull time.
