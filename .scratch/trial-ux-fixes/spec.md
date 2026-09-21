# Trial UX fixes

Status: ready-for-agent

## Problem Statement

After trying the current app, a few Connection / Recipe / History / chrome gaps hurt daily use: no way to edit a Connection, delete only as a sidebar trash icon, Save recipe overwrites silently, History is oldest-first with fixed columns, no visible app version, and last-Recipe restore on Connection select should go away entirely.

## Solution

Edit and Delete Connections from a sidebar context menu (and Delete from the Edit sheet); remove the trash icon. Selecting a Connection always starts on Recipe None and the last-Recipe store is removed (ADR 0017). Save recipe asks for a title when creating; confirms before overwriting a selected Recipe. History defaults to When descending and columns are sortable. Show marketing version by the sidebar name and add a standard macOS About.

## User Stories

1. As a developer, I want a context menu on a Connection in the sidebar with Edit… and Delete…, so that I can change or remove a server without a trash icon on every row.
2. As a developer, I want no trash icon on the Connection sidebar row, so that delete is deliberate via the menu (or Edit sheet).
3. As a developer, I want Edit… to open a sheet with the same fields as New Connection, so that I can fix host, user, SSH, and the rest.
4. As a developer, I want a blank password field on Edit to leave the Keychain password unchanged, and a filled field to update it (same idea for SSH password/passphrase), so that I am not forced to re-type secrets to change the host.
5. As a developer, I want Delete… from the context menu and from the Edit sheet to use the same English confirmation as today (Connection, secrets, source Recipes gone; History unchanged), so that delete stays one rule.
6. As a developer, I want selecting a Connection to leave Recipe on None with empty form defaults, so that I always choose the job explicitly.
7. As a developer, I want the last-Recipe memory gone (no recording on Pull, no `last-recipes.json`, no related tests), so that dead behaviour cannot surprise me later.
8. As a developer, I want Save recipe with no Recipe selected to ask only for a title and create a new Recipe, so that first-time save stays simple.
9. As a developer, I want Save recipe with a Recipe selected to confirm overwrite before writing, so that I do not clobber a named Recipe by accident.
10. As a developer, I want History ordered by When descending by default, so that the newest Pull is at the top.
11. As a developer, I want History column headers sortable (at least When, and the other columns too), so that I can re-order the log without leaving the table.
12. As a developer, I want the marketing version in small text by the UmpaDumpa name in the sidebar, so that I can see which build I am running at a glance.
13. As a developer, I want UmpaDumpa → About UmpaDumpa with name, marketing version, and build when the bundle has it, so that version follows macOS convention.
14. As a developer, I want all of this copy in English, so that chrome stays one language.

## Implementation Decisions

- This spec supersedes sidebar-pull-feedback user stories 15–19 and the last-Recipe implementation decision there. ADR 0017 is the decision record.
- UI terms stay **Connection** and **Recipe** (not Bookmark). ADR 0001 still applies.
- Context menu only: Edit… and Delete…. No Duplicate Connection, no Test in V1.
- Edit sheet reuses New Connection fields. Empty secret fields = do not call Keychain set. Non-empty = update.
- Save recipe: no “Save as new” on the overwrite path in this pass; create only when picker is None.
- History cap 100 and clear-all unchanged; still no per-row delete; still not re-runnable (ADR 0008).
- Sidebar version: marketing version only (e.g. `1.0.0`). About may show version + build.
- Respect `CONTEXT.md` and ADRs 0001–0017.

## Testing Decisions

- Assert store/Pull behaviour for last-Recipe removal (nothing recorded; file gone or unused).
- Assert Connection update keeps password when edit password is blank; updates when set.
- Assert History ordering seam if there is one; do not assert SwiftUI Table sort chrome identity beyond what is practical.
- Do not assert exact About panel layout pixels.

## Out of scope

- Renaming Connection to Bookmark in the UI
- Save as new while a Recipe is selected
- Duplicate Connection / Test Connection
- Per-row History delete or re-run from History
- Changing History cap or clear-all rules
