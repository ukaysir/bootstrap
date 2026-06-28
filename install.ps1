# Codex Forge - PowerShell 7 bootstrap engine
# Restores a reset Windows development environment without depending on cmd.exe,
# Windows PowerShell, or Git Bash after this script starts.

[CmdletBinding()]
param(
  [switch]$SkipCodexLogin
)

$ErrorActionPreference = 'Stop'

$UserHome = 'C:\Users\CKIRUser'
$Tools = Join-Path $UserHome 'tools'
$NodeDir = Join-Path $Tools 'node'
$PythonRoot = Join-Path $env:LOCALAPPDATA 'Programs\Python\Python312'
$PythonScripts = Join-Path $PythonRoot 'Scripts'
$WinGetLinks = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links'
$NpmPrefix = Join-Path $env:APPDATA 'npm'
$CodexHome = Join-Path $UserHome '.codex'
$Tmp = Join-Path $env:TEMP 'codex-bootstrap'

$NodeVersion = '24.18.0'
$PythonPackageId = 'Python.Python.3.12'
$GhPackageId = 'GitHub.cli'
$CodexPackage = '@openai/codex@latest'

$NodeUrl = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-x64.zip"

function Log {
  param([string]$Message)
  Write-Host "[bootstrap] $Message"
}

function Ensure-Dir {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
  }
}

function Download-File {
  param(
    [string]$Url,
    [string]$OutFile
  )
  Log "download: $Url"
  Ensure-Dir (Split-Path -Parent $OutFile)
  $ProgressPreference = 'SilentlyContinue'
  Invoke-WebRequest -Uri $Url -OutFile $OutFile -MaximumRedirection 5
}

function Add-PathForCurrentProcess {
  $parts = @(
    $NodeDir,
    $PythonRoot,
    $PythonScripts,
    $WinGetLinks,
    $NpmPrefix,
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\GitHub.cli_Microsoft.Winget.Source_8wekyb3d8bbwe\bin')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  $env:Path = (($parts + ($env:Path -split ';')) | Where-Object { $_ } | Select-Object -Unique) -join ';'
}

function Set-UserPath {
  $desired = @(
    $NodeDir,
    $PythonRoot,
    $PythonScripts,
    (Join-Path $PythonRoot 'Launcher'),
    $WinGetLinks,
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\GitHub.cli_Microsoft.Winget.Source_8wekyb3d8bbwe\bin'),
    $NpmPrefix,
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps')
  ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }

  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $currentParts = @()
  if ($current) {
    $currentParts = $current -split ';' | Where-Object { $_ }
  }

  $newPath = (($desired + $currentParts) | Where-Object { $_ } | Select-Object -Unique) -join ';'
  try {
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
  } catch {
    Log "warning: could not persist user PATH: $($_.Exception.Message)"
  }

  Add-PathForCurrentProcess
}

function Invoke-Npm {
  param([string[]]$Arguments)
  $npmCli = Join-Path $NodeDir 'node_modules\npm\bin\npm-cli.js'
  if (-not (Test-Path -LiteralPath $npmCli)) {
    throw "npm CLI not found at $npmCli"
  }
  & (Join-Path $NodeDir 'node.exe') $npmCli @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "npm failed with exit code $LASTEXITCODE"
  }
}

function Test-NodeInstallValid {
  $nodeExe = Join-Path $NodeDir 'node.exe'
  if (-not (Test-Path -LiteralPath $nodeExe)) { return $false }

  try {
    $nodeVersionOutput = & $nodeExe --version
    if ($LASTEXITCODE -ne 0 -or $nodeVersionOutput -ne "v$NodeVersion") {
      Log "Node version mismatch or invalid: $nodeVersionOutput"
      return $false
    }
    return $true
  } catch {
    Log "Node validation failed: $($_.Exception.Message)"
    return $false
  }
}

function Use-NewNodeFallbackDir {
  $stamp = Get-Date -Format 'yyyyMMddHHmmss'
  $script:NodeDir = Join-Path $Tools "node-$NodeVersion-$stamp"
  Log "using fallback Node path: $NodeDir"
}

function Test-CodexShimLooksValid {
  $codexJs = Join-Path $NpmPrefix 'node_modules\@openai\codex\bin\codex.js'
  $nativeExe = Get-CodexNativeExe
  if (-not (Test-Path -LiteralPath $codexJs)) { return $false }
  if (-not $nativeExe -or -not (Test-Path -LiteralPath $nativeExe)) { return $false }
  try {
    $bytes = [System.IO.File]::ReadAllBytes($codexJs)
    if ($bytes.Length -lt 20) { return $false }
    $prefixLength = [Math]::Min($bytes.Length, 80)
    $prefix = [System.Text.Encoding]::UTF8.GetString($bytes, 0, $prefixLength)
    return ($prefix -match '^#!/usr/bin/env node' -or $prefix -match 'node')
  } catch {
    return $false
  }
}

