# 01: Connection header, Recipe row, window height

**What to build:** The selected Connection’s header shows MySQL host, port, and whether SSH is on, with no status dot. Duplicate and Delete on a selected Recipe sit on the trailing side of the Recipe row and stay hidden when None is selected. The window opens about 840 points tall and can still shrink to about 720. Copy is English. Parent spec: `.scratch/sidebar-pull-feedback/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Header has no ping / status dot
- [x] Header shows host, port, and SSH vs not
- [x] Duplicate and Delete are trailing; only when a Recipe is selected
- [x] Default window height is about 840; minimum height about 720

## Answer

Selected Connection header is `host:port` plus `· SSH` when the tunnel is on (`Connection.detail`); the green ping dot is gone. Recipe Duplicate/Delete sit after a spacer on the trailing side and only when a Recipe (not None) is selected. Window default is 980×840; content can still shrink to min height 720. No new automated tests — spec says window chrome is not a seam.
