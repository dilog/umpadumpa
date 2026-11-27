# Security Policy

## Supported Versions

Only the latest release is actively maintained. Users should always update to the most recent version.

## Reporting a Vulnerability

If you discover a security vulnerability, please report it privately:

- **Email:** gabriele@alfacomm.it

Please include a clear description of the issue and steps to reproduce it. Avoid including sensitive data (passwords, keys) in the report.

You should receive a response within a reasonable time frame. If you do not, please follow up.

Do **not** open a public GitHub Issue for security vulnerabilities. Private reporting helps protect all users until a fix is available.

## Security Design

UmpaDumpa follows these security principles:

- **macOS Keychain:** All passwords and SSH key passphrases are stored in the macOS Keychain, not in plain text files.
- **No bundled binaries:** The app uses the system's `mysql` and `mysqldump` clients, avoiding the need to ship and update third-party binaries.
- **No external network calls:** The app communicates only with MySQL/MariaDB servers you configure. No telemetry, analytics, or update servers.
- **Workspace files are secrets-free:** Exported workspace files (`.umpadumpaworkspace`) contain Connections, Recipes, and Settings paths — never secrets.
- **Temporary files are cleaned up:** Dump files created during import are stored in the system temp directory and deleted after use.
- **Destructive operations require confirmation:** Drop database and backup operations require explicit user confirmation before execution.
