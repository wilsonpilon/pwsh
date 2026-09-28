Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
scoop bucket add nerd-fonts
scoop bucket add extras
scoop bucket add games
scoop bucket add java
scoop bucket add main
scoop bucket add nirsoft
scoop bucket add nonportable
scoop bucket add sysinternals
scoop bucket add versions
scoop update