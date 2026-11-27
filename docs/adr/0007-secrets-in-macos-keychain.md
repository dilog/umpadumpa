# Secrets live in the macOS Keychain

Connection passwords and SSH key passphrases are stored in the macOS Keychain, never in Connection or Recipe files. Each person on their own Mac has their own Keychain.

Rejected: secrets in config files (even gitignored) and prompting every time without saving. Files leak; prompting every Pull fights the one-setup Connection model.
