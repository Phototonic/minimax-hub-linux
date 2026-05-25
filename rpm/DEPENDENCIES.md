# Runtime Dependencies

This file maps package dependencies for the unofficial MiniMax Hub Linux package. The Debian mapping comes from `linux-build/DEBIAN/control`. The Fedora, RHEL, and Rocky mapping comes from `rpm/minimax-hub.spec`. openSUSE names are install guidance for testing where equivalent packages are available.

Proprietary MiniMax payloads are not committed or redistributed by this repository.

## Build Tool Packages

| Purpose | Debian, Ubuntu | Fedora, RHEL, Rocky | openSUSE |
| --- | --- | --- | --- |
| Shell | `bash` | `bash` | `bash` |
| Downloads | `curl` or `wget` | `curl` or `wget` | `curl` or `wget` |
| Archives | `tar`, `unzip` | `tar`, `unzip` | `tar`, `unzip` |
| Manifest helper | `python3` or `python` | `python3` or `python` | `python3` or `python` |
| Node package rebuilds | `npm` | `npm` | `npm` |
| Debian package build | `dpkg-dev` | not applicable | not applicable |
| RPM package build | not applicable | `rpm-build`, `rpm` | `rpm-build`, `rpm` |
| Desktop validation | `desktop-file-utils` | `desktop-file-utils` | `desktop-file-utils` |

Build-only native module work may also need a compiler, make, Python headers or tooling, and SQLite development headers depending on the staged `better-sqlite3` build path.

## Runtime Package Mapping

| Purpose | Debian, Ubuntu | Fedora, RHEL, Rocky | openSUSE |
| --- | --- | --- | --- |
| GTK 3 | `libgtk-3-0` | `gtk3` | `gtk3` |
| NSS | `libnss3` | `nss` | `mozilla-nss` |
| X11 | `libx11-6` | `libX11` | `libX11-6` |
| X11 XCB bridge | `libx11-xcb1` | `libX11-xcb` | `libX11-xcb1` |
| XCB | `libxcb1` | `libxcb` | `libxcb1` |
| X compositing | `libxcomposite1` | `libXcomposite` | `libXcomposite1` |
| X damage | `libxdamage1` | `libXdamage` | `libXdamage1` |
| X randr | `libxrandr2` | `libXrandr` | `libXrandr2` |
| X screen saver | commonly pulled by Electron stack | `libXScrnSaver` | `libXScrnSaver` |
| X test | commonly pulled by Electron stack | `libXtst` | `libXtst6` |
| Audio | `libasound2` | `alsa-lib` | `alsa-lib` |
| Accessibility toolkit | commonly pulled by GTK stack | `atk`, `at-spi2-atk` | `atk`, `at-spi2-atk` |
| Printing libraries | commonly pulled by GTK stack | `cups-libs` | `cups-libs` or `libcups2` |
| DRM | `libdrm2` | `libdrm` | `libdrm2` |
| GBM | `libgbm1` | `mesa-libgbm` | `libgbm1` |
| Pango text layout | commonly pulled by GTK stack | `pango` | `pango` |
| XDG helpers | `xdg-utils` | `xdg-utils` | `xdg-utils` |
| Desktop database | `desktop-file-utils` | `desktop-file-utils` | `desktop-file-utils` |
| FFmpeg runtime | bundled under `/opt/minimax-hub/resources/ffmpeg` | bundled under `/opt/minimax-hub/resources/ffmpeg` | bundled under `/opt/minimax-hub/resources/ffmpeg` |
| Node runtime | bundled under `/opt/minimax-hub/node` | bundled under `/opt/minimax-hub/node` | bundled under `/opt/minimax-hub/node` |
| OpenCode runtime | bundled under `/opt/minimax-hub/resources/opencode` | bundled under `/opt/minimax-hub/resources/opencode` | bundled under `/opt/minimax-hub/resources/opencode` |

The Debian package currently declares this exact dependency line:

```text
Depends: libgtk-3-0, libnss3, libx11-6, libx11-xcb1, libxcb1, libxcomposite1, libxdamage1, libxrandr2, libasound2, libdrm2, libgbm1, xdg-utils, desktop-file-utils
```

The RPM spec currently declares:

```text
Requires: gtk3
Requires: nss
Requires: libX11
Requires: libX11-xcb
Requires: libxcb
Requires: libXcomposite
Requires: libXdamage
Requires: libXrandr
Requires: libXScrnSaver
Requires: libXtst
Requires: alsa-lib
Requires: atk
Requires: at-spi2-atk
Requires: cups-libs
Requires: libdrm
Requires: mesa-libgbm
Requires: pango
Requires: xdg-utils
Requires: desktop-file-utils
Requires(post): desktop-file-utils
Requires(postun): desktop-file-utils
```

## Install Commands

Debian or Ubuntu:

```bash
sudo apt install ./output/minimax-hub_0.1.44_amd64.deb
```

Fedora, RHEL, or Rocky:

```bash
sudo dnf install ./output/minimax-hub-0.1.44-1.x86_64.rpm
```

openSUSE:

```bash
sudo zypper install ./output/minimax-hub-0.1.44-1.x86_64.rpm
```

## Dependency Verification

Debian artifact metadata:

```bash
dpkg-deb --info output/minimax-hub_0.1.44_amd64.deb
dpkg-deb --contents output/minimax-hub_0.1.44_amd64.deb
bash tests/verify-deb.sh output/minimax-hub_0.1.44_amd64.deb
```

RPM artifact metadata:

```bash
rpm -qpi output/minimax-hub-0.1.44-1.x86_64.rpm
rpm -qpl output/minimax-hub-0.1.44-1.x86_64.rpm
rpm -qp --requires output/minimax-hub-0.1.44-1.x86_64.rpm
bash tests/verify-rpm.sh output/minimax-hub-0.1.44-1.x86_64.rpm
```

`tests/verify-rpm.sh` checks for `gtk3`, `nss`, and `desktop-file-utils` in RPM requirements, confirms desktop and icon cache scriptlets, validates `chrome-sandbox`, requires `/usr/share/icons/hicolor/256x256/apps/minimax-hub.png`, rejects packaged `resources/app-update.yml`, and inspects the extracted payload when `rpm2cpio` plus `cpio` or `bsdtar` is available.

## Dependency Risks

Electron dependency names differ across distro families. If a distro does not provide one of the names above, install the closest provider for the same shared library and record that substitution in release notes.

The package bundles Electron, Node, OpenCode, FFmpeg, FFprobe, and rebuilt native modules under `/opt/minimax-hub`. Distro packages still need GTK, NSS, X11, audio, desktop integration, and related system libraries.

`chrome-sandbox` needs setuid root mode `4755` for the standard Electron sandbox path. The Debian build sets that mode before packaging only after confirming it is a regular non-symlink executable. The RPM spec records it with `%attr(4755,root,root)` and also fixes ownership and mode in `%post` when the installed path remains a regular non-symlink executable.
