@echo off
setlocal EnableExtensions
REM ===========================================================================
REM Builds the offline Claude Code installer. RUN THIS ON A NETWORKED MACHINE.
REM
REM One file, no prerequisites beyond Windows PowerShell 5.1, which ships with
REM Windows - no Docker Desktop, no WSL, no Git Bash, no curl, no jq, no admin
REM rights. Nothing outside %TEMP% and the output directory is written.
REM
REM This file carries the PowerShell builder as a payload appended below the
REM "exit /b" at the end of the batch section. It is written to a temp folder,
REM run with -ExecutionPolicy Bypass (a per-process setting that needs no
REM elevation and changes nothing machine-wide, so the default RemoteSigned
REM policy cannot refuse it), and deleted again - on the failure path too.
REM
REM What the builder does mirrors the official install scripts up to the point
REM where they would run "claude install":
REM
REM   1. resolve the requested version -> downloads.claude.ai/claude-code-releases
REM   2. fetch manifest.json           -> SHA-256 for the platform
REM   3. download the release binary   -> .../<version>/<platform>/<binary>
REM   4. verify the SHA-256
REM
REM and then appends that binary to an installer, producing one self-extracting
REM file. "claude install" cannot be reused offline on either platform, since it
REM re-resolves the release channel over the network, so each installer writes
REM the resulting layout directly.
REM
REM The target platform decides the output:
REM
REM   linux-x64 / linux-arm64  -> claude-code-<version>-<platform>.sh
REM                               payload is a gzipped GNU tar, written by hand
REM                               so it carries POSIX modes and root ownership
REM                               that no Windows filesystem can represent;
REM                               installs to /usr/local
REM   win32-x64 / win32-arm64  -> claude-code-<version>-<platform>.bat
REM                               payload is a gzipped claude.exe; installs to
REM                               %USERPROFILE%\.local with no admin rights
REM
REM Usage:
REM   make-claude-installer.bat 2.1.263             pack that exact version
REM   make-claude-installer.bat stable              pack the current stable release
REM   make-claude-installer.bat latest              pack the current latest release
REM   make-claude-installer.bat                     same as "latest"
REM   make-claude-installer.bat 2.1.263 arm64       linux-arm64 (x64 is the default)
REM   make-claude-installer.bat latest win32-x64    Windows installer
REM   make-claude-installer.bat latest -OutDir D:\artifacts
REM
REM Output lands in the current directory unless -OutDir says otherwise. Upload
REM it to an artifact store the offline environment can reach, and have that
REM environment download and run it.
REM ===========================================================================

REM Passed to the child process rather than interpolated into the PowerShell
REM command line, so a path containing quotes or spaces cannot break it.
set "SELF=%~f0"

if /I "%~1"=="-h" goto :usage
if /I "%~1"=="-?" goto :usage
if /I "%~1"=="/?" goto :usage
if /I "%~1"=="--help" goto :usage

REM --- prerequisites ---------------------------------------------------------
where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: powershell not found on PATH. Windows PowerShell 5.1 is required.>&2
    exit /b 1
)

REM --- unpack the embedded builder -------------------------------------------
set "WORK_DIR=%TEMP%\claude-mk-%RANDOM%%RANDOM%"
mkdir "%WORK_DIR%" 2>nul
if not exist "%WORK_DIR%\" (
    echo ERROR: could not create temp folder %WORK_DIR%.>&2
    exit /b 1
)
set "PS1=%WORK_DIR%\make-claude-installer.ps1"

REM Everything after the marker is the PowerShell script. The marker is
REM assembled from two pieces here so that this line is not itself the first
REM match. CRs are stripped and the file is written without a BOM.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "$m='#__PS1' + '_PAYLOAD_BELOW__';" ^
    "$t=[IO.File]::ReadAllText($env:SELF);" ^
    "$i=$t.IndexOf($m);" ^
    "if($i -lt 0){ [Console]::Error.WriteLine('payload marker not found'); exit 1 };" ^
    "$s=$t.Substring($i+$m.Length).Replace([string][char]13,'').TrimStart([char]10);" ^
    "[IO.File]::WriteAllText($env:PS1,$s,(New-Object Text.UTF8Encoding($false)))"

if errorlevel 1 goto :unpackfailed
if not exist "%PS1%" goto :unpackfailed

REM --- build -----------------------------------------------------------------
REM %* forwards the arguments verbatim, so the builder's own parameters
REM (-OutDir and friends) work exactly as they do when it is run directly.
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" %*
set "RC=%ERRORLEVEL%"

rd /s /q "%WORK_DIR%" 2>nul
exit /b %RC%

:unpackfailed
rd /s /q "%WORK_DIR%" 2>nul
echo ERROR: could not unpack the builder from this file.>&2
exit /b 1

:usage
echo Usage: make-claude-installer.bat [stable^|latest^|VERSION] [PLATFORM] [-OutDir DIR]
echo.
echo   PLATFORM  linux-x64 ^(default^), linux-arm64, win32-x64, win32-arm64;
echo             x64 and arm64 are shorthand for the linux ones
echo.
echo   e.g. make-claude-installer.bat 2.1.263
echo        make-claude-installer.bat latest win32-x64
echo.
echo Needs only Windows PowerShell 5.1 - no Docker, no admin rights.
exit /b 0

