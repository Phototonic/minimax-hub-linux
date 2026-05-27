# MiniMax Hub Linux

Unofficial community Linux packaging for MiniMax Hub.

> **Note**: This project is not affiliated with MiniMax. MiniMax Hub is proprietary software owned by MiniMax. This repository contains packaging scripts and documentation; proprietary MiniMax payloads are not committed to the source tree.

## Download Packages

Download the latest `.deb` or `.rpm` package from [GitHub Releases](https://github.com/Phototonic/minimax-hub-linux/releases).

Current package names:

- Debian/Ubuntu: `minimax-hub_0.1.45_amd64.deb`
- Fedora/RHEL/Rocky/openSUSE: `minimax-hub-0.1.45-1.x86_64.rpm`

## Installation

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

Launch from your desktop menu or run:

```bash
minimax-hub
```

## Features

- Desktop launcher for MiniMax Hub
- Protocol handler registration for MiniMax Hub links
- Bundled Electron, Node.js, OpenCode, FFmpeg, and native module runtime payloads
- Debian and RPM package metadata for common desktop Linux distributions
- Desktop icon and application menu integration

## Supported Distributions

- Debian and Ubuntu via `.deb`
- Fedora, RHEL, and Rocky Linux via `.rpm`
- openSUSE via RPM-style install testing

See [`rpm/DEPENDENCIES.md`](rpm/DEPENDENCIES.md) for dependency mappings across distro families.

## System Requirements

- 64-bit x86 Linux desktop environment
- GTK 3, NSS, X11, audio, and desktop integration libraries
- Enough disk space for a full Electron application package

The packages declare the main distro dependencies. Bundled runtime components live under `/opt/minimax-hub`.

## Maintainer Builds

Release packages are built locally because they require a MiniMax Hub installation supplied by the builder. The helper script builds packages only by default:

```bash
export MINIMAX_HUB_SOURCE="/path/to/MiniMax Hub"
bash create-release.sh
```

Maintainers with release access can explicitly publish after a successful build:

```bash
bash create-release.sh --publish
```

`--publish` is the only mode that requires GitHub CLI authentication or uploads artifacts to GitHub Releases. On Windows Git Bash, `create-release.sh` defaults to `%LOCALAPPDATA%\Programs\MiniMax Hub` when `MINIMAX_HUB_SOURCE` is not set.

For detailed build, verification, and troubleshooting steps, see [`INSTALL.md`](INSTALL.md), [`CONTRIBUTING.md`](CONTRIBUTING.md), and [`LICENSES.md`](LICENSES.md).

## Troubleshooting

### App does not start

Run from a terminal to see startup output:

```bash
minimax-hub
```

### Protocol links do not open

Refresh desktop integration:

```bash
update-desktop-database ~/.local/share/applications 2>/dev/null || true
```

### Package build fails

Check the staged payload and runtime files:

```bash
bash scripts/inspect-payload.sh --no-fail
bash scripts/smoke-runtime.sh
bash tests/verify-payload.sh
```

See [`INSTALL.md`](INSTALL.md) for the full troubleshooting guide.

## Disclaimer

This is an unofficial community packaging project. MiniMax is not affiliated with this repository. Generated packages may contain proprietary MiniMax application payloads supplied by the release builder, and those components remain subject to upstream MiniMax terms.

## Links

- [MiniMax](https://www.minimax.io/)
- [Releases](https://github.com/Phototonic/minimax-hub-linux/releases)
- [Issues](https://github.com/Phototonic/minimax-hub-linux/issues)
