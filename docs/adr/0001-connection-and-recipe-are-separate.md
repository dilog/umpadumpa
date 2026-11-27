# Connection and Recipe are separate

The sidebar is for servers you reach once and reuse. A daily Pull needs more than a server: source database, destination server, destination database. Folding those into one “bookmark” makes the sidebar both an address book and a list of jobs.

We keep two objects. A **Connection** is only how to reach a MySQL server. A **Recipe** is a saved Pull (source Connection + database → destination Connection + database). Two Recipes can share one Connection.

Rejected: a single Bookmark that is always “server + both databases”, and a sidebar that is only Recipes with credentials copied into each row.
