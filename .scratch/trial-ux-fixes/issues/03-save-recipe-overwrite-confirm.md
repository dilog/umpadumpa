# 03: Save recipe overwrite confirm

**What to build:** Save recipe with picker on None asks for a title and creates. Save recipe with a Recipe selected shows an English overwrite confirmation before writing; Cancel leaves the Recipe unchanged. No Save as new on that path in this pass. Parent spec: `.scratch/trial-ux-fixes/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] None selected → title sheet → create (unchanged happy path)
- [x] Recipe selected → confirm overwrite → Save writes / Cancel aborts
- [x] No Save as new while a Recipe is selected
- [x] Copy in English

## Answer

Save recipe with picker on None still opens the title sheet and creates. With a Recipe selected, “Overwrite Recipe?” confirms before `persistSelectedRecipe()`; Cancel leaves the Recipe unchanged. No Save as new on that path.

## Comments
