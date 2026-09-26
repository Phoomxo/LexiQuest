# Backup categories and recovery

1. Source and version history: remote backup branch and local source-history.bundle. Snapshot is through S01-BC; earlier checkpoints retain their actual names, not invented v1-v5 releases.
2. Historical delivery reports, receipts and test records: original paths at backup commit c22cdaa3a11b83c8e3ce84151672ed8dab11a4e1. Use git show COMMIT:path for a specific record.
3. Ignored evidence, media and byte-exact dirty overlay: preserved-overlay/ under C:/Users/Phet/LexiQuest-Backups/2026-09-26-S01-BC. Inventory includes each path, size and SHA256. This evidence backup is local, not uploaded to GitHub.
4. Recovery: clone source-history.bundle into a separate destination, checkout the backup branch, apply preserved-overlay by original relative paths, honor inventory deletions, then verify SHA256 against backup-inventory.json. Inventory itself is separately preserved.
5. Verification: remote ref equals local backup commit; bundle verifies complete history; restored-git-blobs.zip matches all 5124 Git blobs; all 3180 inventory entries copied with matching hashes.

Do not restore caches or copy archives into routine app work. Old worktrees require individual ownership/activity and preservation checks before native archival. Their retirement is still pending.
