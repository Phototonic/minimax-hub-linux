# RPM Dependencies

RPM dependency mapping will be completed when the runtime payload and package scripts are implemented.

This scaffold does not download or vendor proprietary MiniMax files, Electron, Node, OpenCode, or FFmpeg.

## Initial Runtime Mapping

| Purpose | Fedora/RHEL | openSUSE |
| --- | --- | --- |
| Electron GTK | `gtk3` | `gtk3` |
| NSS | `nss` | `mozilla-nss` |
| X11/XCB | `libX11`, `libX11-xcb`, `libxcb` | `libX11-6`, `libX11-xcb1`, `libxcb1` |
| Compositing | `libXcomposite`, `libXdamage`, `libXrandr` | `libXcomposite1`, `libXdamage1`, `libXrandr2` |
| Audio | `alsa-lib` | `alsa-lib` |
| GPU/GBM | `libdrm`, `mesa-libgbm` | `libdrm2`, `libgbm1` |
| Desktop integration | `xdg-utils`, `desktop-file-utils` | `xdg-utils`, `desktop-file-utils` |
| FFmpeg | Bundled or distro-specific package, to be decided later | Bundled or distro package, to be decided later |
