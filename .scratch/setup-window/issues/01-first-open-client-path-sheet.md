# 01: First-open client path sheet

**What to build:** When both client paths are empty, the first open shows a sheet that explains empty means PATH and why `mysql-client@8.0` is often required. The developer can set `mysqldump` and `mysql` there, including choosing each file. Continue saves the paths, even if both stay empty, and the sheet does not return. Not now, Escape, and closing the sheet discard what was typed and show the sheet again on the next launch while both paths are still empty. If either path is already saved, the sheet does not appear. Decisions are in `CONTEXT.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Both client paths empty and the sheet not finished shows the sheet on launch
- [x] The sheet explains PATH and why `mysql-client@8.0` is often required, in English
- [x] Continue saves both paths, including when they are empty, and the sheet does not return
- [x] Not now, Escape, and closing the sheet save nothing and the sheet returns next launch while both paths are still empty
- [x] A saved path on either client skips the sheet
- [x] Workspace tests cover Continue versus Not now; the sheet itself is checked by running the app

## Answer

Continue saves both paths and `firstOpenSheetFinished`, so the sheet stays gone even when both paths are empty. Not now, Escape, and closing the sheet only defer it for this launch. The next launch shows it again while both saved paths are still empty. A saved path on either client skips the sheet. `FirstOpenClientSheetTests` covers Continue versus Not now. The sheet UI is checked by running the app.
