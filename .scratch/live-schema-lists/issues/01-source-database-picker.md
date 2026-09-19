# 01: Source Database picker from a live list

**What to build:** Selecting a Connection loads that Connection’s Databases with `SHOW DATABASES` (same `mysql` path, secrets, and SSH tunnel as a Pull: open, query, close). The Source card is a picker, not a typed field. System Databases stay hidden unless the existing toggle is on. The picker stays empty until the developer chooses a name or a Recipe fills one; a Recipe name missing on the server stays selectable and marked absent. Loading shows a spinner; failure is copyable with Retry/Refresh. Lists are cached for this app session per Connection unless Refresh. Listing is not a Pull: no History row. Listing does not start while a Pull is running. A Pull of All tables from a picked Database still runs as today. Parent spec: `.scratch/live-schema-lists/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Source Database is chosen from a live list on the selected Connection, not typed
- [x] Tunnel opens, query runs, tunnel closes; Settings `mysql` and Keychain apply
- [x] System Databases hidden unless shown; picker empty until pick or Recipe
- [x] Missing Recipe Database name remains selectable and marked absent
- [x] Spinner, copyable error, Retry/Refresh; session cache; no invented names
- [x] Failed or busy listing does not write History; listing refused while a Pull runs
- [x] Pull seam tests cover list Databases (success, failure, tunnel close, blocked by running Pull, no History)

## Comments

## Answer

`PullEngine.listDatabases(on:)` lists Databases with the same `mysql` client, Keychain password, and SSH open/query/close as a Pull. It does not write History. It is refused while a Pull is running. The Source card is a picker: empty until pick or Recipe, system Databases hidden unless shown, missing Recipe names stay selectable and marked absent, session cache plus Refresh/Retry, spinner and copyable error. Destination and Selected tables stay as they were.
