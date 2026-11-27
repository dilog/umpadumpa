<div align="center">

<img src="docs/screenshots/00-logo.png" width="120" alt="UmpaDumpa">

# UmpaDumpa

*Pull a MySQL/MariaDB database from a remote server onto your Mac — with a GUI, in one click.*

</div>

## Why

Every time you need a fresh copy of a remote database for local debugging — whether it is a one-off or something you repeat dozens of times a week — the ritual is always the same: SSH in, run `mysqldump`, download the file, import it locally, fix the charset, drop the old DB, re-import. With UmpaDumpa you save your server once as a connection, define the source and destination once as a recipe, and every time you need a fresh DB you just click once. It remembers everything you configured, so you never have to repeat the steps.

## What it does

![UmpaDumpa](docs/screenshots/01-connections.png)

- **Connections** — save your remote MySQL/MariaDB servers, with or without SSH tunneling. Credentials live in the macOS Keychain.
- **Recipes** — a recipe is a source → destination mapping. Set it once, reuse it forever.
- **Three import strategies** — Replace (drop + restore), Backup + Replace, or New Database. Choose per recipe.
- **Table-level control** — select which tables to sync. Skip large, unnecessary ones.
- **Bookmarks** — save and restore table selections.
- **SSH tunneling** — connect to remote servers behind firewalls.
- **macOS native** — SwiftUI + SwiftData, fully native menus, keyboard shortcuts, dark mode.

## Installation

Download [UmpaDumpa.zip (v1.1.0)](https://github.com/dilog/umpadumpa/releases/download/v1.1.0/UmpaDumpa.zip) for immediate install, or browse [older releases](https://github.com/dilog/umpadumpa/releases).

Unzip and drag `UmpaDumpa.app` into `/Applications`.

The build is signed with a Developer ID certificate and notarized by Apple, so it opens without Gatekeeper warnings.

You need a MySQL client on your Mac — `mysql` and `mysqldump` from Homebrew (`brew install mysql-client`) or the official MySQL package. If yours lives somewhere unusual, set the paths in **Settings**.

Requires Xcode 15+ on macOS 14+.

```bash
git clone https://github.com/dilog/umpadumpa.git
cd umpadumpa
open umpadumpa.xcodeproj
```

Build and run from Xcode. The app packages a bundled `mysql` and `mysqldump` from Homebrew's `mysql-client` — no extra setup needed.

## Configuration

- **MySQL path** — if `mysql` and `mysqldump` are not in your `$PATH`, set the full path in **Settings → MySQL**.
- **SSH keys** — use standard OpenSSH keys in `~/.ssh/`. The app uses `ssh` and `sftp` commands.
- **Keychain** — connection credentials are stored in the macOS Keychain via the `KeychainAccess` framework.

## Architecture decisions

Architecture decisions are documented in [`docs/adr/`](docs/adr/).

## AI-Assisted Development

This project was developed using agentic AI workflows — primarily [Cursor](https://cursor.com) with the Grok 4.7 model — under continuous human direction and architectural oversight.

- **Code generation:** Core features, boilerplate, and build scripts were drafted by autonomous AI agents.
- **Human review:** All code, security boundaries, and final releases were reviewed and verified by the maintainer.

## License

MIT License — see [LICENSE](LICENSE). Use it, fork it, sell it, ship it in your own product; just keep the copyright notice.

## Author

Gabriele Di Lorenzo — gabriele@alfacomm.it

## Acknowledgements

Built with SwiftUI and SwiftData. Architecture decisions are documented in [`docs/adr/`](docs/adr/).
