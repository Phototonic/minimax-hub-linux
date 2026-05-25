%global app_name minimax-hub
%global app_dir /opt/minimax-hub
%global staged_root %{?_staged_root}%{!?_staged_root:%{_builddir}/linux-build}
%global payload_filelist %{?_payload_filelist}%{!?_payload_filelist:%{_builddir}/minimax-hub-payload.files}

Name: minimax-hub
Version: %{?_version}%{!?_version:0.1.44}
Release: 1%{?dist}
Summary: MiniMax Hub unofficial Linux package
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

%description
Unofficial Linux RPM package for MiniMax Hub built from the local staged
linux-build payload. The proprietary application payload is not included in
this source repository.

%prep
test -d "%{staged_root}/opt/minimax-hub"
test -s "%{staged_root}/usr/bin/minimax-hub"
test -s "%{staged_root}/usr/share/applications/minimax-hub.desktop"

%build
:

%install
rm -rf "%{buildroot}"
mkdir -p "%{buildroot}/opt" "%{buildroot}/usr/bin" "%{buildroot}/usr/share/applications"
cp -a "%{staged_root}/opt/minimax-hub" "%{buildroot}/opt/"
install -m 0755 "%{staged_root}/usr/bin/minimax-hub" "%{buildroot}/usr/bin/minimax-hub"
install -m 0644 "%{staged_root}/usr/share/applications/minimax-hub.desktop" "%{buildroot}/usr/share/applications/minimax-hub.desktop"
chmod 0755 "%{buildroot}/opt/minimax-hub/electron" || :
test ! -L "%{buildroot}/opt/minimax-hub/chrome-sandbox"
test -f "%{buildroot}/opt/minimax-hub/chrome-sandbox"
test -x "%{buildroot}/opt/minimax-hub/chrome-sandbox"
chmod 4755 "%{buildroot}/opt/minimax-hub/chrome-sandbox"
chmod 0755 "%{buildroot}/opt/minimax-hub/node/bin/node" || :
chmod 0755 "%{buildroot}/opt/minimax-hub/resources/opencode/opencode" || :
find "%{buildroot}/opt/minimax-hub" -mindepth 1 \( -type f -o -type l \) -printf '/%%P\n' | sed 's#^/#/opt/minimax-hub/#' | LC_ALL=C sort | grep -Fxv '/opt/minimax-hub/chrome-sandbox' > "%{payload_filelist}"

%post
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || :
fi
if [ -e /opt/minimax-hub/chrome-sandbox ] || [ -L /opt/minimax-hub/chrome-sandbox ]; then
  if [ -L /opt/minimax-hub/chrome-sandbox ]; then
    echo "Refusing to set setuid mode on symlink chrome-sandbox: /opt/minimax-hub/chrome-sandbox" >&2
    exit 1
  fi
  if [ ! -f /opt/minimax-hub/chrome-sandbox ]; then
    echo "Refusing to set setuid mode on non-regular chrome-sandbox: /opt/minimax-hub/chrome-sandbox" >&2
    exit 1
  fi
  if [ ! -x /opt/minimax-hub/chrome-sandbox ]; then
    echo "Refusing to set setuid mode on non-executable chrome-sandbox: /opt/minimax-hub/chrome-sandbox" >&2
    exit 1
  fi
  chown root:root /opt/minimax-hub/chrome-sandbox
  chmod 4755 /opt/minimax-hub/chrome-sandbox
fi
%postun
if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database /usr/share/applications || :
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
  gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor || :
fi

%files -f %{payload_filelist}
%dir /opt/minimax-hub
%attr(4755,root,root) /opt/minimax-hub/chrome-sandbox
/usr/bin/minimax-hub
/usr/share/applications/minimax-hub.desktop
