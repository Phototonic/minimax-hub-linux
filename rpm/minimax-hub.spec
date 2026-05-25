Name: minimax-hub
Version: 0.1.44
Release: 1%{?dist}
Summary: MiniMax Hub unofficial Linux package scaffold
License: Proprietary payload not included
BuildArch: x86_64
Requires: gtk3
Requires: nss
Requires: libX11
Requires: libX11-xcb
Requires: libxcb
Requires: libXcomposite
Requires: libXdamage
Requires: libXrandr
Requires: alsa-lib
Requires: libdrm
Requires: mesa-libgbm
Requires: xdg-utils
Requires: desktop-file-utils

%description
Scaffold spec for the future MiniMax Hub Linux RPM package. Proprietary MiniMax
payloads, generated binaries, and downloaded runtimes are not included in this
repository. Later tasks will assemble the shared linux-build payload before RPM
packaging.

%prep
echo "Scaffold only: RPM prep will consume an assembled linux-build tree later."

%build
echo "Scaffold only: RPM build is not implemented yet."

%install
echo "Scaffold only: RPM install will copy the staged payload later."

%post
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || :
fi
if [ -f /opt/minimax-hub/chrome-sandbox ]; then
  chown root:root /opt/minimax-hub/chrome-sandbox || :
  chmod 4755 /opt/minimax-hub/chrome-sandbox || :
fi

%preun
echo "MiniMax Hub scaffold preun: no service shutdown required yet." >&2

%postun
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || :
fi

%files
%dir /opt/minimax-hub
/usr/bin/minimax-hub
/usr/share/applications/minimax-hub.desktop
