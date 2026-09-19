# Sidebar, History, and Pull feedback

Status: ready-for-agent

## Problem Statement

The window still looks partly like a prototype: a fake green “online” dot, no way to delete or reorder Connections, Recipe chrome that does not match the mockup, a History log you cannot empty, a first-open window that sits on the footer, and Pull status as sticky green text. Dumping a large Database also feels slower than Sequel Ace’s Gzip checkbox, and a spinner alone does not show whether the dump is moving.

## Solution

Treat the selected Connection as real chrome (host, port, SSH — never a ping). Let the developer delete and reorder Connections in the sidebar. Remember which Recipe last ran a Pull from that Connection. Align Recipe Duplicate/Delete to the trailing edge. Keep History as a log of the last 100 Pulls and allow clearing it all. Raise the default window so the footer has air. Show Pull work next to the footer in English: spinner, table count while dumping, file size when cheap; import stays a phase plus spinner. Speed the dump with MySQL protocol compression, not a Gzip file and not remote `mysqldump | gzip`.

## User Stories

1. As a developer, I want the selected Connection’s header to show its MySQL host, port, and whether SSH is on, so that I can see how this Pull will reach the server.
2. As a developer, I want no status dot on that header, so that I am not told the server is “up” when nothing was pinged.
3. As a developer, I want that summary in English, so that chrome matches the rest of the window.
4. As a developer, I want a trash control on the Connection’s sidebar row, so that I can remove a server where I pick it.
5. As a developer, I want a confirmation before that delete, so that a mis-click does not drop a Connection.
6. As a developer, I want that confirmation in English with a destructive Delete button, so that it matches macOS alerts.
7. As a developer, I want deleting a Connection to remove its Keychain secrets, so that leftover passwords do not stay for a dead server.
8. As a developer, I want Recipes whose source is that Connection deleted with it, so that I am not offered shortcuts to a server that no longer exists.
9. As a developer, I want History rows left unchanged when I delete a Connection, so that the log still shows what ran.
10. As a developer, I want a Recipe on another Connection that used the deleted server only as destination to remain, so that source-owned Recipes are not silently wiped.
11. As a developer, I want to drag Connections in the sidebar to a new order, so that daily servers sit where I expect.
12. As a developer, I want that order to survive quitting the app, so that I do not re-sort every morning.
13. As a developer, I want a newly added Connection to appear at the end of the list, so that drag order is not shuffled.
14. As a developer, I want History and Settings to stay pinned in the sidebar, so that only Connections are reorderable.
15. As a developer, I want selecting a Connection to preselect the last Recipe that ran a Pull from that Connection, so that the daily job is ready without hunting the picker.
16. As a developer, I want that memory to include a failed Pull, so that a dump that died still brings back the Recipe I meant.
17. As a developer, I want a one-off Pull (None) to leave that memory alone, so that an experiment does not clear tomorrow’s default.
18. As a developer, I want the picker on None when I have never Pull’d with a Recipe from that Connection, so that a new server does not pretend there is a job.
19. As a developer, I want the picker on None if that last Recipe was deleted, so that I am not staring at a missing title.
20. As a developer, I want Duplicate and Delete for the selected Recipe aligned to the trailing side of the Recipe row, so that the layout matches the signed-off mockup.
21. As a developer, I want those two buttons only when a Recipe (not None) is selected, so that None does not offer Delete.
22. As a developer, I want History to show at most the 100 most recent Pulls, so that the table stays a log, not an archive.
23. As a developer, I want older rows dropped automatically when a new Pull would exceed 100, so that I never manage the cap by hand.
24. As a developer, I want a way to clear all History, so that I can wipe the log without deleting rows one by one.
25. As a developer, I want a confirmation before clearing History, so that emptying the log is deliberate.
26. As a developer, I want that confirmation in English (Clear History / Cancel), so that the action is obvious.
27. As a developer, I want no per-row delete on History, so that the table stays a log, not an editor.
28. As a developer, I want History still not to re-run a Pull, so that Recipes remain the way to repeat work.
29. As a developer, I want Pull status next to the footer buttons, so that I watch the job where I started it.
30. As a developer, I want a spinner plus phase while a Pull is running, so that I know the app is working.
31. As a developer, I want dumping source (and dumping a Backup) to show “N of M tables” in English, so that I can see table-level progress.
32. As a developer, I want M to be the real table list: the Pull’s tables when it is a subset, or `SHOW TABLES` when it is the entire Database, so that “10” is not a prototype count.
33. As a developer, I want N to mean tables the dump has reached, so that “7 of 10 tables” is honest even when tables differ in size.
34. As a developer, I want no percent bar and no time remaining, so that the UI does not guess bytes or minutes.
35. As a developer, I want dump file size in MB next to that count when it is cheap to show, so that a huge table still looks like it is moving.
36. As a developer, I want importing destination to stay spinner plus phase only, so that we do not fake table progress on `mysql`.
37. As a developer, I want a successful Pull and “Recipe saved.” to be brief, not a sticky green banner, so that status is not decoration.
38. As a developer, I want a failed Pull’s message to stay visible and copyable, so that I can paste it into a ticket.
39. As a developer, I want source dump and Backup dump to use MySQL protocol compression, so that less SQL crosses the wire.
40. As a developer, I want that compression always on, with fallback if the server cannot, so that I do not manage a Gzip checkbox.
41. As a developer, I do not want a Gzip file option, so that I am not promised Sequel Ace’s “zip on the server” when the dump still runs as local `mysqldump` through the tunnel.
42. As a developer, I want the window to open about 840 points tall, so that the first launch is not flush against the footer.
43. As a developer, I want to still shrink the window to about 720 points, so that a small laptop can compact the chrome.
44. As a developer, I want all of this copy in English, so that agents and screenshots stay on one language.
45. As a developer, I want selected-tables checkboxes to stay prototype names for now, so that live `SHOW TABLES` for progress does not silently become a schema browser.

