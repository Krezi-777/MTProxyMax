# Release readiness audit — unofficial MTProxyMax Telemt 3.5.16 fork

**Audit date:** 2026-11-06  
**Repository:** [Krezi-777/MTProxyMax](https://github.com/Krezi-777/MTProxyMax)  
**Candidate branch:** `fix/telemt-posix-build`  
**Last fully green audited code commit:** `06d88bf0d093b926cbcd48e9d0e27d27bfee542a`  
**Status:** **BLOCKED — NOT APPROVED FOR PUBLIC RELEASE OR PRODUCTION**

This is an independent, unofficial fork, not an upstream SamNet-dev release. Production VPS / Telemt 3.5.14 was not accessed.

## Evidence: latest green runs

| Workflow | GitHub Actions run | Result |
| --- | --- | --- |
| Multi-distribution CI | [42201261539](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261539) | SUCCESS |
| Telemt Smoke Test | [42201261589](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261589) | SUCCESS |
| Real Docker Rollback | [42201261676](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261676) | SUCCESS |
| Full Stack Integration | [42201261534](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261534) | SUCCESS |

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

**B1 — Concurrent operation safety: OPEN.** Group upgrade does not acquire a shared lock preventing concurrent update/restart/instance mutation. Races over container names, configuration files and rollback snapshots remain possible. The workflow must include a tested locking and interruption/recovery policy.

**B2 — Reachability acceptance: OPEN.** Production group-upgrade acceptance depends on Docker status/unchanged restart count for six seconds and does not independently validate every secondary listener or all HAProxy backends inside the function. Runner integration probes both TCP ports, but the implementation lacks equivalent gated verification.

**B3 — Partial rollback / crash recovery: OPEN.** An intentionally failed rollback leaves old Docker objects/snapshots and reports an error; there is no validated automatic continuation/reconciliation after an interruption or partial rollback. Some preflight failures return without cleaning snapshots. Recovery must never remove the only viable original container.

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
- [ ] B1 concurrency lock and interruption policy implemented and tested.
- [ ] B2 reliable per-instance reachability/HAProxy acceptance gates implemented and tested.
- [ ] B3 partial rollback reconciliation and failure evidence validated.
- [ ] B4 actual Telegram traffic and real deployment topology separately accepted or explicitly excluded from release claims.
- [ ] B5 immutable release provenance, integrity verification and installer documentation reviewed.
- [ ] Release notes and instructions reviewed against final code.
- [ ] Owner explicitly authorizes public publication.
- [ ] Owner separately authorizes any production deployment.

**Decision:** Remain Draft. No production changes. The evidence is sufficient for continued development testing, not for public production-ready release claims.
