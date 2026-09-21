# 02: Remove last Recipe memory

**What to build:** Selecting a Connection always leaves Recipe on None with empty form defaults. Stop recording last Recipe on Pull; remove `last-recipes.json`, the last-Recipe store, and related tests. Aligns with ADR 0017 and `CONTEXT.md`. Parent spec: `.scratch/trial-ux-fixes/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] `selectNav` / Connection select never preselects a Recipe
- [x] Pull no longer records last Recipe
- [x] Last-Recipe store and `last-recipes.json` removed
- [x] Related unit tests removed or rewritten to assert no memory
- [x] Supersedes sidebar-pull-feedback stories 15–19 behaviour

## Answer

Selecting a Connection leaves Recipe on None with empty form defaults (`selectNav` no longer calls last-used restore). Pull only appends History; it does not record a last Recipe. `LastRecipeStoring`, `DiskLastRecipeStore`, `MemoryLastRecipeStore`, and `last-recipes.json` are gone. Tests assert History still records with a Recipe id, and that a Recipe Pull does not create `last-recipes.json`.

## Comments
