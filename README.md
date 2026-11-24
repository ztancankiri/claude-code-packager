<div align="center">

# 📦 Claude Code Packager

### Ship Claude Code to machines that can't reach the internet — in one file.

Build a **single self-extracting installer** carrying the official Claude Code
release binary, for hosts that cannot reach `claude.ai` / `downloads.claude.ai`.

<p>
  <img alt="Linux x64 | arm64" src="https://img.shields.io/badge/Linux-x64%20%7C%20arm64-FCC624?style=for-the-badge&logo=linux&logoColor=black">
  <img alt="Windows x64 | arm64" src="https://img.shields.io/badge/Windows-x64%20%7C%20arm64-0078D6?style=for-the-badge&logo=windows&logoColor=white">
  <img alt="PowerShell 5.1" src="https://img.shields.io/badge/PowerShell-5.1-5391FE?style=for-the-badge&logo=powershell&logoColor=white">
</p>
<p>
  <img alt="No admin rights" src="https://img.shields.io/badge/admin%20rights-not%20needed-2ea44f?style=flat-square">
  <img alt="No Docker" src="https://img.shields.io/badge/Docker-not%20needed-2ea44f?style=flat-square&logo=docker&logoColor=white">
  <img alt="Reproducible" src="https://img.shields.io/badge/builds-reproducible-2ea44f?style=flat-square">
  <img alt="SHA-256 verified" src="https://img.shields.io/badge/SHA--256-verified-2ea44f?style=flat-square">
  <a href="LICENSE"><img alt="License: PolyForm Noncommercial 1.0.0" src="https://img.shields.io/badge/license-PolyForm%20NC%201.0.0-blue?style=flat-square"></a>
</p>

