# Existing names abort create-new and Backup

If the user picks Create new and that Database already exists, or the Backup name is already taken, the Pull does not start. They choose another name.

Rejected: overwrite, and auto-suffix `_2`. Overwrite would skip Replace. Auto-suffix hides collisions.
