# Release readiness audit — MTProxyMax Telemt POSIX build fix

**Date:** 2026-11-06  
**Repository:** [Krezi-777/MTProxyMax](https://github.com/Krezi-777/MTProxyMax)  
**Candidate branch:** `fix/telemt-posix-build`  
**Audited head:** `496ae9f19e78f8e6095cbd14ff23c1bd9c2adaed`  
**Status:** **NOT READY FOR PUBLIC RELEASE / PRODUCTION DEPLOYMENT**

This is an independent, unofficial development branch. It is not a release of SamNet-dev.

## Scope and evidence

The branch is 25 commits ahead of its fork's `main`, changing 12 files as of this audit.
The original failure was Bash substring expansion (`${TELEMT_COMMIT:0:7}`) inside a Dockerfile `RUN` command executed by POSIX `/bin/sh`. It was replaced with POSIX-compatible `printf` in the manager-generated Dockerfile and the build workflow.

Recorded passing workflows at audited commit:

| Workflow | Run | Result |
| --- | --- | --- |
| Multi-distribution CI | [42181931454](https://github.com/Krezi-777/MTProxyMax/actions/runs/42181931454) | SUCCESS |
| Native AMD64 Telemt smoke | [42181931457](https://github.com/Krezi-777/MTProxyMax/actions/runs/42181931457) | SUCCESS |
| Real Docker rollback | [42181931549](https://github.com/Krezi-777/MTProxyMax/actions/runs/42181931549) | SUCCESS |
| Telemt + HAProxy + manager rollback | [42181931450](https://github.com/Krezi-777/MTProxyMax/actions/runs/42181931450) | SUCCESS |
| Multiarch Telemt build | [42168436643](https://github.com/Krezi-777/MTProxyMax/actions/runs/42168436643) | SUCCESS on earlier candidate |

The full-stack test uses a synthetic config and internal Docker bridge, not the production HAProxy or the manager's unmodified `run_proxy_container()`. The actual manager rollback helper is exercised with test-specific side-effect helpers. Its 3/3 success establishes the tested contract only. The offline Telemt tests do **not** establish production Telegram network reachability or MTProto client functionality.

## Release blockers

**B1 — Installer selects upstream source — CONFIRMED.** `install.sh` downloads `https://raw.githubusercontent.com/SamNet-dev/MTProxyMax/main/mtproxymax.sh`, not this branch or fork. The repository README's quick-start command likewise uses upstream. Using the original installer cannot be represented as installing this fix. Correct and test a fork-specific, immutable-ref installer flow before distribution.

**B2 — Fork update policy and UX — CONFIRMED.** The manager retains `GITHUB_REPO="SamNet-dev/MTProxyMax"` and `self_update()` checks that repository's `main`. The fork-specific guard blocks replacing the script by default, which prevents accidental overwrite but means the advertised self-update is not a complete fork update strategy. Define and test trusted version/source selection and upgrade behavior.

**B3 — Recovery path not end-to-end production-equivalent — CONFIRMED LIMITATION.** The helper saves and restores the old container, but `run_proxy_container()` regenerates configuration, calls image-building helpers and applies host-network Docker options. Tests substitute this function. A failed update may therefore alter on-disk configuration while restoring an old container. Audit and test config snapshot/restore and auxiliary instances before saying 'complete rollback'.

**B4 — Real connectivity and production topology unverified — CONFIRMED LIMITATION.** GitHub full-stack uses isolated Docker DNS plus synthetic configuration, TCP readiness and HAProxy statistics. It does not verify the actual proxy traffic, actual HAProxy topology, external reachability, production secrets, proxy-protocol handling, or dependent instances. Production VPS was not accessed.

**B5 — Release artifact provenance is incomplete — CONFIRMED.** The build workflow explicitly uses `push: false`; there is no published image to direct users to. Need a documented, tested, versioned delivery mechanism and checksums/commit references before public instructions. The tested Dockerfile uses a pinned Telemt commit `84e5b82`; do not claim a signed artifact exists.

## Operational cautions

- Old images and successful-upgrade rollback containers are retained by design. This preserves rollback options but requires a documented inventory and disk-pressure / manual-cleanup policy.
- The existing self-update tests use stubbed dependencies; real-Docker rollback tests cover only four selected cases.
- Test artifacts and container cleanup are scoped to disposable GitHub-hosted runners. Never run these integration scripts against the production Docker host.
- The separate draft PR remains WIP; its existing description may contain obsolete "tests pending" text.
- MIT license remains applicable; keep upstream copyright and attribution intact.
- The production setup currently described as Telemt 3.5.14 behind HAProxy must remain untouched pending separate approval.

## Acceptance gates (all required)

- [x] Original POSIX shell build defect addressed and tested.
- [x] Multi-distribution CI, smoke, real-Docker rollback, and synthetic full-stack tests passed on the audited commit.
- [ ] B1: fork-specific installation path fixed and tested.
- [ ] B2: fork self-update source strategy explicitly specified and tested.
- [ ] B3: on-disk configuration + extra-instance rollback behavior and durable recovery tested.
- [ ] B4: dedicated Telegram connectivity and topology acceptance completed without risking live service.
- [ ] B5: downloadable artifact or reproducible immutable-source installation, version provenance and verification documented.
- [ ] Release notes and any user-facing instructions independently reviewed.
- [ ] User explicitly authorizes publishing a release.
- [ ] User separately authorizes any production deployment.

**Decision:** Keep release as a draft. Do not merge automatically, publish a GitHub Release, provide a public install command claiming a production-ready fix, or change the VPS.
