# One Pull at a time

umpadumpa runs a single Pull at a time. Two imports sharing a local MySQL server are too easy to interleave.

Rejected: parallel Pulls when source and destination differ.
