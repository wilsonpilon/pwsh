# BrowserProfileSync 0.1.4

Read-only diagnostic development build.

## Implemented
- PowerShell 7 and Windows diagnostics
- OneDrive root detection via standard environment variables
- Microsoft Edge, Google Chrome, and Vivaldi detection
- Browser executable version/path and Chromium `User Data` path detection
- Read-only running-process detection for `msedge`, `chrome`, and `vivaldi`

## Not implemented yet
- Backup destination selection
- Browser profile enumeration
- IndexedDB / Local Storage inspection
- Backup and restore

## Run
```powershell
pwsh -File .\BrowserProfileSync.ps1 doctor
```

The `doctor` command is read-only. It does not terminate browser processes or create, copy, modify, or delete browser data.
