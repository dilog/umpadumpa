# A table-subset Pull does not drop the destination Database

When the Pull names some tables and the destination Database already exists, umpadumpa overwrites only those tables (drop/recreate table, then import), the way Sequel Ace does a table dump into a live database. Other tables on the destination stay. Entire-Database replace still DROP DATABASE + CREATE + import. Backup-then-replace with a subset still makes a Backup of the whole destination Database, then overwrites only the named tables in place.

Rejected: DROP DATABASE on a subset Pull (that would delete local tables the user did not choose), and a separate Strategy just for tables.
