# UmpaDumpa

Dump MySQL database from remote servers directly to your Mac — no command line, no manual mysqldump.

## What it does

UmpaDumpa lets you:
- **Save connections** to your remote MySQL/MariaDB servers (with or without SSH tunneling)
- **Save pull recipes** that define source → destination database mappings
- **Dump and import** with three strategies:
  - **Replace** — drop the destination database and recreate it
  - **Backup then replace** — create a backup first, then replace
  - **Create new** — import into a new database alongside existing ones
- **Table-level control** — select which tables to dump (useful for large databases)
- **History** — track every pull operation with timestamps and outcomes
- **Bookmarks** — save favorite databases and recipes for quick access

## Installation

Download the latest release from the [Releases](https://github.com/YOUR_USERNAME/umpadumpa/releases) page.

The app is signed with Developer ID and notarized.

## Building from source

Requires Xcode 15+ and macOS 14+.

```bash
# Open the project
open umpadumpa.xcodeproj

# Build and run (⌘R)
```

## MySQL client paths

UmpaDumpa looks for MySQL clients in these locations by default:
- `/usr/local/bin/mysql` (Homebrew on Intel)
- `/opt/homebrew/bin/mysql` (Homebrew on Apple Silicon)
- `/usr/local/mysql/bin/mysql` (MySQL official package)

Configure the path in Settings if your installation differs.

## Privacy

- Database credentials are stored in the macOS Keychain
- No data leaves your machine
- No telemetry or analytics

## License

[Add your license here]

## Author

Gabriele — Alfa Communication