[✨ Features](#-features) •
[🚀 Quick start](#-quick-start) •
[🐧 Linux](#-installing-on-linux) •
[🪟 Windows](#-installing-on-windows) •
[⚙️ How it works](#%EF%B8%8F-how-it-works) •
[✅ Verified](#-verified) •
[📜 License](#-license)

</div>

---

## ✨ Features

|     |     |
| --- | --- |
| 🧳 **One file in, one file out** | `make-claude-installer.bat` is the whole builder. It produces one installer that carries the binary inside it. |
| 🪶 **Zero prerequisites** | Needs only **Windows PowerShell 5.1**, which ships with Windows. No Docker, WSL, Git Bash, `curl`, `jq` or Node.js. |
| 🔓 **No admin rights** | Not to build, and not to install on Windows either. Nothing outside `%TEMP%` and the output folder is written. |
| 🔐 **Checksum verified twice** | The binary is checked against upstream's `manifest.json` at build time and again at install time. |
| ♻️ **Byte-for-byte reproducible** | Rebuilding the same version and platform gives an identical file, so a published checksum can be re-derived later. |
| 🧪 **Self-tested** | The builder unpacks its own output and checks the SHA-256 before handing it over. |
| 🐳 **Container friendly** | The Linux installer is designed to be downloaded, run and deleted in a single `RUN` step. |

### 🎯 Targets

| Platform | Output | Installs to |
| --- | --- | --- |
| 🐧 `linux-x64`, `linux-arm64` | `claude-code-<version>-<platform>.sh` | `/usr/local` |
| 🪟 `win32-x64`, `win32-arm64` | `claude-code-<version>-<platform>.bat` | `%USERPROFILE%\.local` |

> [!NOTE]
> 32-bit Windows is not offered because upstream publishes no 32-bit build.

---

## 🚀 Quick start

On a **networked Windows machine**:

```bat
make-claude-installer.bat                     :: latest, linux-x64 (default)
make-claude-installer.bat latest win32-x64    :: Windows installer
```

Copy the resulting file to the offline host and run it:

```bash
bash claude-code-2.1.263-linux-x64.sh         # Linux
```

```bat
claude-code-2.1.263-win32-x64.bat             :: Windows
```

That's it. 🎉

---

## 🛠️ Building

```bat
make-claude-installer.bat 2.1.263             :: a specific version, linux-x64
make-claude-installer.bat stable              :: current stable
make-claude-installer.bat latest              :: current latest (default)
make-claude-installer.bat                     :: same as "latest"

make-claude-installer.bat 2.1.263 arm64       :: linux-arm64
make-claude-installer.bat latest win32-x64    :: Windows installer
make-claude-installer.bat latest win32-arm64
make-claude-installer.bat latest -OutDir D:\artifacts
```

- 🐧 `x64` and `arm64` on their own mean the **Linux** platforms, which is what
  they meant when this builder had only one target.
- 📁 Output goes to the current directory: **~91MB** for Linux, **~94MB** for
  Windows.
- 🔁 Arguments are forwarded verbatim to the PowerShell builder, and its exit
  code is the one the batch file returns.

> [!TIP]
> The batch file runs its embedded builder with `-ExecutionPolicy Bypass`. That
> applies to that one process only: it needs no elevation and changes nothing
> machine-wide, which is what makes this runnable on a locked-down workstation
> where the default `RemoteSigned` policy would refuse a downloaded `.ps1`.

---

## 🐧 Installing on Linux

```bash
bash claude-code-2.1.263-linux-x64.sh                    # into /usr/local
bash claude-code-2.1.263-linux-x64.sh --skip-apt         # deps already present
bash claude-code-2.1.263-linux-x64.sh --prefix /opt/cc
bash claude-code-2.1.263-linux-x64.sh --extract /tmp/x   # inspect, install nothing
```

**What it does, in order:**

1. 📤 locates its own appended payload and unpacks it to a temp dir
2. 🔐 verifies the binary's SHA-256, aborting if it fails
3. 📥 `apt-get update` + `apt-get install -y --no-install-recommends ca-certificates git`
4. 📂 installs the binary mode 0755 to `$PREFIX/share/claude/versions/$VERSION`
5. 🔗 symlinks `$PREFIX/bin/claude` to it, creates `$PREFIX/share/claude/locks` mode 1777
6. ✅ runs `claude --version`, so a broken install fails loudly at install time

### 🐳 Putting it in a container image

- **Run it as `bash <installer>`.** A downloaded file has no executable bit, and
  `chmod`ing a 92MB file forces a copy-up into another layer.
- **Download, run and delete it in one `RUN`.** The installer then reaches no
  layer at all. `COPY`ing or `ADD`ing it instead costs an extra ~92MB that a
  later `rm` cannot reclaim, because a copied file lives in its own layer -
  measured on `ubuntu:24.04`, **560MB versus 749MB** for the same image.
- **`curl` and `ca-certificates` must exist before the fetch.** A bare
  `ubuntu:24.04` has neither, so an HTTPS download cannot verify anything.
- **Verify what you execute** with the SHA-256 the build prints, on top of the
  one the installer checks on its own payload.

> [!IMPORTANT]
> On an offline host, set **`DISABLE_AUTOUPDATER=1`**. Otherwise Claude Code
> retries updates against an unreachable host on every start.
> `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` suppresses the remaining
> non-essential outbound calls.

---

## 🪟 Installing on Windows

```bat
claude-code-2.1.263-win32-x64.bat                    :: into %USERPROFILE%\.local
claude-code-2.1.263-win32-x64.bat --prefix D:\cc
claude-code-2.1.263-win32-x64.bat --no-path          :: leave PATH alone
claude-code-2.1.263-win32-x64.bat --force            :: re-extract over itself
claude-code-2.1.263-win32-x64.bat --extract D:\x     :: unpack only, install nothing
```

**No administrator rights needed.** What it does, in order:

1. ⚡ checks whether that exact version is already at the target path, by
   SHA-256, and if so skips the unpack entirely
2. 📤 finds its own gzip payload, decompresses `claude.exe` and hashes it on the way
3. 🔐 verifies that SHA-256 against the one recorded at build time, aborting if
   it fails
4. 📂 writes `<PREFIX>\share\claude\versions\<version>.exe`, and creates
   `<PREFIX>\share\claude\locks`
5. 🔗 **hard-links** `<PREFIX>\bin\claude.exe` to it
6. 🛣️ adds `<PREFIX>\bin` to the per-user PATH if it is missing, unless `--no-path`
7. ✅ runs `claude --version`, so a broken install fails loudly at install time

<details>
<summary>🔗 <b>Why a hard link and not a symlink?</b></summary>

<br>

Windows needs administrator rights (or Developer Mode) to create a symlink; a
hard link needs neither. So the launcher is a real `claude.exe` that works from
cmd, PowerShell and Git Bash alike, while the ~210MB binary exists on disk only
once. Hard links require the same volume and NTFS, so if one cannot be made the
installer falls back to a full copy and says so.

</details>

<details>
<summary>🛣️ <b>How is PATH updated?</b></summary>

<br>

The per-user PATH is written with
`[Environment]::SetEnvironmentVariable(..., 'User')`, not `setx`, because `setx`
silently truncates a PATH longer than 1024 characters. It writes `HKCU`, so no
elevation, and it affects only your account. Open a new terminal for it to take
effect, or pass `--no-path` and add the directory yourself.

</details>

> [!IMPORTANT]
> On an offline host, set **`DISABLE_AUTOUPDATER=1`** as a user environment
> variable. The installer sets it for its own verification step only.

---

## ⚙️ How it works

### 📜 The upstream installers vs. this one

Unix (`curl -fsSL https://claude.ai/install.sh | bash`) and Windows
(`irm https://claude.ai/install.ps1 | iex`) both do the same steps:

| # | Upstream step | Here |
| :-: | --- | :-: |
| 1 | detect the platform → `linux-x64`, `win32-arm64`, … | ✅ reproduced |
| 2 | `GET downloads.claude.ai/claude-code-releases/latest` → version | ✅ reproduced |
| 3 | `GET .../<version>/manifest.json` → SHA-256 + size per platform | ✅ reproduced |
| 4 | download `.../<version>/<platform>/<binary>` (~210MB) and verify SHA-256 | ✅ reproduced |
| 5 | run `<binary> install` to lay out the versioned binary and a launcher | 🔁 replaced |

**Step 5 cannot be reused offline on either platform.** `claude install`
re-resolves the release channel over the network and fails without it:

```
Failed to fetch version from https://downloads.claude.ai/claude-code-releases/latest
after 3 attempt(s): getaddrinfo ETIMEOUT downloads.claude.ai
```

Its only options are `--force` and `--help`, so there is no way to point it at a
binary already on disk. Each installer therefore writes the layout directly.
Deliberate differences:

- 🐧 **Linux** installs to `/usr/local` rather than `$HOME`, so `claude` is on
  `PATH` for every user, not just the one that ran it.
- 🪟 **Windows** installs to `%USERPROFILE%\.local`, mirroring the `~/.local`
  layout the Unix side uses, and links rather than symlinks. This layout is
  **modeled on** the Unix one: `claude install` cannot be run offline to observe
  what it produces natively on Windows, so what is verified is that the install
  works and runs, not that it is identical to what the official Windows
  installer would have written.

### 📦 How the installers carry a binary

- 🐧 **Linux:** the payload is a gzipped tar concatenated onto the script after an
  `exit 0` and a `__CLAUDE_PAYLOAD_BELOW__` marker, so bash never parses the
  binary data. The installer finds the offset with `awk` (which stops at the
  marker) and pipes `tail -n +N "$0"` into `tar -xz`.
- 🪟 **Windows:** the gzip stream is concatenated onto the batch file after its
  `exit /b`, so cmd.exe never reads that far. The PowerShell half sits between
  two marker lines near the top; the batch half reads only the **first 64KB** of
  the file as text to find it, so the binary is never decoded as text, and the
  payload offset is taken from the marker's own line ending rather than assumed.

### 🐳 Life without a container

<details>
<summary>An earlier version ran inside an <code>ubuntu:24.04</code> container. Here's what replaced it.</summary>

<br>

Four of the five things that container did have direct replacements in the box:

| Container tool | Replaced by |
| --- | --- |
| `curl` | `HttpWebRequest`, which streams the ~215MB binary straight to disk instead of buffering it in memory like `Invoke-WebRequest`, and picks up the system proxy |
| `jq` | `ConvertFrom-Json` |
| `sha256sum` | `Get-FileHash` |
| `gzip` | `GZipStream` |
| `tar` | **writing the tar stream directly** ⬇️ |

**The fifth is replaced by writing the tar stream directly.** That is the one
job Docker was really doing, and it only matters for the Linux target: that
payload needs mode `0755` on the binary, `0644` on the metadata and `root:root`
ownership, none of which an NTFS directory can express, so `tar.exe` cannot be
pointed at a folder and asked to produce them. Instead the builder emits the
512-byte GNU tar headers itself and states mode, uid, gid and mtime as literals.
Zero mtimes and a fixed entry order are what make the result reproducible, and
they are also why the payload comes out identical to the container's.

The Windows payload needs none of that - there are no POSIX modes to carry - so
it is a bare gzip stream of `claude.exe` with no tar around it.

</details>

### ✏️ Editing the builder

<details>
<summary>The PowerShell builder lives inside the <code>.bat</code>, below a marker line. Here's how to get it out and back in.</summary>

<br>

The batch file carries the PowerShell builder as a payload after its own
`exit /b`, writes it to a temp folder, runs it, and deletes it afterwards - on
the failure path too.

**Extract** it as a file you can read or edit:

```powershell
$mark = '#__PS1' + '_PAYLOAD_BELOW__'
$t = [IO.File]::ReadAllText('.\make-claude-installer.bat')
$s = $t.Substring($t.IndexOf($mark) + $mark.Length).Replace("`r", '').TrimStart("`n")
[IO.File]::WriteAllText('.\make-claude-installer.ps1', $s, (New-Object Text.UTF8Encoding($false)))
```

That `.ps1` also runs on its own, and builds exactly the same thing:

```bat
powershell -NoProfile -ExecutionPolicy Bypass -File .\make-claude-installer.ps1 latest win32-x64
```

**Fold changes back in** by replacing everything below the marker. The whole
file is written as ASCII with CRLF endings, which cmd.exe needs for the batch
half and the extractor strips back out of the payload:

```powershell
$bat  = '.\make-claude-installer.bat'
$mark = '#__PS1' + '_PAYLOAD_BELOW__'
$head = [IO.File]::ReadAllText($bat)
$head = $head.Substring(0, $head.IndexOf($mark) + $mark.Length)
$all  = ($head + "`n" + [IO.File]::ReadAllText('.\make-claude-installer.ps1')) `
        -replace "`r`n", "`n" -replace "`n", "`r`n"
[IO.File]::WriteAllText($bat, $all, (New-Object Text.UTF8Encoding($false)))
```

Repacking an unchanged `.ps1` rewrites the same bytes, so this round-trips
losslessly.

</details>

---

## 📝 Notes

- 🧬 **The Linux binary needs only glibc** (`libc`, `libm`, `libdl`, `librt`,
  `libpthread`), all present in `ubuntu:24.04`. No Node.js, no npm.
- 🔒 **`ca-certificates` is not optional** on Linux at runtime either - without a
  CA bundle every HTTPS call Claude Code makes fails certificate verification.
  The installer adds it, along with `git`, unless `--skip-apt` is passed.
- 👥 **Non-root use** works on Linux; the install is system-wide and the `locks`
  directory is mode 1777.
- ⬆️ **Updating** means re-running the builder with the new version and
  reinstalling. There is no in-place upgrade path offline. On Windows, a second
  version lands beside the first under `versions\`, and the launcher points at
  whichever was installed last.

---

## ✅ Verified

<details>
<summary>🛠️ <b>The builder</b> — Windows 10, PowerShell 5.1, no Docker, no elevation</summary>

<br>

- `make-claude-installer.bat 2.1.263` and
  `make-claude-installer.bat 2.1.263 win32-x64` → binary checksum matches
  upstream `manifest.json` in both cases; ~30s end to end each
- `linux-arm64` and `win32-arm64` build against their own manifest checksums,
  and the `win32-arm64` payload extracts and verifies
- rebuilding linux-x64 produces an identical file
  (`8329f08b9a3a40cb8f5edb171684816df46779aa108adb706bdb92c88b4d8ddf`), as does
  building it via `latest`, through the `.bat` or through the `.ps1` directly -
  the wrapper changes nothing about the output, and adding the Windows target
  did not change the Linux one
- with no arguments it defaults to `latest linux-x64` and writes to the current
  directory; `-OutDir` works with a path containing a space
- `/?` prints usage without unpacking anything; a bad version or platform is
  rejected before any download; a release that does not exist fails on the
  manifest fetch with a readable message
- the builder's exit code is passed back through the batch file, and the temp
  folder is gone after every run, successful or not
- the `.bat` is pure ASCII with CRLF throughout and exactly one marker
  occurrence, so cmd.exe parses the batch half and the extractor finds the
  payload; extracting and repacking an unchanged payload is byte-idempotent

</details>

<details>
<summary>🪟 <b>The Windows installer</b> — installed into a throwaway <code>--prefix</code></summary>

<br>

- `claude-code-2.1.263-win32-x64.bat` (93.7MB) installs and
  `claude --version` reports `2.1.263 (Claude Code)`
- layout is `share\claude\versions\2.1.263.exe`, `bin\claude.exe` and
  `share\claude\locks`
- the launcher is a genuine hard link, not a copy: `LinkType` is `HardLink` and
  `fsutil hardlink list` reports both paths, so the 218MB binary is on disk once
- re-running detects the installed version and skips the unpack - 1s instead of
  ~15s - and reports that it refreshed only the launcher; `--force` re-extracts
- PATH, tested against a backup and then restored byte-for-byte: the per-user
  PATH gains `<prefix>\bin` on first install, a second run says it is already
  there, and `--no-path` leaves the user PATH untouched
- `--extract` writes a `claude.exe` whose SHA-256 matches the manifest, for both
  `win32-x64` and `win32-arm64`
- `--help` exits 0; an unknown option prints usage and exits 1
- a `.bat` truncated to half its length fails the checksum and installs nothing

The `win32-arm64` binary itself was not executed - this is an x64 host - so for
that platform only the build, unpack and checksum paths are covered.

</details>

<details>
<summary>🐧 <b>The Linux installer</b> — <code>ubuntu:24.04</code>, version 2.1.263, linux-x64</summary>

<br>

These results come from a **container-built reference installer** for the same
version, made while this project still had a Docker-based builder (since
removed). They carry over because this builder's payload is **byte-identical**
to the container's - both tars are 215,674,880 bytes with no difference under
`cmp`, so modes, `root:root` ownership, zero mtimes, entry order and the
10240-byte record padding all match - behind a byte-identical installer script,
with the payload starting at line 132 in both. Only the gzip stream around the
payload differs, because GNU `gzip` and .NET's `GZipStream` are different
deflate implementations, which is also why the two `.sh` files have different
SHA-256s while installing identical bits.

- installs and runs in an image built from an HTTP-served copy of the installer;
  `claude --version` reports `2.1.263 (Claude Code)`
- binary is mode 0755, `locks` is 1777, symlink resolves
- TLS verified end to end (`git ls-remote https://github.com/...`)
- `claude` runs as root and as a non-root user
- standalone with `--network none`: default prefix, `--prefix`, `--skip-apt`,
  `--extract` and `--help` all work
- a truncated installer aborts instead of installing a corrupt binary

The `.sh` this builder produces also unpacks through its own code path under
`bash` (`--extract`) with the installer's `sha256sum -c SHA256SUMS` step
passing, and a truncated copy aborts in `gzip`/`tar`. It was **not** run inside
`ubuntu:24.04` - that would have meant using the Docker this builder exists to
avoid.

</details>

---

## 📜 License

Copyright © 2026 [ztancankiri](https://github.com/ztancankiri). Licensed under the
[PolyForm Noncommercial License 1.0.0](LICENSE).

| | |
| :-: | --- |
| ✅ | **Use** it freely for any noncommercial purpose |
| ✅ | **Modify** it and share your changes |
| 📣 | **Credit is required:** any copy or derivative work must keep the `Required Notice:` lines in [LICENSE](LICENSE), crediting ztancankiri as the original author and linking to <https://github.com/ztancankiri/claude-code-packager> |
| 🚫 | **No commercial use**, including selling it or using it to make money |

> [!NOTE]
> This is an independent community project. It is not affiliated with or
> endorsed by Anthropic. It repackages the official Claude Code release binary,
> which remains subject to Anthropic's own terms.

<div align="center">

<br>

Made with ❤️ by [ztancankiri](https://github.com/ztancankiri) •
⭐ Star the repo if it saved you a headache!

</div>
