# BrowserProfileSync 0.1.7

Read-only diagnostic build that closes the initial Doctor phase.

## New in 0.1.7
- Wider output labels for long browser/profile names.
- Summary of detected browsers and profiles.
- Estimated total of inventoried web application data and browser databases.
- Backup readiness check: backup is reported BLOCKED while Edge, Chrome or Vivaldi processes are running.
- Read-only backup-location status. An optional `BROWSERPROFILESYNC_BACKUP` environment variable can be inspected, but Doctor never creates the directory.

## Important
The size summary is an estimate of the inventoried protection set, not the size of an entire Chromium profile. Version 0.1.7 still performs no backup and does not stop browsers.

## Run
```powershell
pwsh -File .\BrowserProfileSync.ps1 doctor
```
