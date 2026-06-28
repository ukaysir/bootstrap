# Codex Forge - environment bootstrap

This machine resets on reboot, so globally installed tools and credentials may
disappear. This folder restores a Codex-oriented Windows development environment
with the fewest moving parts.

The bootstrap is now PowerShell 7 based. Git Bash is no longer part of the main
setup path.

## Use it after a reset

1. Download or extract this repository.
2. Open the `bootstrap` folder.
3. Double-click `setup.exe`.
4. When setup finishes, open PowerShell 7 and run:

```powershell
codex login --device-auth
gh auth login --hostname github.com --git-protocol https --web
codex
```

`codex login --device-auth` is the preferred login path when browser callbacks
or localhost redirects are blocked.

## What setup.exe does

`setup.exe` is a small NSIS launcher. On a bare reset machine it:

1. Downloads portable PowerShell 7.6.2 with Windows built-in `curl.exe`.
2. Extracts it with Windows built-in `tar.exe`.
3. Runs `install.ps1` using the portable `pwsh.exe`.

After `pwsh.exe` is available, the rest of setup runs in PowerShell 7.

## What install.ps1 does

`install.ps1` restores:

| Tool | Location / method |
| --- | --- |
| Node.js 24.18.0 | `C:\Users\CKIRUser\tools\node` |
| Python 3.12 | winget user install |
| pip | Python Scripts directory |
| GitHub CLI | winget user install |
| Codex CLI | global npm package `@openai/codex@latest` |
| Codex config | `C:\Users\CKIRUser\.codex\config.toml` |
| PATH | user PATH where allowed, plus current process PATH |

The npm install path calls `npm-cli.js` through `node.exe` directly. That avoids
the `npm.cmd` shim, which matters on machines where `cmd.exe` is blocked.

## Files

- `setup.exe` - Windows entry point compiled from `setup.nsi`.
- `setup.nsi` - NSIS source for the setup launcher.
- `install.ps1` - main Codex bootstrap engine.
- `install.sh` - legacy compatibility stub; it now points users to `install.ps1`.
- `patch-vite.mjs` - legacy Claude Forge app patch, not part of the Codex setup path.
- `patch-app-builder.mjs` - legacy Claude Forge app patch, not part of the Codex setup path.

## Manual fallback

If `setup.exe` is stale or unavailable but PowerShell 7 already exists:

```powershell
C:\Users\CKIRUser\Downloads\PowerShell-7.6.2-win-x64\pwsh.exe -NoProfile -ExecutionPolicy Bypass -File C:\path\to\bootstrap\install.ps1
```

If PowerShell 7 is missing, download and extract:

```text
https://github.com/PowerShell/PowerShell/releases/download/v7.6.2/PowerShell-7.6.2-win-x64.zip
```

Then run `install.ps1` with the extracted `pwsh.exe`.

## Notes

- Credentials are not embedded. Run Codex and GitHub login after setup.
- `~\.codex\auth.json` can contain access tokens. Do not commit or share it.
- `setup.exe` is unsigned, so Windows SmartScreen may warn.
- If `cmd.exe` and Windows PowerShell are blocked, keep using portable
  PowerShell 7 for manual recovery commands.