#__PS1_PAYLOAD_BELOW__
#Requires -Version 5.1
<#
    make-claude-installer.ps1 - builds an offline Claude Code installer for
    Linux or Windows. RUN THIS ON A NETWORKED MACHINE.

    No Docker Desktop, no WSL, no Git Bash, no curl/jq and no administrator
    rights: Windows PowerShell 5.1, which ships with Windows, is the only
    prerequisite. Everything is written under %TEMP% and the output directory.

    It mirrors what the official install scripts do up to the point where they
    would run "claude install":

      1. resolve the requested version -> downloads.claude.ai/claude-code-releases
      2. fetch manifest.json           -> SHA-256 for the platform
      3. download the release binary   -> .../<version>/<platform>/<binary>
      4. verify the SHA-256

    and then appends that binary to an installer, producing one self-extracting
    file. "claude install" cannot be reused offline on either platform - it
    re-resolves the release channel over the network - so each installer writes
    the resulting layout directly.

    Two output shapes, picked from the target platform:

      linux-x64 / linux-arm64   -> claude-code-<version>-<platform>.sh
                                   payload: gzipped GNU tar (POSIX modes, root
                                   ownership), installs to /usr/local
      win32-x64 / win32-arm64   -> claude-code-<version>-<platform>.bat
                                   payload: gzipped claude.exe, installs to
                                   %USERPROFILE%\.local without admin rights

    For the Linux target the payload needs mode 0755, mode 0644 and root:root
    ownership, which a Windows filesystem cannot represent, so this script
    writes the tar headers itself and states those attributes as literals. The
    Windows target needs none of that, so its payload is a bare gzip stream and
    its installer unpacks it with GZipStream.

    Usage:
      powershell -NoProfile -ExecutionPolicy Bypass -File .\make-claude-installer.ps1 2.1.263
      powershell -NoProfile -ExecutionPolicy Bypass -File .\make-claude-installer.ps1 stable
      powershell -NoProfile -ExecutionPolicy Bypass -File .\make-claude-installer.ps1 latest
      powershell -NoProfile -ExecutionPolicy Bypass -File .\make-claude-installer.ps1 2.1.263 arm64
      powershell -NoProfile -ExecutionPolicy Bypass -File .\make-claude-installer.ps1 latest win32-x64

    -ExecutionPolicy Bypass applies to this one process only; it needs no
    elevation and changes nothing machine-wide.

    Output goes to -OutDir (default: the current directory). Upload it to an
    artifact store the offline environment can reach, and have that environment
    download and run it.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)] [string] $Target   = 'latest',
    [Parameter(Position = 1)] [string] $Platform = '',
    [string] $OutDir = '',
    [switch] $Help
)

$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'Continue'

$BaseUrl = 'https://downloads.claude.ai/claude-code-releases'

# Record size GNU tar pads its output to, and the block size within it.
$TarBlock  = 512
$TarRecord = 10240

# ---------------------------------------------------------------------------
# The installer. This text is written verbatim to the front of the output file,
# with the gzipped payload appended after it. Kept byte-for-byte identical to
# the heredoc in make-claude-installer.bat so both builders emit the same
# script.
# ---------------------------------------------------------------------------
$InstallerHeader = @'
#!/bin/bash
#
# Self-extracting offline installer for Claude Code.
#
# This file carries the Claude Code release binary appended to itself as a
# gzipped tar payload. Running it installs OS dependencies via apt, unpacks the
# binary, verifies its SHA-256 and puts it on PATH. Nothing is downloaded.
#
# It reproduces what "curl -fsSL https://claude.ai/install.sh | bash" ends up
# with. The upstream script downloads the binary and then runs "claude install",
# which re-resolves the release channel against downloads.claude.ai and so
# cannot run offline; this installer writes the same layout directly:
#
#   $PREFIX/share/claude/versions/$VERSION   the binary (mode 0755)
#   $PREFIX/bin/claude                       symlink -> the versioned binary
#
# Unlike upstream this installs system-wide (/usr/local by default) rather than
# into $HOME, so every user gets the same "claude" on PATH.

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
SKIP_APT=0
EXTRACT_ONLY=""

# Packages the bare ubuntu:24.04 image lacks. ca-certificates is not optional:
# without a CA bundle every HTTPS call Claude Code makes fails certificate
# verification. git is what Claude Code shells out to for version control.
APT_PACKAGES="${APT_PACKAGES:-ca-certificates git}"

usage() {
    cat <<'USAGE'
Self-extracting offline installer for Claude Code.

Usage: bash claude-code-<version>-linux-<arch>.sh [options]

  --prefix DIR    install root (default: /usr/local)
  --skip-apt      do not touch apt; assume ca-certificates and git are present
  --extract DIR   unpack the payload to DIR and exit, without installing
  -h, --help      this message
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --prefix) PREFIX="$2"; shift 2 ;;
        --prefix=*) PREFIX="${1#*=}"; shift ;;
        --skip-apt) SKIP_APT=1; shift ;;
        --extract) EXTRACT_ONLY="$2"; shift 2 ;;
        --extract=*) EXTRACT_ONLY="${1#*=}"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

SELF="$0"
[ -f "$SELF" ] || { echo "Cannot locate the installer file ($SELF)" >&2; exit 1; }

# First line of the appended payload. awk stops at the marker, so it never
# reads into the binary data below it.
PAYLOAD_LINE="$(awk '/^__CLAUDE_PAYLOAD_BELOW__$/ { print NR + 1; exit }' "$SELF")"
if [ -z "$PAYLOAD_LINE" ]; then
    echo "Payload marker not found - this file is truncated or corrupt." >&2
    exit 1
fi

unpack() {
    tail -n "+$PAYLOAD_LINE" "$SELF" | tar -xz -C "$1"
}

# --extract: hand over the raw payload for inspection, install nothing.
if [ -n "$EXTRACT_ONLY" ]; then
    mkdir -p "$EXTRACT_ONLY"
    unpack "$EXTRACT_ONLY"
    echo "Payload extracted to $EXTRACT_ONLY"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "Unpacking Claude Code..."
unpack "$WORK"

VERSION="$(cat "$WORK/VERSION")"
PLATFORM="$(cat "$WORK/PLATFORM")"
echo "Claude Code $VERSION ($PLATFORM) -> $PREFIX"

# Same SHA-256 check the upstream installer runs against manifest.json, here
# against the checksum recorded when this installer was built.
echo "Verifying checksum..."
( cd "$WORK" && sha256sum -c SHA256SUMS ) || {
    echo "Checksum verification failed - this installer is corrupt or truncated." >&2
    exit 1
}

