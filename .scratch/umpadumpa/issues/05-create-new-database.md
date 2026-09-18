# 05: Create new Database

**What to build:** Strategy create-new imports into a new Database name the developer types on the Destination card. The existing destination Database is not dropped or overwritten. If that new name already exists, the Pull does not start. Confirm shows the new name.

**Blocked by:** 01 One-off Pull, import in place

**Status:** resolved

- [x] Choosing Create new shows a Database name field and hides Replace mode (there is no existing Database to replace)
- [x] Confirm dump shows the new Database name as destination
- [x] If the name already exists, the Pull does not start and nothing is created
- [x] On success the new Database exists and the previous destination Database is unchanged
- [x] Pull seam tests cover create-new success and name collision
