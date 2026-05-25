# Installation and Build Guide

This guide covers local build, test, and install steps for the unofficial MiniMax Hub Linux package. Proprietary MiniMax payloads are not committed to this repository and are not redistributed by this project. You need a local MiniMax Hub installation as the source for application resources.

Run all commands from the repository root.

## Build Prerequisites

Required for all build hosts:

| Tool | Used by |
| --- | --- |
| `bash` | All scripts |
| `curl` or `wget` | Runtime downloads |
| `tar` | Archive extraction and tree copies |
| `unzip` | Electron zip extraction |
| `python3` or `python` | Manifest reads and updates |
| `sha256sum`, `sha512sum`, or Python hashing | Runtime checksum reports |
| `npm` | Native module rebuilds |
| `node-gyp` build dependencies | `better-sqlite3` rebuilds when source build is needed |

Debian and Ubuntu package build tools:

```bash
sudo apt update
sudo apt install bash curl tar unzip python3 npm dpkg-dev desktop-file-utils
```

Fedora, RHEL, and Rocky package build tools:

```bash
sudo dnf install bash curl tar unzip python3 npm rpm-build rpm-build-libs rpm desktop-file-utils
```

openSUSE package build tools:

```bash
sudo zypper install bash curl tar unzip python3 npm rpm-build rpm desktop-file-utils
```

Native module builds may also need compiler, Python, make, and SQLite development packages from your distro. Keep those build-only packages on the build host. The final package carries the staged runtime payload.

## Shell Syntax Check

Before building, check every maintained shell entry point:

```bash
bash -n build.sh build-rpm.sh scripts/*.sh tests/*.sh
```

## Source Payload Extraction

Stage application resources from a local MiniMax Hub install root:

```bash
bash scripts/extract-windows-payload.sh --source "/path/to/MiniMax Hub"
```

If `package-manifest.json` has a reachable `sourceInstallPath`, you can use the default:

```bash
bash scripts/extract-windows-payload.sh
```

The extractor writes `.cache/windows-payload/payload`, plus `inventory.txt`, `sha256.txt`, and `report.txt`. It copies app resources such as `resources/app.asar`, gateway code, MCP tools, OpenCode config, plugins, icons, assets, and selected metadata. It filters Windows runtime artifacts during staging.

Inspect the staged source payload:

```bash
bash scripts/inspect-payload.sh
```

Use a non-failing report during diagnosis:

```bash
bash scripts/inspect-payload.sh --no-fail
```

## Linux Runtime Fetching

Stage Linux replacements into `linux-build/opt/minimax-hub`.

Electron requires a version unless the manifest already records one:

```bash
bash scripts/fetch-electron-linux.sh --version VERSION
```

Use a local Electron archive instead of downloading:

```bash
bash scripts/fetch-electron-linux.sh --version VERSION --archive /path/to/electron-vVERSION-linux-x64.zip
```

OpenCode defaults to `openCodeVersion` from `package-manifest.json`, currently `1.15.10`:

```bash
bash scripts/fetch-opencode-linux.sh
```

Node defaults to `runtimePlaceholders.nodeVersion`, then `22.16.0`:

```bash
bash scripts/fetch-node-linux.sh
```

FFmpeg defaults to the BtbN latest Linux x64 GPL archive and can also stage explicit binaries:

```bash
bash scripts/fetch-ffmpeg-linux.sh
bash scripts/fetch-ffmpeg-linux.sh --ffmpeg /path/to/ffmpeg --ffprobe /path/to/ffprobe --version local
```

All runtime fetchers accept these common options:

```bash
--cache-dir DIR
--payload-dir DIR
--archive FILE
--url URL
--dry-run
--help
```

The fetchers verify upstream checksums where available or record a local SHA256 when upstream checksums are not available.

## Native Module Rebuild

Rebuild Linux-native gateway modules after Node is staged and after source extraction has provided `resources/gateway/node_modules`:

```bash
bash scripts/rebuild-native-modules.sh
```

Useful variants:

```bash
bash scripts/rebuild-native-modules.sh --dry-run
bash scripts/rebuild-native-modules.sh --offline --npm-cache .cache/runtimes/npm
bash scripts/rebuild-native-modules.sh --electron-version VERSION --electron-abi ABI
```