## Implementation Decisions

- This spec supersedes V1 story 16 for delete: do not keep source Recipes and warn. Delete source Recipes with the Connection. Destination-only Recipes on other Connections stay; the developer picks a new destination later. History strings are not rewritten.
- Connection list order is persisted with the Connections (explicit order, not “sort by name”). Append on create. History and Settings are not in that list.
- Last Recipe for a Connection is stored as that Recipe’s id, updated only when a Pull runs with a Recipe selected (success or failure). Not updated on picker clicks or one-off Pulls. Missing id → None.
- Optional Recipe id rides on the Pull request so the Pull module can record last-used without the window guessing.
- Pull progress callbacks stay on the existing Pull module. Extend phases or progress payload so the window can show English “N of M tables” and dump file megabytes during dump/Backup only. Import does not emit table N of M.
- Entire-Database dump: after the source tunnel is up, `SHOW TABLES` on the source Database defines M (hide the same system Databases as the glossary). Subset: M is `tables` on the Pull. Drive N from `mysqldump` verbose (or equivalent) as tables start. Do not use prototype checkbox names as M.
- Protocol compression: pass the MySQL client compression-algorithms (zstd/zlib, uncompressed fallback) on dump invocations (source and Backup). Not Gzip of the temp file. Not remote dump-over-SSH. `--compress` is deprecated; prefer compression-algorithms.
- History store: after each append, keep the newest 100. Clear-all is an explicit store operation, confirmed in the window.
- Window: default size about 980×840; minimum height about 720. Bottom padding can stay; first-open height is the fix.
- UI copy: English. Header has no ping dot. Recipe Duplicate/Delete trailing. Sidebar trash + confirm. History Clear History + confirm. Footer status as above.
- SSH tunnels still close at end of Pull (already required); this spec does not reopen that bug.
- Live `SHOW DATABASES` and live table checkboxes remain out of this spec except `SHOW TABLES` for dump progress.
- Respect ADRs 0001–0014 and `CONTEXT.md` (including last Recipe, History cap, protocol compression, English UI).

## Testing Decisions

- A good test asserts observable behaviour at a seam: what was invoked, what was persisted, what progress was reported, what History contains. It does not assert SwiftUI identity, drag-and-drop hit testing, or exact point sizes of the window.

- **Seam: Pull** (existing). Stub process runner, secrets, clock, tunnels, settings, paths. Cover: dump/Backup commands include protocol compression; entire-Database dump issues `SHOW TABLES` and reports N of M from that list; subset dump uses Pull `tables` as M and does not need `SHOW TABLES` for M; import does not require table N of M; dump failure still closes tunnels (existing); last Recipe id on the request is available for the store to record (or Pull reports it on the History/outcome path — one place, not two).

- **Seam: persisted workspace** (Connections, Recipes, History, last Recipe ids). In-memory or temp-disk adapters, same as today’s store tests. Cover: delete Connection removes it, source Recipes, and secrets; History unchanged; destination-only Recipes remain; save order and append-on-create; last Recipe recorded only when a Pull ran with that Recipe; deleted Recipe clears preselect; History append caps at 100 newest; clear-all empties.

- Window chrome (dot gone, trailing buttons, confirm alerts, default height) is not a third automated seam; verify by running the app. Do not add snapshot tests for padding.

- Prior art: `PullTests` at the Pull seam with fake process runner, fake tunnels, memory secrets.

## Out of Scope

- Gzip of the dump file, remote `mysqldump | gzip`, or a user-facing compression checkbox.
- Percent complete, ETA, or determinate byte progress bars.
- Table N of M during import.
- Per-row History delete.
- Live `SHOW DATABASES` or replacing prototype table checkboxes with live lists (except `SHOW TABLES` for dump progress).
- Live MySQL ping / status dot.
- Edit Connection screen (still New Connection only unless another ticket says otherwise).
- Re-running History, Restore, parallel Pulls, dark mode, App Store.

## Further Notes

- Seams for `/to-tickets`: Pull vs persisted workspace. Do not split “English labels” into its own ticket.
- V1 spec still said window ~980×720 and Recipe buttons hugging left; this spec wins for height and trailing Duplicate/Delete.
- “7 of 10 tables” is table count, never implied as 70% of data.
