# Source copy finishes before the destination is touched

A Pull copies the source to completion first, then changes the destination. If the destination import fails, umpadumpa does not treat that Database as good; a Backup from backup-then-replace is still there.

Rejected: streaming the remote dump straight into local MySQL, and automatic rollback to the exact previous destination. Streaming is faster but a drop mid-import leaves a half-written database with no backup. Full rollback is a second failure-prone pipeline.

Every Pull is confirmed with a summary (source, destination, strategy, backup name if any) before it starts.
