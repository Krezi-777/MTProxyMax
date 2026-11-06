# Release readiness audit — unofficial MTProxyMax Telemt 3.5.16 fork

**Audit date:** 2026-11-06  
**Repository:** [Krezi-777/MTProxyMax](https://github.com/Krezi-777/MTProxyMax)  
**Candidate branch:** `fix/telemt-posix-build`  
**Last fully green audited code commit:** `05aa2d05128f179043fa33f49a3c09bb48f30ee3`  
**Status:** **BLOCKED — NOT APPROVED FOR PUBLIC RELEASE OR PRODUCTION**

This is an independent, unofficial fork, not an upstream SamNet-dev release. Production VPS / Telemt 3.5.14 was not accessed.

## Evidence: latest green runs

| Workflow | GitHub Actions run | Result |
| --- | --- | --- |
| Multi-distribution CI | [42210866342](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866342) | SUCCESS |
| Telemt Smoke Test | [42210866405](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866405) | SUCCESS |
| Real Docker Rollback | [42210866367](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866367) | SUCCESS |
| Full Stack Integration | [42210866430](https://github.com/Krezi-777/MTProxyMax/actions/runs/42210866430) | SUCCESS |

The full-stack integration runs the actual `run_proxy_container()`, `generate_telemt_config()`, and group-upgrade functions on an isolated GitHub runner, with privileged/host-affecting helpers stubbed. Tests cover primary and one additional running instance, successful sequential replacement, injected secondary launch failure and group rollback, TCP listener readiness, HAProxy backend status for the primary, original container identities/config restoration, restart policies, and an injected failure of rollback handling.

**Scope limitation:** this does not prove the actual Telegram client protocol, real external routes, production HAProxy configuration, or all multi-instance failure states. Some checks are short-lived rather than sustained.

## Confirmed changes

- POSIX-compatible pinned Telemt image build in the manager-generated Dockerfile and build workflow; pinned engine source `84e5b82`.
- Fork installer and explicit self-update require immutable source commit and SHA-256 verification.
- Existing primary protected upgrade retains a stopped original container and restores prior `config.toml` on failure.
- Group upgrade `upgrade_all_proxy_instances_with_rollback()` sequentially replaces previously running enabled secondary instances, retains old containers, and attempts whole-group rollback on failure.
- Docker ID and restart-count stability probes reject immediate restart loops; secondary duplicate Control API listener is disabled.
- Group rollback restores originally configured Docker restart policies where tested.

## Remaining release blockers

**B1 — Concurrent operation safety: PARTIALLY MITIGATED.** Group upgrade acquires an exclusive fail-closed `flock`, and an isolated test rejects a second simultaneous group upgrade. Ordinary start/stop/restart/instance mutation commands do not use this same lock. Cross-command concurrency and externally interrupted operations remain release considerations.

**B2 — Reachability acceptance: PARTIALLY MITIGATED.** Group-upgrade function includes bounded TCP readiness probes for primary and secondary listeners, in addition to Docker status and restart-count stability. This still does not validate end-to-end Telegram client functionality or every production HAProxy backend.

**B3 — Partial rollback / crash recovery: PARTIALLY MITIGATED.** The group-upgrade function records a recovery manifest, retains rollback snapshots after unverified recovery and refuses another group upgrade while unresolved snapshot directories exist. A conservative operator runbook is provided. There is still no accepted automatic reconciliation after arbitrary interruption or fully validated cleanup/recovery of every preflight failure. The operator must not delete the only viable original container.

**B4 — Real Telegram/client traffic and target topology: OPEN.** No demonstrated end-to-end real Telegram clients, actual production HAProxy configuration, external routing or production server upgrade. These remain operational acceptance limits, not covered by GitHub green CI.

**B5 — Provenance and public install/release process: OPEN.** No approved immutable release tag, published image, signed artifact or separately verified source checksum and installation guide. Do not advertise a production-ready release or issue a public installation command yet.

## Operational precautions

- The test harness is isolated to ephemeral GitHub-hosted runners; do not run its host-network scripts on the production VPS.
- Old Docker images and rollback containers are retained, with disk consumption and manual cleanup requiring documented operational procedure.
- Do not merge into `main`, publish a GitHub Release, post an upstream solution claim or deploy to the VPS without explicit approval.
- Keep MIT license and upstream attribution.

## Acceptance checklist

- [x] Original POSIX build failure corrected and CI verified.
- [x] Pinned Telemt 3.5.16 build, smoke, real-Docker and synthetic HAProxy integration green at `06d88bf`.
- [x] Group upgrade and selected rollback paths exercised with primary and secondary instances on disposable runner.
- [x] Group-upgrade lock and lock-contention refusal implemented and tested; cross-command locking remains limited.
- [x] Bounded TCP reachability gates tested for primary and secondary; true client/production HAProxy acceptance remains open.
- [x] Partial rollback evidence/manifest and refusal of another upgrade on unresolved state tested.
- [ ] Arbitrary interruption recovery and operator procedure validated outside CI.
- [ ] B4 actual Telegram traffic and real deployment topology separately accepted or explicitly excluded from release claims.
- [ ] B5 immutable release provenance, integrity verification and installer documentation reviewed.
- [ ] Release notes and instructions reviewed against final code.
- [ ] Owner explicitly authorizes public publication.
- [ ] Owner separately authorizes any production deployment.

**Decision:** Remain Draft. No production changes. The evidence is sufficient for continued development testing, not for public production-ready release claims.

## Independent source verification

The manager file `mtproxymax.sh` has SHA-256 `aa527da3314d29ec9ed5e59ca09a1e0c96d1fd5db397c5f705c4831cce1abf7e`, verified in [GitHub Actions run 42219216246](https://github.com/Krezi-777/MTProxyMax/actions/runs/42219216246). The isolated runner checked `sha256sum` for both checked-out content and an immutable raw GitHub HTTPS download, plus byte equality and `bash -n`. This does not prove code security, artifact signing, clean installation or Telegram connectivity. Installer and future package digest acceptance remain open.

## Stage 19 documentation and provenance status

- [Release candidate overview](RELEASE_CANDIDATE.md) is a **draft page in the development branch**, not a published GitHub Release.
- [Conservative group upgrade recovery runbook](GROUP_UPGRADE_RECOVERY_RUNBOOK.md) documents read-only evidence gathering, staged reconciliation and the manual-recovery limitation.
- The manager file digest is independently verified on an immutable source revision. The branch still has no designated final release tag, approved installer/package digest or public install command. The documentation commits themselves must pass CI before any release review.
- **Decision:** Stage 19 preparation is in progress. Keep PR Draft, no publish, no main merge, no production upgrade.
