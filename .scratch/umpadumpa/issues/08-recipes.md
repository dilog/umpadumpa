# 08: Recipes

**What to build:** After picking a Connection, the Recipe picker (title-only, None plus Recipes whose source is that Connection) pre-fills source Database, destination, Strategy, Replace mode, and tables. There is no Start dump on the picker. Changing fields is one-shot until Save recipe. Duplicate copies the Recipe (prototype suffix ` (copy)`). Delete removes it, selects None, and resets the form for the current Connection. Overrides never write themselves.

**Blocked by:** 01 One-off Pull, import in place; 02 Replace mode drop-database; 03 Selected tables; 04 Backup then replace; 05 Create new Database

**Status:** resolved

- [x] Recipe picker is title-only extra-large bordered Menu, hugs title, left-aligned with Duplicate/Delete; options None + Recipes for the sidebar source only
- [x] Choosing a Recipe fills Database, destination Connection/Database, Strategy, Replace mode, and tables; Start dump still requires confirm
- [x] Editing fields then pulling does not change the saved Recipe
- [x] Save recipe persists the current form into the selected Recipe (or creates one if None — if creating, the developer must be able to name it)
- [x] Duplicate keeps the copy selected; Delete selects None and resets the form
- [x] A Recipe with empty `tables` means entire Database; a named list restores Selected tables
- [x] Pull seam / persistence tests: overrides do not persist unless saved; History still cannot re-run a Pull

## Answer

Recipes persist in `recipes.json` (title, source/dest Connection ids, databases, Strategy, Replace mode, `tables`). The picker is None plus Recipes for the sidebar source. Load fills the form; Pull uses the form and does not write the Recipe. Save updates the selected Recipe, or asks for a title when None. Duplicate uses ` (copy)` and stays selected. Delete selects None and resets the form. Empty `tables` is entire Database.