The script removes forbidden Windows native artifacts from gateway `node_modules`, installs the Linux `sharp`, `@img`, and `@node-rs/xxhash` packages, rebuilds or installs `better-sqlite3` from staged package information, verifies that native modules can be required by the packaged Node binary, and writes reports under `.cache/runtimes`.

## Payload Assembly

Assemble the final Linux payload from staged source resources and Linux replacements:

```bash
bash scripts/assemble-linux-payload.sh
```

The assembler preserves an existing Linux `resources/gateway/node_modules` tree, copies app resources, copies Linux runtimes, runs normalization by default, and verifies final prerequisites.

You can pass explicit runtime overrides:

```bash
bash scripts/assemble-linux-payload.sh \
  --electron /path/to/electron \
  --chrome-sandbox /path/to/chrome-sandbox \
  --node-dir /path/to/node-linux-x64 \
  --opencode /path/to/opencode \
  --ffmpeg /path/to/ffmpeg \
  --ffprobe /path/to/ffprobe
```

Run normalization directly when needed:

```bash
bash scripts/normalize-payload.sh
```

Normalization fixes executable bits, removes CRLF line endings from packaged text files, checks for forbidden Windows artifacts, and writes `.cache/assembly/inventory.txt`, `.cache/assembly/sha256.txt`, and `.cache/assembly/normalization-report.txt`.

## Test Matrix

Run the checks that match your stage of work:

| Stage | Command |
| --- | --- |
| Shell syntax | `bash -n build.sh build-rpm.sh scripts/*.sh tests/*.sh` |
| Payload structure | `bash tests/verify-payload.sh` |
| Runtime versions | `bash scripts/smoke-runtime.sh` |
| OpenCode binary | `bash tests/smoke-opencode.sh` |
| Native modules | `bash tests/smoke-native-modules.sh` |
| MCP tools | `bash tests/smoke-mcp.sh` |
| Gateway service | `bash tests/smoke-gateway.sh` |
| Desktop entry | `bash tests/verify-desktop.sh` |
| Debian artifact | `bash tests/verify-deb.sh output/minimax-hub_0.1.44_amd64.deb` |
| RPM artifact | `bash tests/verify-rpm.sh output/minimax-hub-0.1.44-1.x86_64.rpm` |

`tests/smoke-gateway.sh` starts the packaged gateway with bundled Node and probes `http://127.0.0.1:8001/health` and `/`. `tests/smoke-mcp.sh` starts MCP tools with bundled Node and accepts either a clean help exit or a timeout after startup. `tests/verify-desktop.sh` requires protocol handler metadata in the desktop file.

## Build Packages

Debian package:

```bash
bash build.sh
```

Expected artifact:

```text
output/minimax-hub_0.1.44_amd64.deb
```

RPM package:

```bash
bash build-rpm.sh
```

Expected artifact:

```text
output/minimax-hub-0.1.44-1.x86_64.rpm
```

`build.sh` validates Debian metadata, normalizes the package tree, checks required payload files, rejects forbidden Windows artifacts, builds with `dpkg-deb --root-owner-group`, and runs `tests/verify-deb.sh`.

`build-rpm.sh` validates the payload before invoking RPM tools, requires `rpmbuild`, builds from `rpm/minimax-hub.spec`, copies the first `minimax-hub-0.1.44-1*.x86_64.rpm` match to `output/minimax-hub-0.1.44-1.x86_64.rpm`, and runs `tests/verify-rpm.sh` when `rpm` is installed.

## Install Packages

Debian or Ubuntu:

```bash
sudo apt install ./output/minimax-hub_0.1.44_amd64.deb
```

Alternative Debian flow:

```bash
sudo dpkg -i output/minimax-hub_0.1.44_amd64.deb
sudo apt -f install
```

Fedora, RHEL, or Rocky:

```bash
sudo dnf install ./output/minimax-hub-0.1.44-1.x86_64.rpm
```

openSUSE:

```bash
sudo zypper install ./output/minimax-hub-0.1.44-1.x86_64.rpm
```

Run after install:

```bash
minimax-hub
```

## Troubleshooting

### Missing Payload

Error examples mention `resources/app.asar`, `resources/gateway/dist/main.js`, `resources/mcp-tools/dist/main.js`, or `resources/opencode/config`.

