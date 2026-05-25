# Contributing

Keep contributions focused on Linux packaging for the unofficial community MiniMax Hub port. Proprietary MiniMax payloads are not committed here and are not redistributed by this project.

## Ground Rules

1. Keep changes scoped to the task at hand.
2. Do not commit MiniMax app payloads, runtime archives, generated packages, generated reports, or local caches.
3. Do not claim redistribution permission for proprietary payloads.
4. Keep commands and artifact names in docs aligned with the scripts.
5. Add or update tests when script behavior changes.
6. Preserve clear failure messages for missing payloads and missing Linux runtimes.

## Documentation Changes

When docs change, check that they match these current facts:

| Item | Current value |
| --- | --- |
| Package | `minimax-hub` |
| Version | `0.1.44` from `VERSION` |
| Debian artifact | `output/minimax-hub_0.1.44_amd64.deb` |
| RPM artifact | `output/minimax-hub-0.1.44-1.x86_64.rpm` |
| Payload root | `linux-build/opt/minimax-hub` |
| Windows source cache | `.cache/windows-payload/payload` |
| Runtime cache | `.cache/runtimes` |
| Assembly reports | `.cache/assembly` |

Use exact script names in examples:

```bash
bash scripts/extract-windows-payload.sh --source "/path/to/MiniMax Hub"
bash scripts/inspect-payload.sh
bash scripts/fetch-electron-linux.sh --version VERSION
bash scripts/fetch-opencode-linux.sh
bash scripts/fetch-node-linux.sh
bash scripts/fetch-ffmpeg-linux.sh
bash scripts/rebuild-native-modules.sh
bash scripts/assemble-linux-payload.sh
bash build.sh
bash build-rpm.sh
```

## Local Verification

For documentation-only changes, run a safe syntax check on documented shell scripts when possible:

```bash
bash -n build.sh build-rpm.sh scripts/*.sh tests/*.sh
```

For script or packaging changes, run the relevant checks from this matrix:

```bash
bash tests/verify-payload.sh
bash scripts/smoke-runtime.sh
bash tests/smoke-opencode.sh
bash tests/smoke-native-modules.sh
bash tests/smoke-mcp.sh
bash tests/smoke-gateway.sh
bash tests/verify-desktop.sh
bash build.sh
bash tests/verify-deb.sh output/minimax-hub_0.1.44_amd64.deb
bash build-rpm.sh
bash tests/verify-rpm.sh output/minimax-hub-0.1.44-1.x86_64.rpm
```

Do not run install commands on a shared machine unless you intend to install the local package. Install tests should use disposable VMs or containers where possible.

## Release Checklist

Before publishing a release artifact, verify each item:

1. `VERSION`, `package-manifest.json`, `linux-build/DEBIAN/control`, and `rpm/minimax-hub.spec` agree on the release version.
2. The MiniMax source payload came from a local installation supplied by the release builder.
3. Proprietary MiniMax payloads, runtime archives, generated reports, and package artifacts are not committed.
4. Electron, Node, OpenCode, FFmpeg, and FFprobe were fetched from documented sources or staged from local files with recorded checksums.
5. Native modules were rebuilt for Linux x64 glibc and verified with the packaged Node runtime.
6. `bash -n build.sh build-rpm.sh scripts/*.sh tests/*.sh` passes.
7. `bash tests/verify-payload.sh` passes after assembly.
8. Runtime, OpenCode, native module, MCP, gateway, and desktop smoke tests pass on the release build host.
9. `bash build.sh` creates `output/minimax-hub_0.1.44_amd64.deb` and runs `tests/verify-deb.sh` successfully.
10. `bash build-rpm.sh` creates `output/minimax-hub-0.1.44-1.x86_64.rpm` and runs `tests/verify-rpm.sh` successfully when `rpm` is available.
11. Install the `.deb` on a Debian or Ubuntu test system and launch `minimax-hub`.
12. Install the `.rpm` on a Fedora, RHEL, Rocky, or compatible RPM test system and launch `minimax-hub`.
13. Confirm desktop entry registration, protocol handler metadata, `chrome-sandbox` mode, gateway startup, MCP startup, OpenCode startup, and FFmpeg execution.
14. Record known risks, unsupported distros, and any runtime source substitutions in release notes.

## Release Artifact Policy

Release artifacts must be built from the local staged inputs for that release. Do not publish private download URLs, fake checksums, or claims that proprietary MiniMax payloads are covered by this repository license.

If a release includes generated `.deb` or `.rpm` files outside git, the release notes must state that the package is an unofficial community build, identify the source of each Linux runtime component at a high level, and tell users that MiniMax proprietary components remain subject to upstream MiniMax terms.
