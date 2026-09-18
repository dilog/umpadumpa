# 02: Replace mode drop-database

**What to build:** On an entire-Database Pull into an existing destination, the developer can choose Replace mode: Drop database then import, or Import in place. Drop removes the destination Database and recreates it from the dump so leftover local tables are gone. Import in place stays as in ticket 01. New forms default to import-in-place. Confirm names the Replace mode. The choice is remembered on a later Recipe ticket; this ticket is the one-off form and the Pull seam.

**Blocked by:** 01 One-off Pull, import in place

**Status:** resolved

- [x] Destination card shows two Replace mode radios when Tables is All tables: “Drop database, then import” and “Import in place”
- [x] Default on a new form is import-in-place
- [x] Confirm dump names the chosen Replace mode
- [x] `drop-database` issues DROP DATABASE, then CREATE, then import; extra local tables do not remain
- [x] `import-in-place` still issues no DROP DATABASE
- [x] Pull seam tests cover both modes with a stubbed runner

## Answer

Entire-Database replace now carries Replace mode. Confirm names it. `drop-database` runs `mysql -e DROP DATABASE`, then `CREATE DATABASE`, then import; leftover destination tables are gone. `import-in-place` is unchanged. New forms still default to import-in-place. Recipes do not persist this yet.
