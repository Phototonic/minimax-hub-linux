# Licensing and Distribution Notes

This project is an unofficial community Linux packaging effort for MiniMax Hub. It is not an official MiniMax release.

Proprietary MiniMax payloads are not committed to this repository and are not redistributed by the source tree. Builders provide their own local MiniMax Hub installation as the source for application resources. Redistribution of any generated package that contains MiniMax application payloads depends on upstream MiniMax terms and any third-party licenses that apply to the bundled components.

## Repository Content

The repository is intended to contain:

| Content | Policy |
| --- | --- |
| Packaging scripts | May be committed |
| Verification tests | May be committed |
| Debian and RPM metadata | May be committed |
| Documentation | May be committed |
| Empty scaffold directories | May be committed when needed |
| MiniMax application payloads | Must not be committed |
| Windows runtime files | Must not be committed |
| Linux runtime archives | Must not be committed |
| Rebuilt native modules | Must not be committed |
| `.deb` and `.rpm` outputs | Must not be committed |
| Generated reports and caches | Must not be committed |

## Runtime Components

The build can stage these runtime components:

| Component | Default handling | Notes |
| --- | --- | --- |
| MiniMax app resources | Copied from a local MiniMax Hub install root | Proprietary payload, not repository content |
| Electron Linux x64 | Fetched from Electron releases or provided as a local archive | Checksum verified with Electron `SHASUMS512.txt` |
| Node Linux x64 | Fetched from Node releases or provided as a local archive | Checksum verified with Node `SHASUMS256.txt` |
| OpenCode Linux x64 | Fetched from OpenCode releases or provided as a local archive | Local SHA256 recorded when upstream checksums are unavailable |
| FFmpeg and FFprobe | Fetched from a Linux archive or provided as local binaries | Upstream checksum used when available, otherwise local SHA256 recorded |
| Gateway native modules | Rebuilt or installed for Linux x64 glibc | Must be verified with packaged Node |

Each component keeps its own upstream license or terms. This document does not grant extra redistribution rights.

## Source Artifact Policy

A release builder may use local source inputs to produce packages, but those inputs must stay outside git:

```text
.cache/windows-payload/payload
.cache/runtimes
.cache/assembly
linux-build/opt/minimax-hub runtime payload after assembly
output/minimax-hub_0.1.44_amd64.deb
output/minimax-hub-0.1.44-1.x86_64.rpm
```

The scripts reject common Windows runtime artifacts in Linux payloads, including `.exe`, `.dll`, `.bat`, `.cmd`, and directories whose names identify Windows-specific module builds. Do not bypass those checks.

## Release Notes Requirements

Release notes for generated packages should state:

1. The package is an unofficial community build.
2. The package version and artifact names.
3. The Linux runtime component sources used by the builder.
4. That proprietary MiniMax components are subject to upstream MiniMax terms.
5. Any known runtime, desktop integration, sandbox, gateway, MCP, OpenCode, FFmpeg, or native module risks.

Do not publish private source URLs, fake checksums, or statements that imply this repository owns or relicenses MiniMax proprietary payloads.
