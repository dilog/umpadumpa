# umpadumpa

A macOS app for copying a MySQL database from one server onto another, usually a remote production database onto a local development server. The product name is UmpaDumpa, not DB Pull.

## Language

**UmpaDumpa**:
The app. A database pull manager for developers, not a SQL client.
_Avoid_: DB Pull, Sequel Ace, TablePlus, umpadumpa as all-lowercase in the UI

**Connection**:
A saved MySQL server you can reach. Remote and local servers are the same kind of thing. A Connection does not name a database. The app opens on Connections: you pick one before you Pull. That Connection is the source of the Pull. The sidebar order is the user’s and is saved; a new Connection is appended. A Connection can be deleted after confirm: it goes away with its Keychain secrets and with Recipes whose source is that Connection. History rows are not rewritten.
_Avoid_: Bookmark, server bookmark, project, host, DB server

**Recipe**:
An optional saved set of defaults for a Pull: source Connection and database, destination Connection and database, a Strategy, a Replace mode, and optionally a list of tables. An empty table list means the entire Database. After picking a Connection, only Recipes whose source is that Connection are offered. Changing fields for one Pull does not update the Recipe unless the user saves. Selecting a Connection leaves the Recipe picker on None with empty form defaults; the app does not remember or preselect the last Recipe used from that Connection.
_Avoid_: Bookmark, project, preset, connection (a Connection is only the server)

**Database**:
A named MySQL database that lives on a Connection. System databases (`mysql`, `information_schema`, `performance_schema`, `sys`) are hidden unless the user shows them. The user picks a Database from a live list on that Connection; they do not type the name except when creating a new Database (or naming a Backup).
_Avoid_: Schema, catalog, server

**Table**:
A named object in a Database that can appear in a subset Pull: a base table or a view. An empty list on the Pull still means the entire Database, views included.
_Avoid_: Collection, relation, schema object

**Strategy**:
How a Pull treats the destination if it already exists: replace, backup then replace, or create a new Database.
_Avoid_: Operation, mode, import type

**Replace mode**:
When writing into an existing Database, whether to DROP DATABASE then import, or import in place (overwrite dumped tables, leave the rest). A table-subset Pull is always import in place.
_Avoid_: Merge, sync, apply

**Backup**:
A Database created on the destination Connection before a replace, holding the previous destination. The default name is `{database}_backup_YYYYMMDD_HHMM`; the user can change it on confirm. If that name already exists, the Pull does not start. In V1 a Backup is only a Database in MySQL; umpadumpa does not restore it.
_Avoid_: Snapshot, clone, copy (a Pull is the copy from remote)

**Pull**:
One run of copying a source Database onto a destination, always after a confirm summary. The copy is the entire Database unless the Pull names a subset of tables. A subset Pull into an existing destination overwrites only those tables. Only one Pull runs at a time. A Pull can follow a Recipe or be a one-off. The source copy finishes before the destination is changed. If the destination import fails or the user cancels, any Backup still exists and the destination is not treated as successful. Create-new does not start if the new name already exists.
_Avoid_: Sync, import, dump

**History**:
A local log of Pulls that already happened: when, source, destination, succeeded or failed. You cannot re-run a Pull from History. The log keeps the most recent 100 rows. The user can empty the whole log after confirm; they cannot delete one row.
_Avoid_: Recipe, Storico as a second concept

**Workspace file**:
A file on disk holding Connections, Recipes, and the Settings paths for `mysqldump` and `mysql`. It has no passwords and no History. It is not a Backup.
_Avoid_: Backup, settings backup, snapshot

## Facts (do not invent otherwise)

