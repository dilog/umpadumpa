# 06: Protocol compression on dump

**What to build:** Source dump and Backup dump always ask the MySQL client for protocol compression (zstd/zlib, uncompressed fallback). There is no Gzip file option and no remote dump-over-SSH. Parent spec: `.scratch/sidebar-pull-feedback/spec.md`.

**Blocked by:** None (can start immediately)

**Status:** resolved

- [x] Source `mysqldump` invocations include compression-algorithms
- [x] Backup `mysqldump` invocations include the same
- [x] No Gzip of the temp dump file
- [x] Pull seam tests assert the dump command, not a live bastion

## Answer

`mysqldump` (source and Backup) always gets `--compression-algorithms=zstd,zlib,uncompressed`. The temp dump stays a `.sql` file. There is no Gzip flag and no remote dump-over-SSH. Pull tests assert that argv.
