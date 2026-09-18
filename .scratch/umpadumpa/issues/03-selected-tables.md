# 03: Selected tables

**What to build:** A one-off Pull can copy All tables or Selected tables, as in the mockup. Selected tables lists tables from the source Database in a short scrolling checklist with Check all / Uncheck all. A subset Pull is always import-in-place: it overwrites only those tables and must not DROP DATABASE. Confirm lists the table names (or “all tables”). Empty selection should not start a destructive no-op without saying so — refuse or require at least one table.

**Blocked by:** 01 One-off Pull, import in place

**Status:** resolved

- [x] Source card: All tables vs Selected tables; choose mode is a max-height ~160 scrolling checklist plus Check all / Uncheck all
- [x] Replace mode drop-database is unavailable (hidden or disabled) while Selected tables is on
- [x] Confirm dump names the chosen tables or “All tables”
- [x] Non-empty `tables` is forwarded to `mysqldump`; destination Database is not dropped; other tables remain
- [x] Empty `tables` still means entire Database (All tables)
- [x] Pull seam tests cover subset vs all with a stubbed runner

## Comments

Implemented at the Pull seam: non-empty `tables` is appended to `mysqldump`, subset confirm/run forces import-in-place, empty `tables` still dumps the whole Database. Selected tables with none checked refuses to start. Table names in the checklist still come from the prototype list for the chosen source Database name, not a live `SHOW TABLES`.

## Answer

Subset Pulls copy named tables in place. Empty `tables` remains All tables. Drop-database radios are hidden while Selected tables is on.
