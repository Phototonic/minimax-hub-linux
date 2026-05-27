# MiniMax Hub Linux

Unofficial community Linux packaging for MiniMax Hub.

This repository builds local Linux packages from a MiniMax Hub installation that you provide. Proprietary MiniMax payloads are not committed to this repository and are not redistributed by this project. The build keeps source application resources in ignored local caches, then stages Linux runtime replacements before creating native `.deb` and `.rpm` artifacts.

## What This Builds

Current package metadata:

| Item | Value |
| --- | --- |
| Package name | `minimax-hub` |
| Version source | `VERSION` |
| Current version | `0.1.45` |
| Debian artifact | `output/minimax-hub_0.1.45_amd64.deb` |
| RPM artifact | `output/minimax-hub-0.1.45-1.x86_64.rpm` |
| Install prefix | `/opt/minimax-hub` |
| Launcher | `/usr/bin/minimax-hub` |
| Desktop file | `/usr/share/applications/minimax-hub.desktop` |

The payload is assembled at `linux-build/opt/minimax-hub`. Runtime archives are cached under `.cache/runtimes`, Windows source resources are staged under `.cache/windows-payload/payload`, the installed desktop icon is staged from local payload PNG resources into `linux-build/usr/share/icons/hicolor/256x256/apps/minimax-hub.png`, and assembly reports are written under `.cache/assembly`.

## Supported Build Hosts

The scripts are written for Linux, WSL, or Git Bash style shells with Bash available.

| Host family | Package format | Main build tools | Runtime dependency source |
| --- | --- | --- | --- |
| Debian, Ubuntu | `.deb` | `bash`, `dpkg-deb`, `curl` or `wget`, `tar`, `unzip`, `python3` or `python` | `linux-build/DEBIAN/control` |
| Fedora, RHEL, Rocky | `.rpm` | `bash`, `rpmbuild`, `rpm`, `curl` or `wget`, `tar`, `unzip`, `python3` or `python` | `rpm/minimax-hub.spec` |
| openSUSE | RPM style install testing | `bash`, RPM tools, `curl` or `wget`, `tar`, `unzip`, `python3` or `python` | See `rpm/DEPENDENCIES.md` |

Use `rpm/DEPENDENCIES.md` for package name mappings. The RPM spec is the authoritative Fedora, RHEL, and Rocky packaging target. openSUSE mappings are dependency guidance for testing, not a separate package spec.

## Install From a Release

Most users should install the prebuilt package attached to a GitHub Release. Download the `.deb` or `.rpm` asset for your distro family, then run one of these commands from the download directory.

Debian or Ubuntu:

```bash
sudo apt install ./minimax-hub_0.1.45_amd64.deb
```

Fedora, RHEL, or Rocky:

```bash
sudo dnf install ./minimax-hub-0.1.45-1.x86_64.rpm
```

openSUSE:

```bash
sudo zypper install ./minimax-hub-0.1.45-1.x86_64.rpm
```

After install, start the app from the desktop menu or run:

```bash
minimax-hub
```

## Maintainer Build Flow

Release packages are built locally because they require a MiniMax Hub installation supplied by the builder. The helper script builds packages only by default:

```bash
export MINIMAX_HUB_SOURCE="/path/to/MiniMax Hub"
bash create-release.sh
```

Maintainers with release access can explicitly publish after a successful build:

```bash
bash create-release.sh --publish
```

`--publish` is the only mode that requires GitHub CLI authentication or uploads artifacts to GitHub Releases. Fork maintainers can use the same script against their own repository credentials.

On Windows Git Bash, `create-release.sh` defaults to `%LOCALAPPDATA%\Programs\MiniMax Hub` when `MINIMAX_HUB_SOURCE` is not set. On other hosts, set `MINIMAX_HUB_SOURCE` explicitly.

## Manual Build Flow

Run commands from the repository root.

```bash
bash -n create-release.sh scripts/*.sh build.sh build-rpm.sh linux-build/DEBIAN/postinst linux-build/DEBIAN/prerm linux-build/DEBIAN/postrm tests/*.sh
bash scripts/extract-windows-payload.sh --source "/path/to/MiniMax Hub"
bash scripts/inspect-payload.sh
bash scripts/fetch-electron-linux.sh --version VERSION
bash scripts/fetch-opencode-linux.sh
bash scripts/fetch-node-linux.sh
bash scripts/fetch-ffmpeg-linux.sh
bash scripts/rebuild-native-modules.sh
bash scripts/assemble-linux-payload.sh
bash tests/verify-payload.sh
bash scripts/smoke-runtime.sh
bash tests/smoke-opencode.sh
bash tests/smoke-native-modules.sh
bash tests/smoke-mcp.sh
bash tests/smoke-gateway.sh
bash tests/verify-desktop.sh
bash build.sh
bash build-rpm.sh
```

`VERSION` in the Electron fetch command must match the Electron Linux runtime needed by the staged app. If `package-manifest.json` already contains `runtimePlaceholders.electronVersion`, you may omit `--version`.

`bash build.sh` creates `output/minimax-hub_0.1.45_amd64.deb` and runs `tests/verify-deb.sh` on that artifact. `bash build-rpm.sh` creates `output/minimax-hub-0.1.45-1.x86_64.rpm` and runs `tests/verify-rpm.sh` when the `rpm` command is available.

## Artifact Source Policy

Only packaging scripts, metadata, documentation, tests, and empty scaffolding belong in git. Do not commit MiniMax application payloads, Windows runtime files, Linux runtime archives, native module output, `.deb` files, `.rpm` files, or generated reports.

Allowed source inputs are local files supplied by the builder:

| Input | Source | Staged path |
| --- | --- | --- |
| MiniMax app resources | Local MiniMax Hub install root passed with `--source` | `.cache/windows-payload/payload` |
| Desktop icon | Local MiniMax payload PNG from staged icons, assets, resources, or top-level payload files | `linux-build/usr/share/icons/hicolor/256x256/apps/minimax-hub.png` |
| Electron Linux runtime | Official Electron Linux x64 release or local archive | `linux-build/opt/minimax-hub/electron` |
| Node Linux runtime | Official Node Linux x64 release or local archive | `linux-build/opt/minimax-hub/node/bin/node` |
| OpenCode Linux binary | OpenCode Linux x64 release or local archive | `linux-build/opt/minimax-hub/resources/opencode/opencode` |
| FFmpeg and FFprobe | Linux archive or explicit local binaries | `linux-build/opt/minimax-hub/resources/ffmpeg/` |
| Native Node modules | Rebuilt from staged gateway dependencies | `linux-build/opt/minimax-hub/resources/gateway/node_modules` |

## Troubleshooting

See `INSTALL.md` for detailed fixes. Common checks are:

```bash
bash scripts/inspect-payload.sh --no-fail
bash scripts/smoke-runtime.sh
bash tests/smoke-native-modules.sh
bash tests/verify-payload.sh
```

Missing payload errors mean extraction has not staged the local MiniMax app resources. Missing icon errors mean no usable local PNG was found in staged payload resources for the installed hicolor icon path. Missing Electron, OpenCode, Node, FFmpeg, or native module errors mean the matching fetch or rebuild step has not completed for Linux. Forbidden Windows artifact errors mean a `.exe`, `.dll`, `.bat`, `.cmd`, or Windows-specific directory remained in the Linux payload and must be removed before packaging. Updater metadata such as `resources/app-update.yml` or top-level `app-update.yml` is removed from the final Linux payload and must not appear in packages.
