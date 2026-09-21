# 04: History date desc and sortable columns

**What to build:** History table defaults to When descending (newest first). Column headers are sortable (When, Source, Destination, Result). Cap 100, clear-all, and no per-row delete stay as today. Parent spec: `.scratch/trial-ux-fixes/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Default order: When descending
- [x] Columns sortable via headers
- [x] Cap / clear-all / no row delete / not re-runnable unchanged

## Answer

History table uses SwiftUI `sortOrder` initialized to When descending (`HistoryDisplay.defaultSortOrder`). When, Source, Destination, and Result headers are sortable (`resultLabel` for Result). Store cap, clear-all, and log-only rows are unchanged.

## Comments
