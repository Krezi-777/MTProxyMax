# DRAFT ONLY — Unofficial MTProxyMax / Telemt 3.5.16 POSIX build fix

> **NOT RELEASED. NOT APPROVED FOR PRODUCTION.** This is a development candidate from an independent fork, not an official SamNet-dev release.

## Purpose

Addresses the shell compatibility failure discussed in [upstream issue #162](https://github.com/SamNet-dev/MTProxyMax/issues/162). The manager-generated Dockerfile used Bash-only substring expansion in a POSIX `/bin/sh` build step; the corrected approach is POSIX-compatible. Engine source is pinned to Telemt 3.5.16 commit `84e5b82`.

## Changes under development

- POSIX-compatible source build and guarded image-build failure handling.
- Immutable-commit + SHA-256 verification for opt-in fork installs / manager self-update.
- Protected primary Docker container replacement, backup config recovery and preservation of old images and stopped rollback containers.
- Host-network secondary Control API port collision avoidance.
- Sequential update of running enabled secondary instances and group rollback attempts if a secondary update fails.
- Stability probes using container identity and Docker restart counter.
- Regression tests across Linux distributions, isolated Docker, Telemt smoke and Telemt + HAProxy integration.

## Verification

For source commit `06d88bf0d093b926cbcd48e9d0e27d27bfee542a`, GitHub Actions reports **SUCCESS** for all four workflow groups:

| Workflow | Run |
| --- | --- |
| CI | [42201261539](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261539) |
| Full Stack Integration | [42201261534](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261534) |
| Real Docker Rollback | [42201261676](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261676) |
| Telemt Smoke | [42201261589](https://github.com/Krezi-777/MTProxyMax/actions/runs/42201261589) |

The full-stack test uses genuine manager functions and host-network Docker on a disposable GitHub runner, but stubs side-effectful host management helpers. It checks primary HAProxy backend health and primary/secondary TCP listeners and injects failure into secondary upgrade and rollback. It does **not** prove real Telegram client traffic, every HAProxy backend in the actual target topology or complete recovery from every interruption.

## Unresolved safety / release gates

- No shared transaction lock against concurrent updates or instance changes.
- Readiness checks inside group update rely mainly on Docker status and restart-count stability rather than per-instance end-to-end traffic acceptance.
- Partial rollback and crash interruption recovery are not fully reconciled automatically.
- Actual production Telegram client traffic and HAProxy layout remain unverified.
- Reviewed immutable public release tag, source checksum, install instructions and artifact provenance are not finalized.

See [release readiness audit](RELEASE_READINESS_AUDIT.md).

## Distribution and attribution

No public production-ready installation command is supplied. Any future release must designate and review an immutable commit and verifiable digest, preserve the MIT license and upstream credit, and state that the fork is unofficial.

**Release status:** BLOCKED; Draft PR only. No merge into `main`, no publication and no change to production VPS Telemt 3.5.14 without separate explicit authorization.
