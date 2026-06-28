; Codex Forge - bare-Windows bootstrapper.
; Runs on a freshly-reset machine with cmd.exe / Windows PowerShell blocked.
; Uses curl.exe + tar.exe shipped in Windows System32 to fetch portable
; PowerShell 7, then hands off to bootstrap/install.ps1 for the rest.
Unicode true
ManifestSupportedOS all
Name "Codex Forge - Environment Setup"
OutFile "setup.exe"
RequestExecutionLevel user
ShowInstDetails show
XPStyle on
Caption "Codex Forge - Environment Setup"

Page instfiles

!define PWSHZIP "https://github.com/PowerShell/PowerShell/releases/download/v7.6.2/PowerShell-7.6.2-win-x64.zip"
!define PWSHDIR "C:\Users\CKIRUser\Downloads\PowerShell-7.6.2-win-x64"

Section "Bootstrap"
  DetailPrint "=== Codex Forge environment setup ==="
  DetailPrint "Fetching portable PowerShell 7 with curl/tar from Windows System32."

  ; ---- PowerShell 7 portable ----
  IfFileExists "${PWSHDIR}\pwsh.exe" pwsh_ready
    DetailPrint "Downloading PowerShell 7.6.2 ..."
    ExecWait 'curl.exe -L --fail -o "$TEMP\codex-pwsh.zip" "${PWSHZIP}"' $0
    DetailPrint "curl(pwsh) exit: $0"
    CreateDirectory "${PWSHDIR}"
    DetailPrint "Extracting PowerShell 7 ..."
    ExecWait 'tar.exe -xf "$TEMP\codex-pwsh.zip" -C "${PWSHDIR}"' $0
  IfFileExists "${PWSHDIR}\pwsh.exe" pwsh_ready
    DetailPrint "!! PowerShell 7 setup failed (check internet) - aborting."
    Goto done
  pwsh_ready:
  DetailPrint "PowerShell 7 ready."

  ; ---- run the engine (Node + Python + GitHub CLI + Codex CLI) ----
  IfFileExists "$EXEDIR\install.ps1" run_engine
    DetailPrint "!! install.ps1 not found next to setup.exe."
    Goto done
  run_engine:
  DetailPrint "Running install.ps1 ..."
  ExecWait '"${PWSHDIR}\pwsh.exe" -NoProfile -ExecutionPolicy Bypass -File "$EXEDIR\install.ps1"' $0
  DetailPrint "install.ps1 exit: $0"

  done:
  DetailPrint "=== Finished. ==="
  DetailPrint "Next: run 'codex login --device-auth' if Codex is not logged in."
  DetailPrint "Optional: run 'gh auth login --hostname github.com --git-protocol https --web'."
SectionEnd
