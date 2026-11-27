# Entire-Database replace asks drop vs import in place

Replace used to mean DROP DATABASE + CREATE + import. After table-subset Pulls landed as Sequel Ace-style in-place import, a full Pull into an existing Database needs the same fork: drop the Database then import (local becomes an exact copy, extra tables gone), or import in place (overwrite dumped tables, leave others). That choice is Replace mode, stored on the Recipe, shown under Replace and Backup-and-replace when Tables is All tables. A table-subset Pull still cannot drop the Database (ADR 0013). Backup-then-replace still copies the whole destination Database first, then applies the chosen Replace mode. New forms default to import in place (less destructive); drop-database is explicit. Confirm always names the mode.

Rejected: keeping full replace as drop-only, and adding a fourth Strategy instead of a Replace mode under replace.
