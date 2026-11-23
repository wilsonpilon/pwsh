# BrowserProfileSync 0.1.6

Read-only diagnostic build.

## New in 0.1.6
- Inventory and approximate sizes for Chromium web application data per profile:
  - IndexedDB
  - Local Storage
  - Session Storage
  - WebStorage
  - Service Worker
- Inventory and approximate sizes for browser files/databases:
  - Cookies (`Network\\Cookies`)
  - History
  - Login Data
  - Web Data
  - Favicons
  - Preferences
  - Secure Preferences
- Wider diagnostic labels for profile names.

Supported discovery currently covers Microsoft Edge, Google Chrome, and Vivaldi.

## Run
```powershell
pwsh -File .\\BrowserProfileSync.ps1 doctor
```

`doctor` is read-only. It does not stop browsers or create, copy, edit, or delete browser data.
