# No last Recipe when selecting a Connection

Selecting a Connection always leaves the Recipe picker on None with empty form defaults. The app does not remember which Recipe last ran a Pull from that Connection.

We tried last-used restore (see `.scratch/sidebar-pull-feedback/`); in practice it was confusing and unreliable for the developer, who prefers an explicit Recipe pick every time. Drop the memory entirely: stop recording on Pull, remove `last-recipes.json` and its store, and delete the related tests.

Rejected: keep recording but hide restore in the UI, and restore last saved or last selected Recipe instead of last Pull’d.