function Get-CodexNativeExe {
  $nativeExe = Join-Path $NpmPrefix 'node_modules\@openai\codex\node_modules\@openai\codex-win32-x64\vendor\x86_64-pc-windows-msvc\bin\codex.exe'
  if (Test-Path -LiteralPath $nativeExe) { return $nativeExe }
  return $null
}

function Write-CodexShims {
  $nativeExe = Get-CodexNativeExe
  if (-not $nativeExe) { throw 'Codex native executable not found for shim creation.' }

  $codexPs1 = Join-Path $NpmPrefix 'codex.ps1'
  $codexCmd = Join-Path $NpmPrefix 'codex.cmd'
  $codexSh = Join-Path $NpmPrefix 'codex'

  @"
#!/usr/bin/env pwsh
& '$nativeExe' @args
exit `$LASTEXITCODE
"@ | Set-Content -LiteralPath $codexPs1 -Encoding UTF8

  @"
@ECHO off
"$nativeExe" %*
"@ | Set-Content -LiteralPath $codexCmd -Encoding ASCII

  @"
#!/bin/sh
exec "$nativeExe" "$@"
"@ | Set-Content -LiteralPath $codexSh -Encoding ASCII
}

function Remove-BrokenCodexInstall {
  $paths = @(
    (Join-Path $NpmPrefix 'codex'),
    (Join-Path $NpmPrefix 'codex.cmd'),
    (Join-Path $NpmPrefix 'codex.ps1'),
    (Join-Path $NpmPrefix 'node_modules\@openai\codex')
  )

  foreach ($path in $paths) {
    if (Test-Path -LiteralPath $path) {
      Log "removing broken Codex path: $path"
      Remove-Item -LiteralPath $path -Recurse -Force
    }
  }
}

function Expand-TarballPackage {
  param(
    [string]$Tarball,
    [string]$Destination
  )
  $extract = Join-Path $Tmp ([IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFileNameWithoutExtension($Tarball)))
  if (Test-Path -LiteralPath $extract) {
    Remove-Item -LiteralPath $extract -Recurse -Force
  }
  Ensure-Dir $extract
  tar.exe -xf $Tarball -C $extract
  if ($LASTEXITCODE -ne 0) {
    throw "tar failed extracting $Tarball"
  }
  $packageDir = Join-Path $extract 'package'
  if (-not (Test-Path -LiteralPath $packageDir)) {
    throw "package directory not found in $Tarball"
  }
  Ensure-Dir $Destination
  Get-ChildItem -LiteralPath $packageDir -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
  }
}

function Install-CodexManually {
  Log 'installing Codex manually from npm tarballs'

  $registry = Invoke-RestMethod -Uri 'https://registry.npmjs.org/@openai/codex'
  $version = [string]$registry.'dist-tags'.latest
  if (-not $version) { throw 'could not resolve latest Codex version from npm registry' }
  Log "Codex version: $version"

  $mainTarball = Join-Path $Tmp "codex-$version.tgz"
  $nativeTarball = Join-Path $Tmp "codex-$version-win32-x64.tgz"
  Download-File "https://registry.npmjs.org/@openai/codex/-/codex-$version.tgz" $mainTarball
  Download-File "https://registry.npmjs.org/@openai/codex/-/codex-$version-win32-x64.tgz" $nativeTarball

  $codexDir = Join-Path $NpmPrefix 'node_modules\@openai\codex'
  $nativeDir = Join-Path $codexDir 'node_modules\@openai\codex-win32-x64'
  if (Test-Path -LiteralPath $codexDir) {
    Remove-Item -LiteralPath $codexDir -Recurse -Force
  }

  Expand-TarballPackage $mainTarball $codexDir
  Expand-TarballPackage $nativeTarball $nativeDir

  Write-CodexShims
}

function Ensure-Node {
  Log "1/6 Node.js"
  $nodeExe = Join-Path $NodeDir 'node.exe'
  if (-not (Test-NodeInstallValid)) {
    if (Test-Path -LiteralPath $NodeDir) {
      Log "removing invalid Node install: $NodeDir"
      try {
        Remove-Item -LiteralPath $NodeDir -Recurse -Force
      } catch {
        Log "warning: could not remove invalid Node install: $($_.Exception.Message)"
        Use-NewNodeFallbackDir
      }
    }
    $zip = Join-Path $Tmp 'node.zip'
    Download-File $NodeUrl $zip
    Ensure-Dir $Tools
    $extractDir = Join-Path $Tmp 'node-extract'
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force }
    Expand-Archive -LiteralPath $zip -DestinationPath $extractDir -Force
    $expanded = Join-Path $extractDir "node-v$NodeVersion-win-x64"
    if (Test-Path -LiteralPath $NodeDir) {
      try {
        Remove-Item -LiteralPath $NodeDir -Recurse -Force
      } catch {
        Log "warning: could not remove fallback Node path: $($_.Exception.Message)"
        Use-NewNodeFallbackDir
      }
    }
    Move-Item -LiteralPath $expanded -Destination $NodeDir
  }
  $nodeExe = Join-Path $NodeDir 'node.exe'
  Add-PathForCurrentProcess
  & $nodeExe --version
  if ($LASTEXITCODE -ne 0) { throw 'Node.js verification failed' }
}

function Ensure-Python {
  Log "2/6 Python"
  Add-PathForCurrentProcess
  $pythonExe = Join-Path $PythonRoot 'python.exe'
  if (-not (Test-Path -LiteralPath $pythonExe)) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
      throw 'winget.exe is required to install Python when it is missing.'
    }
    & winget.exe install --id $PythonPackageId --exact --scope user --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "Python install failed with exit code $LASTEXITCODE" }
  }
  Set-UserPath
  & $pythonExe --version
  if ($LASTEXITCODE -ne 0) { throw 'Python verification failed' }
  & (Join-Path $PythonScripts 'pip.exe') --version
  if ($LASTEXITCODE -ne 0) { throw 'pip verification failed' }
}

function Ensure-GitHubCli {
  Log "3/6 GitHub CLI"
  Add-PathForCurrentProcess
  if (-not (Get-Command gh.exe -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
      throw 'winget.exe is required to install GitHub CLI when it is missing.'
    }
    & winget.exe install --id $GhPackageId --exact --scope user --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "GitHub CLI install failed with exit code $LASTEXITCODE" }
  }
  Set-UserPath
  & gh.exe --version
  if ($LASTEXITCODE -ne 0) { throw 'GitHub CLI verification failed' }
}

function Ensure-CodexConfig {
  Log "4/6 Codex config"
  Ensure-Dir $CodexHome
  $config = Join-Path $CodexHome 'config.toml'
  if (-not (Test-Path -LiteralPath $config)) {
    @'
# Codex local defaults restored by bootstrap.
sandbox_mode = "workspace-write"
approval_policy = "on-request"
cli_auth_credentials_store = "file"

[windows]
sandbox = "unelevated"
'@ | Set-Content -LiteralPath $config -Encoding UTF8
    Log "created $config"
  } else {
    Log "config exists: $config"
  }
}

function Ensure-CodexCli {
  Log "5/6 Codex CLI"
  Ensure-Dir $NpmPrefix
  Add-PathForCurrentProcess

  $needsInstall = -not (Test-CodexShimLooksValid)
  if ($needsInstall) {
    Log 'existing Codex install is missing or corrupt'
    Remove-BrokenCodexInstall
  }

  if ($needsInstall) {
    Remove-BrokenCodexInstall
    Install-CodexManually
  } else {
    Write-CodexShims
  }

  Add-PathForCurrentProcess
  $codexCmd = Get-Command codex -ErrorAction SilentlyContinue
  if (-not $codexCmd) {
    throw 'codex command not found after install.'
  }
  & (Get-CodexNativeExe) --version
  if ($LASTEXITCODE -ne 0) {
    throw 'Codex CLI verification failed after install.'
  }
}

function Check-Auth {
  Log "6/6 auth status"
  try {
    & gh.exe auth status
  } catch {
    Log 'GitHub CLI is installed but not authenticated. Run: gh auth login --hostname github.com --git-protocol https --web'
  }

  if (-not $SkipCodexLogin) {
    $authFile = Join-Path $CodexHome 'auth.json'
    if (Test-Path -LiteralPath $authFile) {
      Log 'Codex auth cache exists.'
    } else {
      Log 'Codex is installed but not authenticated.'
      Log 'Run this after setup if browser login is blocked: codex login --device-auth'
    }
  }
}

Ensure-Dir $Tmp
Ensure-Node
Ensure-Python
Ensure-GitHubCli
Ensure-CodexConfig
Ensure-CodexCli
Check-Auth

Log 'DONE.'
Write-Host 'Next commands:'
Write-Host '  codex login --device-auth'
Write-Host '  gh auth login --hostname github.com --git-protocol https --web'
Write-Host '  codex'
