# 03: Import progress and lasting Pull outcome

**What to build:** While the destination is importing, the footer shows a spinner and how many megabytes have been sent of the dump file size (“N MB of M MB”), not a table count. Dumping source and dumping a Backup stay “N of M tables”. The outcome stays on that Connection’s Pull screen until the developer closes it, changes Recipe, selects another Connection, or starts another Pull. Opening History or Settings does not clear it. Editing a form field without changing Recipe does not clear it. Failures stay copyable. “Recipe saved.” stays brief. This supersedes the earlier rule that import is spinner plus phase only and that success disappears after a few seconds. Decisions are in `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Import reports megabytes sent against the dump file size
- [x] Dump and Backup progress stay “N of M tables”
- [x] There is no table count, percent, or time remaining during import
- [x] The outcome remains until close, Recipe change, another Connection, or another Pull
- [x] History, Settings, and form edits alone do not clear it
- [x] Failures stay copyable; “Recipe saved.” stays brief
- [x] Pull seam tests cover import byte progress; the outcome rules are checked by running the app

## Answer

Import progress is bytes sent against the dump file, shown as “N MB of M MB” with a spinner. Dump and Backup stay “N of M tables”. Success and failure stay on that Connection until Close, a Recipe change, another Connection, or another Pull. History, Settings, and form edits leave the outcome in place. “Recipe saved.” still clears itself. `PullTests.testImportReportsBytesSentAgainstTheDumpFileSize` covers the byte progress. The outcome rules need a run of the app.
