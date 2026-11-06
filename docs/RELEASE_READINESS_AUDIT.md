# Release readiness audit — MTProxyMax Telemt POSIX build fix

**Date:** 2026-11-06  
**Repository:** [Krezi-777/MTProxyMax](https://github.com/Krezi-777/MTProxyMax)  
**Candidate branch:** `fix/telemt-posix-build`  
**Previously verified baseline:** `496ae9f19e78f8e6095cbd14ff23c1bd9c2adaed`  
**Latest development changes:** source-pinned installer, verified fork script update, config rollback (reverification required)  
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

**B1 — Installer source — CODE CORRECTED; RELEASE PROCEDURE PENDING.** `install.sh` now downloads from this fork only when the operator explicitly supplies a 40-hex immutable commit and SHA-256 digest; it checks checksum and Bash syntax before execution. The README prominently warns that its original quick-start command targets upstream. A reviewed immutable release commit and checksum have not yet been designated. Recheck CI before accepting this gate.

**B2 — Fork update policy — CODE CORRECTED; VERIFICATION PENDING.** The default upstream update checker remains read-only with an overwrite guard. A separate opt-in path accepts `MTPROXYMAX_FORK_UPDATE_COMMIT` and `MTPROXYMAX_FORK_UPDATE_SHA256`, downloads this fork at an immutable ref and requires matching checksum before replacement. A manager backup is now mandatory before replacement. CI regression tests for pinned source and bad checksum were added; review these results and the operator workflow before accepting.

**B3 — Recovery path — CONFIG RESTORATION ADDED; ADDITIONAL SCOPE PENDING.** The helper now snapshots `config.toml` before stopping the old container; on a failed replacement, it atomically restores the saved file before restarting the previous container. The unit and full-stack tests now inject a configuration mutation. The real `run_proxy_container()` remains substituted by a test function; auxiliary instances and other changed files are not included in the rollback contract. Consequently complete production rollback is **not** proven.

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
- [ ] B1: fork-specific installer source guard updated; regression checks and reviewed immutable release checksum pending.
- [ ] B2: pinned fork update strategy added; CI verification and operator workflow review pending.
- [ ] B3: primary config snapshot/restore added; complete primary execution and extra-instance rollback acceptance pending.
- [ ] B4: dedicated Telegram connectivity and topology acceptance completed without risking live service.
- [ ] B5: downloadable artifact or reproducible immutable-source installation, version provenance and verification documented.
- [ ] Release notes and any user-facing instructions independently reviewed.
- [ ] User explicitly authorizes publishing a release.
- [ ] User separately authorizes any production deployment.

**Decision:** Keep release as a draft. Do not merge automatically, publish a GitHub Release, provide a public install command claiming a production-ready fix, or change the VPS.
