# Recovery runbook — group engine upgrade (DRAFT; isolated test environments)

**Scope:** Experimental fork `Krezi-777/MTProxyMax`, Telemt 3.5.16 candidate.  
**Status:** Reviewed recovery *procedure*, not a verified automated crash-recovery tool.  
**Restrictions:** Do not perform these actions on the production VPS without a separate change authorization, complete backup and maintenance window. Never delete a rollback container or the only copy of a configuration.

## How a protected group upgrade works

The group update holds an exclusive `flock` on `$INSTALL_DIR/.engine-group-upgrade.lock` for its invocation. Before the primary upgrade it creates `$CONFIG_DIR/.group-rollback.XXXXXX/` and a `RECOVERY.txt` manifest containing original container IDs. The directory contains `primary.toml` and snapshots of the enabled, running secondary instances included in that update. Old containers are normally renamed to `<name>-rollback-<timestamp>-<pid>`; the replacement takes the original name. If rollback is incomplete or interrupted, snapshots are intentionally retained, and a subsequent group upgrade is refused while such a directory remains.

**Important limitations:** The lock is held by the upgrade invocation only, not by every ordinary instance-management command. The manifest is a recovery hint, not a guaranteed durable transaction journal; for example, a crash between an individual Docker rename and its log update may require discovery via Docker ID. Docker `RestartPolicy`, network mode and image must be inspected, not assumed. Docker container ID is preserved only if the *original container* is renamed back; recreating a container produces a different ID. The smoke/integration tests do not establish real Telegram client connectivity.

## Recovery decision sequence

1. **Freeze changes.** Stop scheduling upgrades and prevent other operators/automation from modifying the same containers. A live upgrade may still hold the flock: do not race it. Do not manually remove lock files; existence of a file does not establish whether a process holds its lock.
2. **Capture evidence without mutation.** Record timestamps, the exact script revision, `docker ps -a --no-trunc`, Docker ID, name, image, state, restart count and restart policy for the primary and each known secondary. Copy `RECOVERY.txt` plus `*.toml` snapshots to a separate secured directory; configurations may contain secrets.
3. **Locate original containers by immutable Docker ID.** For each `primary_id` or `original_id` from `RECOVERY.txt`, use `docker inspect <id>` to find its *current* name and state. Search stopped and renamed containers as well. If the ID is missing, **stop**: do not guess which container is the original or delete any replacement.
4. **Compare the desired and actual state.** For every instance, identify its pre-upgrade Docker ID, snapshot TOML, pre-upgrade image and restart policy (from inspection/history). Note which replacement currently owns the original name. Inspect the real HAProxy configuration and listeners separately.
5. **Choose a recovery plan case by case.** Only after verifying all original IDs, preserving current replacement containers and confirming the maintenance window may an operator restore snapshot TOML and rename/start original containers. There is deliberately no blind one-line recovery command: partial failures differ, and generic `docker rm -f` could destroy the only viable instance.
6. **Validate restored service.** Verify expected Docker IDs, images, restart policies, config hashes, stable process state, TCP listeners, HAProxy backend health and, where authorized, real client connectivity. A successful TCP handshake alone is not proof of MTProto traffic.
7. **Close the incident explicitly.** Record the evidence and restoration outcome. Only after verifying all instances and retaining a separate evidence copy should an operator archive or remove the unresolved `.group-rollback.*` transaction directory; its existence intentionally blocks new group upgrades.

## Read-only evidence commands (adapt paths and names)

```bash
# Substitute the actual existing paths after inspecting the installation.
docker ps -a --no-trunc
docker inspect --format '{{.Id}} {{.Name}} {{.Config.Image}} {{.State.Status}} {{.RestartCount}} {{.HostConfig.RestartPolicy.Name}}' <actual-container-name-or-id>

# Read the transaction manifest and snapshot directory without changing them.
cat '<actual-CONFIG_DIR>/.group-rollback.<actual-suffix>/RECOVERY.txt'
sha256sum '<actual-CONFIG_DIR>/.group-rollback.<actual-suffix>/'*.toml
```

The placeholders above must be replaced with verified values. Do **not** paste the angle-bracket placeholders literally into a terminal. The `RECOVERY.txt` may lack an entry for an interrupted individual operation: reconcile it with `docker ps -a` and the old IDs.

## Tested versus untested

- **Tested on disposable GitHub Runner:** successful primary and secondary update, injected secondary launch failure, restoration of selected Docker IDs/configs/restart policies, TCP readiness, lock-contention refusal, injected rollback failure with retained snapshots, and refusal to upgrade while unresolved snapshots remain.
- **Not yet accepted:** a process killed at every interruption boundary, fully automatic crash reconciliation, production config, production HAProxy, real Telegram client traffic, cross-command locking and restoration after permanent loss of an original Docker container.

## Release acceptance gate

This document supports operator diagnosis; it does not authorize production deployment or make incomplete rollback automatically recoverable. Keep PR Draft, no GitHub Release or deployment pending separate review and explicit authorization.
