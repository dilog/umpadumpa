# 02: Remove last Recipe memory

**What to build:** Selecting a Connection always leaves Recipe on None with empty form defaults. Stop recording last Recipe on Pull; remove `last-recipes.json`, the last-Recipe store, and related tests. Aligns with ADR 0017 and `CONTEXT.md`. Parent spec: `.scratch/trial-ux-fixes/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] `selectNav` / Connection select never preselects a Recipe
- [ ] Pull no longer records last Recipe
- [ ] Last-Recipe store and `last-recipes.json` removed
- [ ] Related unit tests removed or rewritten to assert no memory
- [ ] Supersedes sidebar-pull-feedback stories 15–19 behaviour

## Comments
