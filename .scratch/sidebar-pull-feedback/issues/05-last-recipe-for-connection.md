# 05: Last Recipe for a Connection

**What to build:** Selecting a Connection preselects the last Recipe that ran a Pull from that Connection, including a failed Pull. A one-off Pull (None) does not change that memory. If the developer has never Pull’d with a Recipe from that Connection, or that Recipe was deleted, the picker is None. The Pull request carries the Recipe id so last-used is recorded at the Pull, not by guessing from the picker. Parent spec: `.scratch/sidebar-pull-feedback/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Pull with a Recipe selected records that Recipe for the source Connection (success or failure)
- [x] One-off Pull does not change the recorded Recipe
- [x] Selecting the Connection loads that Recipe into the form
- [x] Missing or deleted Recipe → None
- [x] Tests at Pull + persisted workspace, not SwiftUI identity

## Answer

Last Recipe id lives on the Pull request and is written by Pull when a Recipe id is present (success or failure). One-off Pulls leave the map alone. Selecting a Connection loads that Recipe if it still exists; a missing or deleted Recipe is None. Persisted in `last-recipes.json`.
