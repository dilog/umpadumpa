# 06: SSH on Connection

**What to build:** A Connection can reach MySQL through an SSH tunnel: SSH host, custom SSH port, SSH username, password or private key (including a `.pem` path) plus passphrase. Secrets stay in the Keychain. A Pull from that Connection uses the tunnel; a missing or failed tunnel is a clear error and does not touch the destination.

**Blocked by:** 01 One-off Pull, import in place

**Status:** resolved

- [x] New/edit Connection can enable SSH tunnel with host, port, user, password or key path, and passphrase
- [x] SSH passwords and passphrases are Keychain items, not written next to Connection settings
- [x] A Pull whose source (or destination) uses SSH runs dump/import through that tunnel
- [x] Tunnel or auth failure records a failed History row and does not change the destination
- [x] Direct (non-SSH) Connections still work as in ticket 01
- [x] Pull seam tests stub the tunnel/process runner; do not require a live bastion

## Answer

SSH lives on Connection (host, port, user, password or key path). Passwords and passphrases are Keychain accounts, not JSON. Pull opens a stubbed tunnel and points mysqldump/mysql at 127.0.0.1:forwardedPort. Tunnel failure writes a failed History row and never runs destination import. There is no separate Edit Connection screen yet; SSH fields are on New Connection.
