# MTProxyMax Telemt 3.5.16 — unofficial release candidate (DRAFT)

> **UNPUBLISHED DEVELOPMENT CANDIDATE — NOT FOR PRODUCTION INSTALLATION.**  
> This page describes a candidate in [Krezi-777/MTProxyMax](https://github.com/Krezi-777/MTProxyMax); no GitHub Release, verified public distribution archive or Docker image has been published. The upstream project and maintainers have not endorsed this fork.

## Why this fork exists

The build problem reported in [SamNet-dev/MTProxyMax issue #162](https://github.com/SamNet-dev/MTProxyMax/issues/162) involves a Bash-only substring expression inside a Dockerfile `RUN` layer executed using POSIX `/bin/sh`. The fork changes the affected build logic to POSIX-compatible syntax and tests the pinned Telemt 3.5.16 engine (source revision `84e5b82`).

The development branch also adds guarded engine replacement, selected rollback/recovery protections, secondary-instance handling and isolated HAProxy integration testing. These are **additional experimental fork changes**, not an upstream-approved patch.

## Candidate identity and provenance

| Field | Value |
| --- | --- |
| GitHub fork | `Krezi-777/MTProxyMax` |
| Development branch | `fix/telemt-posix-build` |
| Last fully tested *code* revision | `05aa2d05128f179043fa33f49a3c09bb48f30ee3` |
| Telemt source revision used in tests | `84e5b82` (Telemt 3.5.16) |
| Release tag | **NOT CREATED** |
| Published Docker image | **NONE** |
| Independently verified `mtproxymax.sh` SHA-256 | `aa527da3314d29ec9ed5e59ca09a1e0c96d1fd5db397c5f705c4831cce1abf7e` — checked against an immutable raw GitHub download in [provenance run 42219216246](https://github.com/Krezi-777/MTProxyMax/actions/runs/42219216246) |
| Independently verified `install.sh` SHA-256 | `c04916744e494fadd13d8c4797feb68d9014f1b7e11737c49d089789b4198cba` — checkout plus immutable raw HTTPS verified in [run 42219426404](https://github.com/Krezi-777/MTProxyMax/actions/runs/42219426404) |
| Release package checksum | **NOT YET RECORDED** |
| Published install command | **NONE** |

The manager and installer digests were independently checked on isolated GitHub Runners using `sha256sum` on the checkout and an immutable raw HTTPS download, with byte-for-byte comparison. This is integrity evidence, **not a digital signature**, clean-install acceptance or publication authorization. The release commit cannot be finalized until the documentation and remaining changes stop moving. A Git commit SHA identifies a source-tree revision; it is **not** the SHA-256 digest of the raw manager script or a Docker image.

## Test evidence (development, not operational deployment)

All four GitHub Actions workflow groups completed SUCCESS for `05aa2d05128f179043fa33f49a3c09bb48f30ee3`:

- [CI / distribution and lint](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866342)
- [Full Stack Integration: manager + Telemt + HAProxy](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866430)
- [Real Docker Rollback Integration](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866367)
- [Telemt Smoke Test](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866405)

These tests are confined to disposable GitHub Runners. They do not establish real Telegram client traffic, your production HAProxy routing or an in-place VPS upgrade. The service-health probes are partly TCP-level and do not fully validate MTProto behavior.

## Installation — not yet enabled for the public

The fork installer `install.sh` intentionally refuses moving-branch sources. It requires `MTPROXYMAX_SOURCE_COMMIT` (40 hexadecimal characters) and `MTPROXYMAX_SOURCE_SHA256` (64 hexadecimal characters), checks the downloaded manager's checksum and Bash syntax, and refuses mismatches.

A **future**, separately approved installation guide must supply a reviewed immutable commit and the independently generated SHA-256 of `mtproxymax.sh` at **that same commit**, then demonstrate that a clean isolated installation works. There is no public copy-and-paste install command in this draft. The original Quick Start in the upstream README downloads **SamNet-dev's upstream installer**, not this modified fork.

## Release preparation checklist

- [x] Independent upstream issue analysis and tested POSIX shell correction.
- [x] Isolated Docker, rollback, group-lock, TCP readiness and selected failure-injection tests on the last tested code commit.
- [x] Recovery runbook drafted at [GROUP_UPGRADE_RECOVERY_RUNBOOK.md](GROUP_UPGRADE_RECOVERY_RUNBOOK.md).
- [ ] Final reviewed source commit and immutable tag designated.
- [ ] Full CI green on that exact final commit (including docs and packaging).
- [x] Independently verify the manager SHA-256 against immutable raw HTTPS content on a GitHub Runner.
- [x] Independently verify the installer SHA-256 against immutable raw HTTPS content on a GitHub Runner.
- [ ] Independently record checksums of any future release packages/assets.
- [ ] Confirm no unexpected secrets/configuration in public source and no existing-name/tag collisions.
- [ ] Repeat clean installation in isolated environment using immutable ref and matching SHA-256.
- [ ] Decide how to handle unresolved partial rollback and real Telegram/client validation; document accepted limitations explicitly.
- [ ] Obtain explicit owner approval for public publication.
- [ ] Publish a release separately; verify its tag, assets and links after publishing.
- [ ] Only then reply to upstream issue #162 with a neutral description and link, without implying official status.

## Rollback, support and attribution

See the [conservative recovery runbook](GROUP_UPGRADE_RECOVERY_RUNBOOK.md) and [release readiness audit](RELEASE_READINESS_AUDIT.md). Keep original Docker containers and configuration backups until recovery is complete. No production changes or automatic cleanup of rollback evidence are authorized here.

This is an **unofficial fork** of [SamNet-dev/MTProxyMax](https://github.com/SamNet-dev/MTProxyMax). Retain upstream copyright and the repository's MIT license, and independently check applicable engine redistribution license terms before distributing any built binary/image.
