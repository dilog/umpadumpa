# Duplicate Connection

Status: resolved

## Problem Statement

A developer often needs a second Connection that is almost the same as one they already have (same host, user, SSH tunnel, password) so they can tweak only a name or a detail without retyping everything. Today the sidebar context menu only offers Edit… and Delete…; Recipe already has Duplicate. Creating a near-copy means New Connection and careful re-entry of secrets.

## Solution

Add Duplicate on a Connection’s sidebar context menu. It creates a new Connection with a new identity, the same reachability fields, a name suffix like Recipe’s `" (copy)"`, and Keychain secrets copied to the new id. The copy is appended at the end of the sidebar list and becomes selected. Recipes stay on the original Connection; History is unchanged. No confirmation sheet.

## User Stories

1. As a developer, I want Duplicate on the sidebar Connection context menu, so that I can clone a server entry without leaving the list.
2. As a developer, I want Duplicate next to Edit… and Delete… on that menu, so that Connection actions live in one place.
3. As a developer, I want Duplicate to run immediately with no confirmation, so that cloning stays as light as Recipe Duplicate.
4. As a developer, I want the duplicate Connection to have a new id, so that it is a separate saved server and can be edited or deleted on its own.
5. As a developer, I want the duplicate’s name to be the original name plus `" (copy)"`, so that naming matches Recipe Duplicate.
6. As a developer, I want host, port, user, and all SSH fields copied onto the duplicate, so that reachability matches the original.
7. As a developer, I want the MySQL password in Keychain copied to the new Connection id, so that I can Pull without retyping the password.
8. As a developer, I want SSH password or SSH key passphrase in Keychain copied when the original uses SSH, so that tunnel auth works on the copy.
9. As a developer, I want the duplicate appended at the end of the Connection list, so that sidebar order stays the user’s until they drag.
10. As a developer, I want that order (including the new row at the end) saved to disk, so that the copy is still there after quit.
11. As a developer, I want the app to select the new Connection after Duplicate, so that I land on the copy ready to edit or Pull.
12. As a developer, I want selecting that new Connection to leave Recipe on None with empty form defaults, so that Connection select behaviour stays the same (ADR 0017).
13. As a developer, I want Recipes whose source is the original Connection left pointing at the original, so that Duplicate does not clone or re-home Recipes.
14. As a developer, I want Recipes that use the original only as destination left unchanged, so that Duplicate does not rewrite Recipe destinations.
15. As a developer, I want History left unchanged when I duplicate a Connection, so that the log stays a record of past Pulls only.
16. As a developer, I want deleting the duplicate later to remove only that Connection’s secrets and its own source Recipes (none at first), so that delete rules stay as today.
17. As a developer, I want deleting the original after a duplicate to leave the copy and its secrets intact, so that the two Connections are independent.
18. As a developer, I want Duplicate while a Pull is not required to be blocked specially beyond existing one-Pull-at-a-time rules, so that this feature does not invent new concurrency policy.
19. As a developer, I want all menu and naming copy in English, so that chrome stays one language.
20. As a developer, I want the UI to keep saying Connection (not Bookmark), so that glossary and ADR 0001 stay consistent.
21. As a developer who already has Recipe Duplicate, I want Connection Duplicate to feel like the same idea (new id, `" (copy)"` suffix, select the copy), so that the product has one mental model for clone.
22. As a developer, I want to duplicate a Connection that does not use SSH and get a copy that also does not use SSH, so that direct MySQL Connections clone cleanly.
23. As a developer, I want to duplicate a Connection that uses SSH with password auth and get a working copy, so that bastion setups are reusable.
24. As a developer, I want to duplicate a Connection that uses SSH with private key (and passphrase when stored) and get a working copy with the same key path, so that key-based tunnels clone without re-picking the file.
25. As a developer, I want Duplicate available whether or not the Connection row is currently selected, so that I can clone from the menu on any row I right-click.
26. As a developer, after Duplicate from an unselected row, I want the new Connection selected (not the row I right-clicked left selected), so that focus follows the new server.

## Implementation Decisions

- UI term is **Connection**. This supersedes the trial-ux-fixes decision that left Duplicate Connection out of scope; Edit… / Delete… remain. ADR 0001 and ADR 0007 still apply.
- Prefer the Recipe pattern: a domain `Connection.duplicated()` that returns a new id, same fields, name `original + " (copy)"`. Persist via existing append/save Connection behaviour; copy Keychain secrets from the source id to the new id (MySQL password; SSH password or passphrase when relevant).
- Highest seam: domain duplicate + store/AppModel path that saves the Connection and copies secrets. One behavioural entry point for “duplicate this Connection”; UI only invokes it and selects the new id.
- Do not clone Recipes. Do not rewrite History. Do not open the Edit/New sheet as part of Duplicate.
- Append the new Connection; do not insert beside the original. Selection after duplicate follows Recipe Duplicate (select the copy).
- No new ADR unless implementation discovers a conflict; none known with ADRs 0001–0017.
- Respect `CONTEXT.md` language throughout.

## Testing Decisions

- Good tests assert external behaviour: new id, name suffix, field equality, secrets readable under the new id, original secrets still under the old id, list append order, Recipes/History unchanged. Do not assert SwiftUI context-menu identity or pixel layout.
- Modules under test: Connection domain duplicate; DiskStore / SecretStoring (or AppModel) duplicate path that persists and copies secrets. Prior art: `Recipe.duplicated()` / `testDuplicateKeepsACopyWithSuffixAndDeleteRemovesIt`, and `ConnectionStoreTests` for secrets-on-disk and delete behaviour.
- Cover at least: plain Connection with MySQL password; SSH password auth with SSH secret copied; independence of original vs copy after delete of one.
- Do not require UI snapshot or ViewInspector coverage for the menu item.

## Out of Scope

- Renaming Connection to Bookmark in the UI
- Cloning Recipes onto the duplicate Connection
- “Duplicate and edit” sheet flow, or auto-opening Edit after Duplicate
- Inserting the copy next to the original instead of appending
- Test Connection / live ping from the context menu
- Changing Edit… / Delete… confirm rules
- Duplicate from anywhere other than the sidebar Connection context menu (e.g. Edit sheet button)
- Changing Recipe Duplicate behaviour

## Further Notes

- User request used “bookmark”; product language is Connection (sidebar server). Trial UX explicitly deferred Duplicate Connection; this spec is that follow-up.
- Recipe Duplicate lives on the Recipe picker trailing controls; Connection Duplicate lives only on the sidebar context menu — different chrome, same clone idea.
