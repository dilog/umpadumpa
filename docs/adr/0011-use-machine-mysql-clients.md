# V1 uses the machine's mysql clients

umpadumpa shells out to `mysqldump` and `mysql` on the Mac (PATH, or a path the user sets). It does not bundle those binaries and does not speak the MySQL protocol itself.

Rejected: shipping clients inside the app (size, licensing, updates) and a native Swift driver (a separate product). The user already has the tools for this workflow.