Run:

```bash
bash scripts/extract-windows-payload.sh --source "/path/to/MiniMax Hub"
bash scripts/inspect-payload.sh --no-fail
```

Make sure `--source` points at the installed app root that contains `resources/app.asar`. Do not point it at the repository or at a package output directory.

### Missing Electron Version

`fetch-electron-linux.sh` fails when no Electron version is passed and no manifest placeholder is set.

Run:

```bash
bash scripts/fetch-electron-linux.sh --version VERSION
```

Use the Electron version required by the staged MiniMax Hub app. The script downloads `electron-vVERSION-linux-x64.zip` by default and verifies it with Electron `SHASUMS512.txt`.

### OpenCode Binary Failure

If `tests/smoke-opencode.sh` or `scripts/smoke-runtime.sh` reports a missing or non-executable OpenCode binary, run:

```bash
bash scripts/fetch-opencode-linux.sh
bash tests/smoke-opencode.sh
```

Expected path: `linux-build/opt/minimax-hub/resources/opencode/opencode`.

### FFmpeg Or FFprobe Failure

If FFmpeg or FFprobe is missing or cannot run, stage both binaries again:

```bash
bash scripts/fetch-ffmpeg-linux.sh
bash scripts/smoke-runtime.sh
```

For offline or curated binaries:

```bash
bash scripts/fetch-ffmpeg-linux.sh --ffmpeg /path/to/ffmpeg --ffprobe /path/to/ffprobe --version local
```

Expected paths are `resources/ffmpeg/ffmpeg` and `resources/ffmpeg/ffprobe` under the payload root.

### Node, Gateway, Or MCP Failure

If bundled Node cannot execute:

```bash
bash scripts/fetch-node-linux.sh
bash scripts/smoke-runtime.sh
```

If gateway or MCP code is missing, extraction or assembly is incomplete:

```bash
bash scripts/inspect-payload.sh --no-fail
bash scripts/assemble-linux-payload.sh
```

If `tests/smoke-gateway.sh` cannot reach port `8001`, check whether another process is using that port, then rerun the smoke test after stopping the other process.

### Native Module Failure

If `better-sqlite3`, `sharp`, or `@node-rs/xxhash` cannot be required with packaged Node, rerun:

```bash
bash scripts/rebuild-native-modules.sh
bash tests/smoke-native-modules.sh
```

Make sure `npm` can reach the registry unless you use `--offline` with a populated npm cache. If `better-sqlite3` needs Electron ABI coverage, pass `--electron-version` and `--electron-abi`, then verify the generated report before assembly.

### Desktop Integration Failure

If desktop validation fails, run:

```bash
bash tests/verify-desktop.sh
```

Install `desktop-file-utils` to use `desktop-file-validate`. The package maintainer scripts call `update-desktop-database` when available. The desktop file must launch `minimax-hub`, include `%u` or `%U` for protocol URLs, include `x-scheme-handler/` entries, and include the `X-MiniMaxHub-Protocol-Schemes` discovery marker.

### chrome-sandbox Failure

Electron may require `chrome-sandbox` to be owned by root with mode `4755`. The build normalizes this in `linux-build`, and package scripts try to fix it after install.

Check an installed package with:

```bash
ls -l /opt/minimax-hub/chrome-sandbox
```

A correct mode begins with `-rws`. If local policy blocks setuid sandboxing, document that policy in release notes and test Electron startup in that environment before shipping.

### RPM Toolchain Failure

If `build-rpm.sh` reports `Required command not found: rpmbuild`, install RPM build tools or run on a Fedora, RHEL, Rocky, or compatible build host:

```bash
sudo dnf install rpm-build rpm
```

If `rpm` is missing, `build-rpm.sh` can still build after `rpmbuild` succeeds, but it skips `tests/verify-rpm.sh`. Install `rpm` before release verification.

### Forbidden Windows Artifacts

Packaging fails if `.exe`, `.dll`, `.bat`, `.cmd`, or Windows-specific directories such as `win32`, `windows`, or `msvc` remain in the payload.

Run:

```bash
bash scripts/inspect-payload.sh --no-fail
bash scripts/normalize-payload.sh
bash tests/verify-payload.sh
```

Do not bypass this check. Linux packages must contain Linux runtimes and Linux-native modules.