if [ "$SKIP_APT" -eq 0 ] && [ -n "$APT_PACKAGES" ]; then
    if command -v apt-get >/dev/null 2>&1; then
        echo "Installing OS packages: $APT_PACKAGES"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y --no-install-recommends $APT_PACKAGES
        rm -rf /var/lib/apt/lists/*
    else
        echo "Warning: apt-get not found, skipping $APT_PACKAGES." >&2
        echo "         Claude Code needs a CA bundle for HTTPS to work." >&2
    fi
fi

install -d "$PREFIX/share/claude/versions"
install -m 0755 "$WORK/bin/claude" "$PREFIX/share/claude/versions/$VERSION"

install -d "$PREFIX/bin"
ln -sfn "$PREFIX/share/claude/versions/$VERSION" "$PREFIX/bin/claude"

# Claude Code writes lock files here; pre-creating it world-writable keeps the
# installation usable by every user, not just the one that ran this installer.
install -d -m 1777 "$PREFIX/share/claude/locks"

# Provenance: the upstream release manifest this binary came from.
install -m 0644 "$WORK/manifest.json" "$PREFIX/share/claude/manifest.json"

echo -n "Installed: "
"$PREFIX/bin/claude" --version

echo "Claude Code is at $PREFIX/bin/claude"

# The payload is appended below this marker. The exit keeps bash from ever
# parsing the binary data that follows.
exit 0
__CLAUDE_PAYLOAD_BELOW__
'@

# ---------------------------------------------------------------------------
# The Windows installer. Written verbatim to the front of a .bat output, with
# the gzipped claude.exe appended after it. @@VERSION@@, @@PLATFORM@@ and
# @@CHECKSUM@@ are substituted at build time.
#
# The batch half only unpacks the PowerShell half that follows it and runs that,
# reading just the first 64KB of the file, so the binary payload is never
# decoded as text.
# ---------------------------------------------------------------------------
$WindowsInstallerHeader = @'
@echo off
setlocal EnableExtensions
REM ===========================================================================
REM Self-extracting offline installer for Claude Code (Windows).
REM
REM   Version:  @@VERSION@@
REM   Platform: @@PLATFORM@@
REM   SHA-256:  @@CHECKSUM@@
REM
REM This file carries the Claude Code release binary appended to itself as a
REM gzip stream. Running it unpacks the binary, verifies that SHA-256 and puts
REM it on PATH. Nothing is downloaded and no administrator rights are needed.
REM
REM It reproduces what "irm https://claude.ai/install.ps1 | iex" ends up with.
REM That script downloads claude.exe and then runs "claude install", which
REM re-resolves the release channel against downloads.claude.ai and so cannot
REM run offline. This installer writes the layout directly instead:
REM
REM   <PREFIX>\share\claude\versions\@@VERSION@@.exe   the binary
REM   <PREFIX>\bin\claude.exe                          hard link to it
REM
REM PREFIX defaults to %USERPROFILE%\.local, mirroring the ~/.local layout the
REM Unix installer uses, and <PREFIX>\bin is added to the per-user PATH.
REM
REM Options:
REM   --prefix DIR    install root (default: %USERPROFILE%\.local)
REM   --extract DIR   unpack claude.exe to DIR and exit, installing nothing
REM   --no-path       do not touch PATH
REM   --force         re-extract even if this version is already installed
REM   -h, --help      usage
REM ===========================================================================

set "CLAUDE_INSTALLER_SELF=%~f0"

where powershell >nul 2>&1
if errorlevel 1 (
    echo ERROR: powershell not found on PATH. Windows PowerShell 5.1 is required.>&2
    exit /b 1
)

set "WORK_DIR=%TEMP%\claude-inst-%RANDOM%%RANDOM%"
mkdir "%WORK_DIR%" 2>nul
if not exist "%WORK_DIR%\" (
    echo ERROR: could not create temp folder %WORK_DIR%.>&2
    exit /b 1
)
set "CLAUDE_INSTALLER_PS1=%WORK_DIR%\install.ps1"

REM The PowerShell half sits between the two markers below. Each marker is
REM assembled from two pieces here so that these lines are not themselves the
REM first match.
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$ErrorActionPreference='Stop';" ^
    "$a='#__PS1' + '_INSTALLER_BELOW__';" ^
    "$b='#__CLAUDE' + '_PAYLOAD_BELOW__';" ^
    "$f=[IO.File]::OpenRead($env:CLAUDE_INSTALLER_SELF);" ^
    "$u=New-Object byte[] 65536;" ^
    "$n=$f.Read($u,0,65536);" ^
    "$f.Close();" ^
    "$t=[Text.Encoding]::ASCII.GetString($u,0,$n);" ^
    "$i=$t.IndexOf($a);" ^
    "$j=$t.IndexOf($b);" ^
    "if($i -lt 0 -or $j -le $i){ [Console]::Error.WriteLine('installer markers not found - this file is truncated or corrupt'); exit 1 };" ^
    "$s=$t.Substring($i+$a.Length,$j-$i-$a.Length).Replace([string][char]13,'').TrimStart([char]10);" ^
    "[IO.File]::WriteAllText($env:CLAUDE_INSTALLER_PS1,$s,(New-Object Text.UTF8Encoding($false)))"

if errorlevel 1 goto :unpackfailed
if not exist "%CLAUDE_INSTALLER_PS1%" goto :unpackfailed

powershell -NoProfile -ExecutionPolicy Bypass -File "%CLAUDE_INSTALLER_PS1%" %*
set "RC=%ERRORLEVEL%"

rd /s /q "%WORK_DIR%" 2>nul
exit /b %RC%

:unpackfailed
rd /s /q "%WORK_DIR%" 2>nul
echo ERROR: could not unpack the installer from this file.>&2
exit /b 1

#__PS1_INSTALLER_BELOW__
# Offline installer for Claude Code @@VERSION@@ (@@PLATFORM@@).
#
# Unpacked from the .bat that carries it, which passes that file's own path in
# CLAUDE_INSTALLER_SELF. This script finds the gzip payload appended to it,
# verifies the SHA-256 recorded at build time, and writes the install layout.

$ErrorActionPreference = 'Stop'

$Version  = '@@VERSION@@'
$Platform = '@@PLATFORM@@'
$Checksum = '@@CHECKSUM@@'

function Die([string] $Message) {
    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

function Show-Usage {
    Write-Host "Self-extracting offline installer for Claude Code $Version ($Platform)."
    Write-Host ''
    Write-Host 'Usage: claude-code-<version>-<platform>.bat [options]'
    Write-Host ''
    Write-Host '  --prefix DIR    install root (default: %USERPROFILE%\.local)'
    Write-Host '  --extract DIR   unpack claude.exe to DIR and exit, installing nothing'
    Write-Host '  --no-path       do not add <prefix>\bin to the per-user PATH'
    Write-Host '  --force         re-extract even if this version is already installed'
    Write-Host '  -h, --help      this message'
}

$Prefix    = Join-Path $env:USERPROFILE '.local'
$ExtractTo = ''
$NoPath    = $false
$Force     = $false

$i = 0
while ($i -lt $args.Count) {
    $a = [string] $args[$i]
    if ($a -eq '--prefix' -or $a -eq '--extract') {
        if ($i + 1 -ge $args.Count) { Die "$a needs a directory" }
        if ($a -eq '--prefix') { $Prefix = [string] $args[$i + 1] } else { $ExtractTo = [string] $args[$i + 1] }
        $i += 2
        continue
    }
    switch ($a) {
        '--no-path' { $NoPath = $true }
        '--force'   { $Force  = $true }
        '-h'        { Show-Usage; exit 0 }
        '--help'    { Show-Usage; exit 0 }
        default {
            if ($a -like '--prefix=*')      { $Prefix    = $a.Substring(9) }
            elseif ($a -like '--extract=*') { $ExtractTo = $a.Substring(10) }
            else {
                [Console]::Error.WriteLine("Unknown option: $a")
                Show-Usage
                exit 1
            }
        }
    }
    $i++
}

try {
    $Self = $env:CLAUDE_INSTALLER_SELF
    if (-not $Self) { $Self = $PSCommandPath }
    if (-not $Self -or -not (Test-Path -LiteralPath $Self)) { Die 'cannot locate the installer file' }

    $versionsDir = Join-Path $Prefix 'share\claude\versions'
    $binDir      = Join-Path $Prefix 'bin'
    $target      = Join-Path $versionsDir "$Version.exe"
    $launcher    = Join-Path $binDir 'claude.exe'

    # Settled before unpacking: re-running this installer where the version is
    # already in place should not spend a 200MB decompression to find that out.
    $present = $false
    if (-not $ExtractTo -and -not $Force -and (Test-Path -LiteralPath $target)) {
        if ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant() -eq $Checksum) {
            $present = $true
        }
    }

    if (-not $present) {
        # Staging goes in the temp folder the .bat made, so its cleanup covers it.
        if ($PSCommandPath) { $work = Split-Path -Parent $PSCommandPath } else { $work = $env:TEMP }
        $staged = Join-Path $work 'claude.exe'

        # Byte offset of the gzip stream: right after the marker line, whose line
        # ending is skipped explicitly rather than assumed.
        $marker = '#__CLAUDE' + '_PAYLOAD_BELOW__'
        $fs = [IO.File]::OpenRead($Self)
        try {
            $head = New-Object byte[] 65536
            $n    = $fs.Read($head, 0, $head.Length)
            $text = [Text.Encoding]::ASCII.GetString($head, 0, $n)
            $idx  = $text.IndexOf($marker)
            if ($idx -lt 0) { Die 'payload marker not found - this file is truncated or corrupt' }
            $off = $idx + $marker.Length
            while ($off -lt $n -and ($head[$off] -eq 13 -or $head[$off] -eq 10)) { $off++ }

            Write-Host 'Unpacking Claude Code...'
            $fs.Position = $off
            $gz  = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
            $out = [IO.File]::Create($staged)
            $sha = [Security.Cryptography.SHA256]::Create()
            try {
                $buf      = New-Object byte[] 1048576
                $done     = 0L
                $lastTick = 0
                while (($k = $gz.Read($buf, 0, $buf.Length)) -gt 0) {
                    $out.Write($buf, 0, $k)
                    [void] $sha.TransformBlock($buf, 0, $k, $null, 0)
                    $done += $k
                    if (([Environment]::TickCount - $lastTick) -gt 250) {
                        $lastTick = [Environment]::TickCount
                        Write-Progress -Activity 'Unpacking Claude Code' -Status ('{0:N1} MB' -f ($done / 1MB))
                    }
                }
                [void] $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
                $actual = (($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
            } finally {
                $out.Dispose()
                $gz.Dispose()
                $sha.Dispose()
            }
            Write-Progress -Activity 'Unpacking Claude Code' -Completed
        } finally {
            $fs.Dispose()
        }

        # The same check the upstream installer runs against manifest.json, here
        # against the checksum recorded when this installer was built.
        Write-Host 'Verifying checksum...'
        if ($actual -ne $Checksum) {
            Die "checksum verification failed - this installer is corrupt or truncated (got $actual)"
        }
    }

    if ($ExtractTo) {
        New-Item -ItemType Directory -Force -Path $ExtractTo | Out-Null
        Move-Item -LiteralPath $staged -Destination (Join-Path $ExtractTo 'claude.exe') -Force
        Write-Host "claude.exe extracted to $ExtractTo"
        exit 0
    }

    Write-Host "Claude Code $Version ($Platform) -> $Prefix"

    New-Item -ItemType Directory -Force -Path $versionsDir | Out-Null
    New-Item -ItemType Directory -Force -Path $binDir | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $Prefix 'share\claude\locks') | Out-Null

    if ($present) {
        Write-Host "$Version is already installed; refreshing the launcher only (--force to re-extract)."
    } else {
        try { Move-Item -LiteralPath $staged -Destination $target -Force }
        catch { Die "cannot write $target - close any running claude and try again" }
    }

    # Windows has no unprivileged symlink, so the launcher is a hard link: one
    # copy of a 200MB binary, under a real .exe name every shell can run. A hard
    # link needs the same volume and NTFS, hence the copy fallback.
    if (Test-Path -LiteralPath $launcher) {
        try { Remove-Item -LiteralPath $launcher -Force }
        catch { Die "cannot replace $launcher - close any running claude and try again" }
    }
    $linked = $false
    try {
        New-Item -ItemType HardLink -Path $launcher -Value $target -ErrorAction Stop | Out-Null
        $linked = $true
    } catch { }
    if (-not $linked) {
        Copy-Item -LiteralPath $target -Destination $launcher -Force
        Write-Host 'Note: a hard link was not possible here, so the launcher is a full copy.'
    }

    if ($NoPath) {
        Write-Host "PATH left alone. Add this yourself: $binDir"
    } else {
        $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
        if ($null -eq $userPath) { $userPath = '' }
        $parts = @($userPath -split ';' | Where-Object { $_ -ne '' })
        if (@($parts | Where-Object { $_.TrimEnd('\') -ieq $binDir.TrimEnd('\') }).Count -gt 0) {
            Write-Host "PATH already contains $binDir"
        } else {
            # SetEnvironmentVariable, not setx: setx silently truncates a PATH
            # longer than 1024 characters. This writes HKCU, so no elevation.
            [Environment]::SetEnvironmentVariable('Path', (($parts + $binDir) -join ';'), 'User')
            Write-Host "Added to your user PATH: $binDir"
            Write-Host 'Open a new terminal for that to take effect.'
        }
    }

    # A broken install fails loudly here rather than the first time it is used.
    $env:DISABLE_AUTOUPDATER = '1'
    Write-Host -NoNewline 'Installed: '
    & $launcher --version
    if ($LASTEXITCODE -ne 0) { Die "the installed binary did not run cleanly (exit $LASTEXITCODE)" }

    Write-Host "Claude Code is at $launcher"
    Write-Host ''
    Write-Host 'On a host that cannot reach claude.ai, also set DISABLE_AUTOUPDATER=1 so that'
    Write-Host 'Claude Code stops retrying updates against an unreachable host on every start.'
} catch {
    Die $_.Exception.Message
}
#__CLAUDE_PAYLOAD_BELOW__
'@

function Die([string] $Message) {
    [Console]::Error.WriteLine("ERROR: $Message")
    exit 1
}

function Show-Usage {
    Write-Host 'Usage: make-claude-installer.ps1 [stable|latest|VERSION] [PLATFORM] [-OutDir DIR]'
    Write-Host ''
    Write-Host '  PLATFORM  linux-x64 (default), linux-arm64, win32-x64, win32-arm64;'
    Write-Host '            x64 and arm64 are accepted as shorthand for the linux ones'
    Write-Host ''
    Write-Host '  e.g. make-claude-installer.ps1 2.1.263'
    Write-Host '       make-claude-installer.ps1 latest win32-x64'
}

# --- HTTP -------------------------------------------------------------------
# HttpWebRequest rather than Invoke-WebRequest: it streams to disk instead of
# buffering a 215MB response in memory, and it honours the system proxy.

function Save-Url {
    param(
        [Parameter(Mandatory)] [string] $Url,
        [Parameter(Mandatory)] [string] $Path,
        [string] $Label
    )

    $req = [Net.HttpWebRequest] [Net.WebRequest]::Create($Url)
    $req.UserAgent        = 'make-claude-installer.ps1'
    $req.Timeout          = 60000
    $req.ReadWriteTimeout = 300000
    if ($req.Proxy) {
        try { $req.Proxy.Credentials = [Net.CredentialCache]::DefaultCredentials } catch { }
    }

    $resp = $req.GetResponse()
    try {
        $total = $resp.ContentLength
        $in    = $resp.GetResponseStream()
        $out   = [IO.File]::Create($Path)
        try {
            $buf      = New-Object byte[] 1048576
            $done     = 0L
            $lastTick = 0
            while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                $out.Write($buf, 0, $n)
                $done += $n
                if ($Label -and $total -gt 0 -and ([Environment]::TickCount - $lastTick) -gt 250) {
                    $lastTick = [Environment]::TickCount
                    Write-Progress -Activity $Label `
                        -Status ('{0:N1} / {1:N1} MB' -f ($done / 1MB), ($total / 1MB)) `
                        -PercentComplete ([int](100 * $done / $total))
                }
            }
        } finally {
            $out.Dispose()
            $in.Dispose()
        }
        if ($Label) { Write-Progress -Activity $Label -Completed }
        if ($total -gt 0 -and $done -ne $total) {
            throw "Short read from $Url ($done of $total bytes)"
        }
    } finally {
        $resp.Close()
    }
}

# --- tar --------------------------------------------------------------------
# GNU tar's header layout, written by hand. This is what replaces the
# container: mode, uid/gid and mtime are stated here rather than read off a
# filesystem that has no notion of them.

function Set-TarField {
    param([byte[]] $Buffer, [int] $Offset, [string] $Value)
    $bytes = [Text.Encoding]::ASCII.GetBytes($Value)
    [Array]::Copy($bytes, 0, $Buffer, $Offset, $bytes.Length)
}

function New-TarHeader {
    param(
        [Parameter(Mandatory)] [string] $Name,
        [long]   $Size = 0,
        [string] $Mode = '0000644',
        [string] $Type = '0'
    )

    if ([Text.Encoding]::ASCII.GetByteCount($Name) -gt 99) { throw "Name too long for a tar header: $Name" }

    # Unset bytes stay zero, which is also how each field is terminated.
    $h = New-Object byte[] 512
    Set-TarField $h 0   $Name
    Set-TarField $h 100 $Mode
    Set-TarField $h 108 '0000000'                                       # uid 0
    Set-TarField $h 116 '0000000'                                       # gid 0
    Set-TarField $h 124 ([Convert]::ToString($Size, 8).PadLeft(11, '0'))
    Set-TarField $h 136 '00000000000'                                   # mtime 0, for reproducibility
    Set-TarField $h 148 '        '                                      # checksum counts itself as spaces
    Set-TarField $h 156 $Type
    Set-TarField $h 257 'ustar  '                                       # GNU magic + version
    Set-TarField $h 265 'root'
    Set-TarField $h 297 'root'

    $sum = 0
    foreach ($b in $h) { $sum += $b }
    Set-TarField $h 148 ([Convert]::ToString($sum, 8).PadLeft(6, '0'))
    $h[154] = 0
    $h[155] = 32

    , $h
}

function Write-TarBytes {
    param($Stream, [byte[]] $Bytes, [int] $Count = -1)
    if ($Count -lt 0) { $Count = $Bytes.Length }
    $Stream.Write($Bytes, 0, $Count)
    $script:TarWritten += $Count
}

function Write-TarPadding {
    param($Stream, [long] $Length)
    $pad = ($script:TarBlock - ($Length % $script:TarBlock)) % $script:TarBlock
    if ($pad -gt 0) { Write-TarBytes $Stream (New-Object byte[] $pad) }
}

function Write-TarDirectory {
    param($Stream, [string] $Name, [string] $Mode = '0000755')
    Write-TarBytes $Stream (New-TarHeader -Name $Name -Mode $Mode -Type '5')
}

function Write-TarFile {
    param($Stream, [string] $Name, [byte[]] $Content, [string] $Mode = '0000644')
    Write-TarBytes $Stream (New-TarHeader -Name $Name -Size $Content.Length -Mode $Mode)
    Write-TarBytes $Stream $Content
    Write-TarPadding $Stream $Content.Length
}

function Write-TarFileFromDisk {
    param($Stream, [string] $Name, [string] $Path, [string] $Mode = '0000644', [string] $Label)

    $size = (Get-Item -LiteralPath $Path).Length
    Write-TarBytes $Stream (New-TarHeader -Name $Name -Size $size -Mode $Mode)

    $in = [IO.File]::OpenRead($Path)
    try {
        $buf      = New-Object byte[] 1048576
        $done     = 0L
        $lastTick = 0
        while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
            Write-TarBytes $Stream $buf $n
            $done += $n
            if ($Label -and ([Environment]::TickCount - $lastTick) -gt 250) {
                $lastTick = [Environment]::TickCount
                Write-Progress -Activity $Label `
                    -Status ('{0:N1} / {1:N1} MB' -f ($done / 1MB), ($size / 1MB)) `
                    -PercentComplete ([int](100 * $done / $size))
            }
        }
    } finally {
        $in.Dispose()
    }
    if ($Label) { Write-Progress -Activity $Label -Completed }
    Write-TarPadding $Stream $size
}

function Write-TarEnd {
    param($Stream)
    Write-TarBytes $Stream (New-Object byte[] 1024)                 # two zero blocks
    $rem = ($script:TarRecord - ($script:TarWritten % $script:TarRecord)) % $script:TarRecord
    if ($rem -gt 0) { Write-TarBytes $Stream (New-Object byte[] $rem) }
}

# --- self-test --------------------------------------------------------------
# Walks the finished installer the way the installer itself does - find the
# marker, gunzip what follows, unpack the tar - and checks the binary against
# the checksum recorded inside the payload.

function Read-Exact {
    param($Stream, [byte[]] $Buffer, [int] $Count)
    $got = 0
    while ($got -lt $Count) {
        $n = $Stream.Read($Buffer, $got, $Count - $got)
        if ($n -le 0) { break }
        $got += $n
    }
    $got
}

function Test-Installer {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Version,
        [Parameter(Mandatory)] [string] $Platform,
        [Parameter(Mandatory)] [string] $Checksum
    )

    $marker = "`n__CLAUDE_PAYLOAD_BELOW__`n"
    $fs = [IO.File]::OpenRead($Path)
    try {
        $head = New-Object byte[] 16384
        $n    = Read-Exact $fs $head 16384
        $text = [Text.Encoding]::ASCII.GetString($head, 0, $n)
        $i    = $text.IndexOf($marker)
        if ($i -lt 0) { throw 'payload marker not found in the generated installer' }

        # What the installer's own awk computes: the first line of the payload.
        $payloadOffset = $i + $marker.Length
        $payloadLine   = ([regex]::Matches($text.Substring(0, $payloadOffset), "`n")).Count + 1

        $fs.Position = $payloadOffset
        $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
        try {
            $seen   = @{}
            $binSha = $null
            $hdr    = New-Object byte[] 512
            $buf    = New-Object byte[] 1048576

            while ($true) {
                if ((Read-Exact $gz $hdr 512) -ne 512) { throw 'payload truncated inside a tar header' }
                $empty = $true
                foreach ($b in $hdr) { if ($b -ne 0) { $empty = $false; break } }
                if ($empty) { break }

                $name = [Text.Encoding]::ASCII.GetString($hdr, 0, 100).TrimEnd([char]0)
                $size = [Convert]::ToInt64(([Text.Encoding]::ASCII.GetString($hdr, 124, 12).Trim([char]0, ' ')), 8)
                $type = [char] $hdr[156]

                if ($type -eq '0' -and $name -eq './bin/claude') {
                    $sha  = [Security.Cryptography.SHA256]::Create()
                    $left = $size
                    while ($left -gt 0) {
                        $want = [Math]::Min([long] $buf.Length, $left)
                        $got  = Read-Exact $gz $buf ([int] $want)
                        if ($got -ne $want) { throw 'payload truncated inside the binary' }
                        [void] $sha.TransformBlock($buf, 0, $got, $null, 0)
                        $left -= $got
                    }
                    [void] $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
                    $binSha = (($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
                    $sha.Dispose()
                } elseif ($type -eq '0' -and $size -gt 0 -and $size -le 65536) {
                    $small = New-Object byte[] ([int] $size)
                    if ((Read-Exact $gz $small ([int] $size)) -ne $size) { throw "payload truncated inside $name" }
                    $seen[$name] = [Text.Encoding]::ASCII.GetString($small)
                } else {
                    $left = $size
                    while ($left -gt 0) {
                        $want = [Math]::Min([long] $buf.Length, $left)
                        $got  = Read-Exact $gz $buf ([int] $want)
                        if ($got -ne $want) { throw "payload truncated inside $name" }
                        $left -= $got
                    }
                }

                $pad = ($script:TarBlock - ($size % $script:TarBlock)) % $script:TarBlock
                if ($pad -gt 0) { [void] (Read-Exact $gz $buf ([int] $pad)) }
            }

            if (-not $binSha)                             { throw './bin/claude missing from the payload' }
            if ($binSha -ne $Checksum)                    { throw "unpacked binary is $binSha, expected $Checksum" }
            if ($seen['./VERSION'].Trim()  -ne $Version)  { throw 'VERSION in the payload does not match' }
            if ($seen['./PLATFORM'].Trim() -ne $Platform) { throw 'PLATFORM in the payload does not match' }
            if ($seen['./SHA256SUMS'] -notmatch [regex]::Escape("$Checksum  bin/claude")) {
                throw 'SHA256SUMS in the payload does not match'
            }
        } finally {
            $gz.Dispose()
        }
    } finally {
        $fs.Dispose()
    }

    $payloadLine
}

function Test-WindowsInstaller {
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Checksum
    )

    # The same two steps the Windows installer takes: find the marker in the head
    # of the file, then gunzip everything after it.
    $marker = '#__CLAUDE' + '_PAYLOAD_BELOW__'
    $fs = [IO.File]::OpenRead($Path)
    try {
        $head = New-Object byte[] 65536
        $n    = Read-Exact $fs $head 65536
        $text = [Text.Encoding]::ASCII.GetString($head, 0, $n)

        # Both markers have to be inside that first 64KB, or the batch half
        # cannot find the PowerShell half at run time.
        if ($text.IndexOf('#__PS1' + '_INSTALLER_BELOW__') -lt 0) {
            throw 'installer marker not found in the generated installer'
        }
        $idx = $text.IndexOf($marker)
        if ($idx -lt 0) { throw 'payload marker not found in the generated installer' }

        $off = $idx + $marker.Length
        while ($off -lt $n -and ($head[$off] -eq 13 -or $head[$off] -eq 10)) { $off++ }

        $fs.Position = $off
        $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionMode]::Decompress)
        try {
            $sha  = [Security.Cryptography.SHA256]::Create()
            $buf  = New-Object byte[] 1048576
            $size = 0L
            while (($k = $gz.Read($buf, 0, $buf.Length)) -gt 0) {
                [void] $sha.TransformBlock($buf, 0, $k, $null, 0)
                $size += $k
            }
            [void] $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
            $actual = (($sha.Hash | ForEach-Object { $_.ToString('x2') }) -join '')
            $sha.Dispose()
            if ($size -le 0)           { throw 'payload unpacked to nothing' }
            if ($actual -ne $Checksum) { throw "unpacked binary is $actual, expected $Checksum" }
        } finally {
            $gz.Dispose()
        }
    } finally {
        $fs.Dispose()
    }
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------
if ($Help -or @('-h', '--help', '/?', '-?') -contains $Target) { Show-Usage; exit 0 }

if (-not $Platform) { $Platform = $env:CLAUDE_ARCH }
if (-not $Platform) { $Platform = 'x64' }
if (-not $OutDir)   { $OutDir = (Get-Location).ProviderPath }

# Bare architectures keep meaning linux, which is what they meant when this
# builder only had one target.
switch ($Platform.ToLowerInvariant()) {
    'x64'   { $Platform = 'linux-x64' }
    'arm64' { $Platform = 'linux-arm64' }
    default { $Platform = $Platform.ToLowerInvariant() }
}

$KnownPlatforms = @('linux-x64', 'linux-arm64', 'win32-x64', 'win32-arm64')

# Anything but the two channel names must look like X.Y.Z, so a typo fails here
# rather than 200MB into a download.
if (@('stable', 'latest') -notcontains $Target -and $Target -notmatch '^[0-9]+\.[0-9]+\.[0-9]+') {
    Die "'$Target' is not a version. Use stable, latest, or X.Y.Z (e.g. 2.1.263)."
}
if ($KnownPlatforms -notcontains $Platform) {
    Die "PLATFORM must be one of x64, arm64, $($KnownPlatforms -join ', ') - got '$Platform'."
}
if (-not (Test-Path -LiteralPath $OutDir -PathType Container)) {
    Die "Output directory does not exist: $OutDir"
}
$OutDir = (Resolve-Path -LiteralPath $OutDir).ProviderPath

# TLS 1.0 is still the default on some Windows PowerShell installs and
# downloads.claude.ai will not negotiate it.
try {
    [Net.ServicePointManager]::SecurityProtocol =
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch { }

$WindowsTarget = $Platform.StartsWith('win32')
$work          = $null

try {
    $work = Join-Path $env:TEMP ('claude-pkg-' + [Guid]::NewGuid().ToString('N').Substring(0, 12))
    New-Item -ItemType Directory -Path $work | Out-Null

    # 1. resolve the requested version. "stable" and "latest" are pointer files
    #    holding a version number; an explicit version is used as-is.
    if ($Target -match '^[0-9]') {
        $Version = $Target
    } else {
        $pointer = Join-Path $work 'channel'
        try { Save-Url -Url "$BaseUrl/$Target" -Path $pointer }
        catch { throw "Failed to resolve the $Target channel: $($_.Exception.Message)" }
        $Version = ([IO.File]::ReadAllText($pointer)).Trim()
    }
    if ($Version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+') {
        throw "Failed to resolve a valid version (got: $Version)"
    }
    Write-Host "Version:  $Version"
    Write-Host "Platform: $Platform"

    # 2. manifest -> expected checksum. A version that does not exist fails here.
    $manifestPath = Join-Path $work 'manifest.json'
    try { Save-Url -Url "$BaseUrl/$Version/manifest.json" -Path $manifestPath }
    catch { throw "No manifest for version $Version - does that release exist? ($($_.Exception.Message))" }

    $manifest = [IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
    $entry    = $manifest.platforms.PSObject.Properties[$Platform]
    if (-not $entry) { throw "Platform $Platform not found in manifest" }
    $Checksum = [string] $entry.Value.checksum
    if ($Checksum -notmatch '^[a-f0-9]{64}$') { throw "Platform $Platform has no usable checksum in the manifest" }

    # 3. the release binary. The manifest names it, which is how the win32
    #    platforms get claude.exe rather than claude.
    $BinaryName = [string] $entry.Value.binary
    if (-not $BinaryName) { $BinaryName = if ($WindowsTarget) { 'claude.exe' } else { 'claude' } }

    Write-Host "Downloading $BinaryName..."
    $binPath = Join-Path $work $BinaryName
    Save-Url -Url "$BaseUrl/$Version/$Platform/$BinaryName" -Path $binPath -Label "Downloading $BinaryName"

    # 4. verify before packaging anything
    $actual = (Get-FileHash -LiteralPath $binPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Checksum) {
        throw "Checksum mismatch for the downloaded binary. expected $Checksum, got $actual"
    }
    Write-Host "$BinaryName`: OK ($Checksum)"

    $ascii   = [Text.Encoding]::ASCII
    $OutFile = "claude-code-$Version-$Platform" + $(if ($WindowsTarget) { '.bat' } else { '.sh' })
    $OutPath = Join-Path $OutDir $OutFile
    Write-Host "Creating $OutFile..."

    if ($WindowsTarget) {
        # 5/6. Windows installer = batch+PowerShell header, then the gzipped
        #      claude.exe. No tar: there are no POSIX modes to carry, and the
        #      installer unpacks the stream with GZipStream.
        $headerText = $WindowsInstallerHeader.
            Replace('@@VERSION@@',  $Version).
            Replace('@@PLATFORM@@', $Platform).
            Replace('@@CHECKSUM@@', $Checksum)
        # CRLF throughout: cmd.exe needs it for the batch half, and the
        # installer's own extractor strips the CRs back out of the PowerShell
        # half. The marker line's CRLF is what the payload offset skips.
        $headerText  = ($headerText -replace "`r`n", "`n" -replace "`r", "`n").TrimEnd("`n") + "`n"
        $headerBytes = $ascii.GetBytes(($headerText -replace "`n", "`r`n"))

        $fs = [IO.File]::Create($OutPath)
        try {
            $fs.Write($headerBytes, 0, $headerBytes.Length)
            $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionLevel]::Optimal, $true)
            try {
                $in = [IO.File]::OpenRead($binPath)
                try {
                    $size     = (Get-Item -LiteralPath $binPath).Length
                    $buf      = New-Object byte[] 1048576
                    $done     = 0L
                    $lastTick = 0
                    while (($n = $in.Read($buf, 0, $buf.Length)) -gt 0) {
                        $gz.Write($buf, 0, $n)
                        $done += $n
                        if (([Environment]::TickCount - $lastTick) -gt 250) {
                            $lastTick = [Environment]::TickCount
                            Write-Progress -Activity 'Compressing payload' `
                                -Status ('{0:N1} / {1:N1} MB' -f ($done / 1MB), ($size / 1MB)) `
                                -PercentComplete ([int](100 * $done / $size))
                        }
                    }
                } finally {
                    $in.Dispose()
                }
                Write-Progress -Activity 'Compressing payload' -Completed
            } finally {
                $gz.Dispose()
            }
        } finally {
            $fs.Dispose()
        }
    } else {
        # 5. metadata the installer reads back out of its own payload. LF endings
        #    and no BOM - these are read by bash and by sha256sum.
        $verB = $ascii.GetBytes("$Version`n")
        $plfB = $ascii.GetBytes("$Platform`n")
        $sumB = $ascii.GetBytes("$Checksum  bin/claude`n")
        $manB = [IO.File]::ReadAllBytes($manifestPath)

        # 6. installer = header + gzipped payload, written in one pass. Entry
        #    order, modes and the zero mtime match "tar --sort=name --mtime=@0
        #    --owner=0 --group=0", so the payload is reproducible across rebuilds.
        $headerText  = $InstallerHeader.Replace("`r`n", "`n").Replace("`r", "`n").TrimEnd("`n") + "`n"
        $headerBytes = $ascii.GetBytes($headerText)

        $script:TarWritten = 0L
        $fs = [IO.File]::Create($OutPath)
        try {
            $fs.Write($headerBytes, 0, $headerBytes.Length)
            $gz = New-Object IO.Compression.GZipStream($fs, [IO.Compression.CompressionLevel]::Optimal, $true)
            try {
                Write-TarDirectory    $gz './'
                Write-TarFile         $gz './PLATFORM'      $plfB
                Write-TarFile         $gz './SHA256SUMS'    $sumB
                Write-TarFile         $gz './VERSION'       $verB
                Write-TarDirectory    $gz './bin/'
                Write-TarFileFromDisk $gz './bin/claude'    $binPath '0000755' 'Compressing payload'
                Write-TarFile         $gz './manifest.json' $manB
                Write-TarEnd          $gz
            } finally {
                $gz.Dispose()
            }
        } finally {
            $fs.Dispose()
        }
    }

    # 7. self-test before handing it over: the payload must unpack and match its
    #    own checksum through the installer's own extraction path.
    if ($WindowsTarget) {
        Test-WindowsInstaller -Path $OutPath -Checksum $Checksum
        Write-Host 'Self-test: payload unpacks and verifies.'
    } else {
        $payloadLine = Test-Installer -Path $OutPath -Version $Version -Platform $Platform -Checksum $Checksum
        Write-Host "Self-test: payload unpacks and verifies (payload starts at line $payloadLine)."
    }

    $sum   = (Get-FileHash -LiteralPath $OutPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $bytes = (Get-Item -LiteralPath $OutPath).Length
    Write-Host ''
    Write-Host "$sum  $OutFile"
    Write-Host ('{0}  {1:N1} MB' -f $OutPath, ($bytes / 1MB))
    Write-Host ''
    Write-Host "Upload $OutFile to an artifact store the offline environment can reach."
    if ($WindowsTarget) {
        Write-Host "Install it with:  $OutFile [--prefix DIR] [--no-path]"
    } else {
        Write-Host "Install it with:  bash $OutFile [--prefix DIR] [--skip-apt]"
    }
    Write-Host 'Pin what runs with the SHA-256 above.'
} catch {
    [Console]::Error.WriteLine("ERROR: $($_.Exception.Message)")
    exit 1
} finally {
    if ($work -and (Test-Path -LiteralPath $work)) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
