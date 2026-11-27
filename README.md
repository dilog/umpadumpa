# UmpaDumpa

Pull a MySQL/MariaDB database from a remote server onto your Mac — with a GUI, no `mysqldump` archaeology.

![UmpaDumpa](docs/screenshots/00-logo.png){width=200}

![UmpaDumpa](docs/screenshots/01-connections.png)

## Why

Every time you need real data locally for a bug or a feature, the ritual is the same: SSH in, `mysqldump`, download, import, fix the charset, drop the old DB, re-import. UmpaDumpa makes that a single click, and remembers how you did it.

## What it does

- **Connections** — save your remote MySQL/MariaDB servers, with or without SSH tunneling. Credentials live in the macOS Keychain.
- **Recipes** — a recipe is a source → destination mapping. Set it once, reuse it forever.
- **Three import strategies**
  - **Replace** — drop the destination database and recreate it
  - **Backup then replace** — keep a backup, then replace
  - **Create new** — import alongside existing databases, nothing destroyed
- **Table-level control** — dump only the tables you need, for databases too big to copy whole
- **History** — every pull, with timestamp, duration and outcome
- **Bookmarks** — pin the databases and recipes you use daily

## Installation

Download [UmpaDumpa.zip (v1.1.0)](https://github.com/dilog/umpadumpa/releases/download/v1.1.0/UmpaDumpa.zip) for immediate install, or browse [older releases](https://github.com/dilog/umpadumpa/releases).

Unzip and drag `UmpaDumpa.app` into `/Applications`.

The build is signed with a Developer ID certificate and notarized by Apple, so it opens without Gatekeeper warnings.

You need a MySQL client on your Mac — `mysql` and `mysqldump` from Homebrew (`brew install mysql-client`) or the official MySQL package. If yours lives somewhere unusual, set the paths in **Settings**.

## Building from source

Requires Xcode 15+ on macOS 14+.

```bash
git clone https://github.com/dilog/umpadumpa.git
cd umpadumpa
open umpadumpa.xcodeproj
```

Then ⌘R. For a signed and notarized build, see `scripts/distribute-macos.sh`.

## Default MySQL client paths

- `/opt/homebrew/bin/mysql` — Homebrew on Apple Silicon
- `/usr/local/bin/mysql` — Homebrew on Intel
- `/usr/local/mysql/bin/mysql` — official MySQL package

## Privacy

- Database credentials are stored in the macOS Keychain
- Nothing leaves your machine: no telemetry, no analytics, no accounts
- The only network traffic is the database connection itself, plus SSH if you use tunneling

## License

MIT — see [LICENSE](LICENSE). Use it, fork it, sell it, ship it in your own product; just keep the copyright notice.

## Author

Gabriele Di Lorenzo — gabriele@alfacomm.it

## Acknowledgements

Built with SwiftUI and SwiftData. Architecture decisions are documented in [`docs/adr/`](docs/adr/).
