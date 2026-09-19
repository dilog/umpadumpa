# 04: History cap and clear

**What to build:** History keeps the 100 most recent Pulls and drops older rows as new ones arrive. The developer can clear the whole log after an English confirmation (Clear History / Cancel). There is no per-row delete. A History row still cannot re-run a Pull. Parent spec: `.scratch/sidebar-pull-feedback/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] After more than 100 Pulls, only the newest 100 remain
- [x] Clear History with confirm empties the log
- [x] Cancel on confirm leaves History unchanged
- [x] No per-row delete
- [x] History tests at the store / Pull append path, not SwiftUI

## Answer

History append keeps the newest 100 rows (drops the oldest on the store, including through Pull). `HistoryStoring.clear()` empties memory and disk. The History screen has Clear History with an English confirmation (Clear History / Cancel); Cancel does not call clear. There is still no per-row delete and no way to re-run a Pull from a History row.