- The Dock and the sidebar say **UmpaDumpa**. The window title bar does not repeat the name. The Xcode target, repo folder, Application Support directory (`~/Library/Application Support/umpadumpa`), and Keychain service stay `umpadumpa`.
- Bundle id: `it.alfacommunication.UmpaDumpa`. Debug/release on this Mac: Apple Development, team Alfa Communication (`3N673T64VD`). Keychain Always Allow sticks across rebuilds with that team and bundle id.
- Minimum macOS is **26 (Tahoe)**. The Xcode default was 27; that made a Tahoe Mac refuse to launch. Sequoia (15) and older are out of V1 unless we decide otherwise. A zip already built with 27 must be rebuilt to run on Tahoe.
- Clients: Settings `mysqldump` / `mysql` paths, not bundled binaries. Homebrew MySQL 9 cannot talk to servers that still use `mysql_native_password`; this machine’s Settings point at `mysql-client@8.0` (`/opt/homebrew/opt/mysql-client@8.0/bin/...`). That is one Settings pair for the whole app, not per Connection. When both paths are empty and the user has not finished the first-open sheet, the app explains that empty means PATH and why `mysql-client@8.0` is often required. Continue saves the paths and dismisses that sheet for good, even if both stay empty. Not now discards what was typed and shows the sheet again on the next launch while both paths are still empty.
- Visible UI copy is English for now (including progress strings such as “7 of 10 tables”).
- macOS UI follows Apple’s Human Interface Guidelines and the native SwiftUI or AppKit control for each job. Prefer the system look, motion, and interaction. Do not invent a custom control, gesture, or decoration when the platform already has the recommended one.
- Source and destination Database pickers load live `SHOW DATABASES` (session cache, Refresh). Selected tables loads live `SHOW TABLES` (tables and views, no session cache). Recipe names missing on the server stay selectable and marked absent. For dump progress on an entire Database, the Pull still runs its own `SHOW TABLES`; a subset Pull uses the Pull’s table list. There is no live MySQL ping. The selected Connection’s header shows host, port, and whether SSH is on; no status dot.
- Connections can be deleted from the sidebar after confirm. Sidebar order is the user’s and is saved; a new Connection is appended.
- Pull progress sits by the footer buttons. While dumping (and while dumping a Backup): spinner, “N of M tables” (tables completed, not bytes or ETA), and dump file size in MB when cheap. Import is spinner plus “N MB of M MB” sent to `mysql`, not a table count. The outcome stays on that Connection’s Pull screen until the user closes it, changes Recipe, selects another Connection, or starts another Pull. History and Settings do not clear it. “Recipe saved.” stays brief. Failures stay copyable.
- A Workspace file is exported and imported from Settings. Import replaces Connections, Recipes, and the client paths after confirm. Connection ids are kept, so Keychain secrets on this Mac still match; passphrases and passwords are never in the file. A Connection missing from the file is deleted with its Keychain secrets and with Recipes whose source is that Connection. History is not changed. An unreadable file changes nothing. Import is unavailable while a Pull is running. Export stays available during a Pull. A failed Import stays on Settings until the user closes it or starts another Import. A successful Import shows a brief “Workspace imported.”
- Source dump (and destination dump for Backup) always asks the MySQL client for protocol compression (`zstd`/`zlib`, falling back if the server cannot). This is not a Gzip file option and not remote `mysqldump | gzip`.
- Duplicate and Delete on a selected Recipe sit to the trailing side of the Recipe picker.
- First-open window is taller than the old 720 pt default (about 840) so the footer is not flush with the bottom; the window can still shrink to 720.
- App icon (Dock and Finder): `umpadumpa/Resources/AppIcon.icns`, built from the opaque full-bleed `AppIcon.png` (cream, orange disc, mascot). Do not wrap that PNG in an Icon Composer `.icon` or set `CFBundleIconName` — on macOS 27 the Dock then draws Apple’s gray squircle instead of the illustration. The cut-out mascot is `AppIcon-mascot.png` (source only, not the Dock). Sidebar logo is a separate asset, `AppLogo`. A rebuild does not refresh `/Applications/UmpaDumpa.app` by itself.
- Other Macs get a notarized zip of a Developer ID–signed `UmpaDumpa.app` (`scripts/distribute-macos.sh`). Not the Mac App Store. Recipients unzip and drag into `/Applications`; they do not use the developer Apple ID. Copying `UmpaDumpa.app` to `/Applications` is still how this Mac double-clicks; a rebuild does not refresh that copy by itself. Debug and Archive stay Apple Development; export to Developer ID happens in the distribute script. Release has Hardened Runtime (needed for notarization).
