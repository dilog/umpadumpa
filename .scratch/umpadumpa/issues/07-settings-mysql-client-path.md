# 07: Settings mysql client path

**What to build:** If `mysqldump` and `mysql` are not on PATH, the developer can set absolute paths in Settings. A Pull uses those clients. If they are missing, Start dump fails with a clear error before touching the destination.

**Blocked by:** 01 One-off Pull, import in place

**Status:** resolved

- [x] Settings can store absolute paths for `mysqldump` and `mysql`
- [x] A Pull uses PATH when Settings paths are empty, otherwise the configured paths
- [x] Missing clients produce a clear error; destination is untouched; History records failed
- [x] Pull seam tests stub the runner and cover PATH vs configured path vs missing binary

## Answer

Settings persist `mysqldumpPath` / `mysqlPath` (empty = PATH). Pull checks both binaries before dump or destination work, puts the resolved executable on `ExternalCommand`, and records a failed History row on `missingClient`.
