#!/usr/bin/env bash
# =============================================================================
# ld-watchdog.sh - keep the Learning Dashboard stack alive on a (rootless) Docker host
# =============================================================================
#
# What it does, every run:
#   1. If the Docker daemon is not reachable, asks systemd --user to start it.
#   2. Looks for container processes (postgres, mongod, java, gunicorn, nginx)
#      that are still running but that Docker no longer knows about. This happens
#      when the rootless daemon restarts/crashes: the shims die, the containers
#      keep running as orphans, and a fresh `mongod`/`postgres` cannot start on the
#      same volume (lock held / two postmasters on one data dir -> corruption).
#      Orphans are stopped cleanly (SIGINT for postgres, SIGTERM otherwise).
#   3. Only when no orphan is left, runs `docker compose up -d` so that every
#      service is running again (idempotent; starts what is stopped, leaves the
#      rest untouched).
#
# Safety: only processes owned by this user or by this user's subordinate UID
# range (/etc/subuid, i.e. processes started by this user's rootless Docker) are
# ever considered. Nothing else on the host is touched.
#
# Install (no sudo needed), in `crontab -e`:
#
#   */5 * * * *  /path/to/learning-dashboard-deploy/scripts/ld-watchdog.sh >> $HOME/ld-watchdog.log 2>&1
#   @reboot      sleep 90 && /path/to/learning-dashboard-deploy/scripts/ld-watchdog.sh >> $HOME/ld-watchdog.log 2>&1
#
# Environment overrides:
#   COMPOSE_DIR        directory with docker-compose.yml (default: parent of this script)
#   COMPOSE_PROFILES   compose profiles to bring up (default: admin)
#   WATCHDOG_DRY_RUN=1 only report, do not kill or start anything
# =============================================================================

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_DIR="${COMPOSE_DIR:-$(dirname "$SCRIPT_DIR")}"
COMPOSE_PROFILES="${COMPOSE_PROFILES:-admin}"
DRY_RUN="${WATCHDOG_DRY_RUN:-0}"
LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/ld-watchdog.lock"
ORPHAN_WAIT_SECONDS=90

# Process names that belong to the stack's containers.
STACK_PROCS=(postgres mongod java gunicorn nginx)

log() { printf '%s %s\n' "$(date '+%F %T')" "$*"; }

# One instance at a time.
if ! { exec 9>"$LOCK_FILE"; } 2>/dev/null; then
  LOCK_FILE="/tmp/ld-watchdog-${USER:-$(id -u)}.lock"
  exec 9>"$LOCK_FILE" || { log "ERROR: cannot create lock file $LOCK_FILE"; exit 1; }
fi
if ! flock -n 9; then
  exit 0
fi

export COMPOSE_PROFILES
cd "$COMPOSE_DIR" || { log "ERROR: cannot cd to $COMPOSE_DIR"; exit 1; }

MY_UID="$(id -u)"
MY_USER="$(id -un)"
# Subordinate UID range of this user (used by rootless Docker to map container UIDs).
read -r SUBUID_BASE SUBUID_COUNT < <(awk -F: -v u="$MY_USER" '$1==u {print $2, $3; exit}' /etc/subuid 2>/dev/null)
SUBUID_BASE="${SUBUID_BASE:-0}"
SUBUID_COUNT="${SUBUID_COUNT:-0}"

# ---------------------------------------------------------------------------
# 1. Daemon reachable?
# ---------------------------------------------------------------------------
if ! docker info >/dev/null 2>&1; then
  log "docker daemon not reachable"
  if [ "$DRY_RUN" = "1" ]; then exit 0; fi
  if command -v systemctl >/dev/null 2>&1; then
    log "trying: systemctl --user start docker"
    systemctl --user start docker 2>/dev/null || true
  fi
  # Give it time; the next cron run will continue.
  exit 0
fi

# ---------------------------------------------------------------------------
# 2. Detect orphaned container processes
# ---------------------------------------------------------------------------
proc_uid()  { awk '/^Uid:/  {print $2; exit}' "/proc/$1/status" 2>/dev/null; }
proc_ppid() { awk '/^PPid:/ {print $2; exit}' "/proc/$1/status" 2>/dev/null; }
proc_name() { cat "/proc/$1/comm" 2>/dev/null; }

uid_is_ours() {
  local uid="$1"
  [ "$uid" = "$MY_UID" ] && return 0
  [ "$SUBUID_COUNT" -gt 0 ] && [ "$uid" -ge "$SUBUID_BASE" ] && [ "$uid" -lt $((SUBUID_BASE + SUBUID_COUNT)) ] && return 0
  return 1
}

# PIDs (host view) of every container Docker currently believes is running.
KNOWN_PIDS=" $(docker ps -q | xargs -r docker inspect -f '{{.State.Pid}}' 2>/dev/null | tr '\n' ' ') "

descends_from_known() {
  local p="$1" depth=0
  while [ -n "$p" ] && [ "$p" -gt 1 ] && [ "$depth" -lt 64 ]; do
    case "$KNOWN_PIDS" in *" $p "*) return 0 ;; esac
    p="$(proc_ppid "$p")"
    depth=$((depth + 1))
  done
  return 1
}

# Candidates: stack process names, owned by us (directly or via subuid), not under a known container.
CANDIDATES=()
for name in "${STACK_PROCS[@]}"; do
  for pid in $(pgrep -x "$name" 2>/dev/null); do
    uid="$(proc_uid "$pid")"
    [ -n "$uid" ] || continue
    uid_is_ours "$uid" || continue
    descends_from_known "$pid" && continue
    CANDIDATES+=("$pid")
  done
done

# Keep only top-level orphans (e.g. the postmaster, not its workers).
ORPHANS=()
for pid in "${CANDIDATES[@]:-}"; do
  [ -n "$pid" ] || continue
  ppid="$(proc_ppid "$pid")"
  is_child=0
  for other in "${CANDIDATES[@]}"; do
    [ "$ppid" = "$other" ] && { is_child=1; break; }
  done
  [ "$is_child" = "0" ] && ORPHANS+=("$pid")
done

signal_orphan() {
  # $1 = pid, $2 = signal name. Processes mapped through subuid cannot be
  # signalled directly by this user; we signal them from a throwaway container
  # running as the matching in-container UID (kill permission is UID-based).
  local pid="$1" sig="$2" uid cuid
  uid="$(proc_uid "$pid")"
  [ -n "$uid" ] || return 0
  if [ "$uid" = "$MY_UID" ]; then
    kill "-$sig" "$pid" 2>/dev/null
  else
    cuid=$((uid - SUBUID_BASE + 1))
    docker run --rm --pid=host --user "$cuid" alpine kill "-$sig" "$pid" >/dev/null 2>&1
  fi
}

if [ "${#ORPHANS[@]}" -gt 0 ]; then
  for pid in "${ORPHANS[@]}"; do
    log "orphan container process: pid=$pid uid=$(proc_uid "$pid") name=$(proc_name "$pid")"
  done

  if [ "$DRY_RUN" = "1" ]; then
    log "dry run: not stopping orphans, not starting the stack"
    exit 0
  fi

  for pid in "${ORPHANS[@]}"; do
    case "$(proc_name "$pid")" in
      postgres) sig=INT ;;   # fast shutdown: checkpoint + exit
      *)        sig=TERM ;;
    esac
    log "sending SIG$sig to orphan pid=$pid"
    signal_orphan "$pid" "$sig"
  done

  waited=0
  while [ "$waited" -lt "$ORPHAN_WAIT_SECONDS" ]; do
    alive=0
    for pid in "${ORPHANS[@]}"; do
      [ -d "/proc/$pid" ] && alive=1
    done
    [ "$alive" = "0" ] && break
    sleep 5
    waited=$((waited + 5))
  done

  still=()
  for pid in "${ORPHANS[@]}"; do
    [ -d "/proc/$pid" ] && still+=("$pid")
  done
  if [ "${#still[@]}" -gt 0 ]; then
    log "ERROR: orphans still alive after ${ORPHAN_WAIT_SECONDS}s: ${still[*]} - NOT starting the stack (would risk two postmasters on one volume). Host reboot may be required."
    exit 1
  fi
  log "all orphans stopped cleanly"
fi

# ---------------------------------------------------------------------------
# 3. Make sure everything is up
# ---------------------------------------------------------------------------
if [ "$DRY_RUN" = "1" ]; then
  docker compose ps --format '{{.Name}}\t{{.Status}}' 2>/dev/null
  exit 0
fi

# Avoid noisy logs: only call `up` if something is not running.
NOT_RUNNING="$(docker compose ps -a --format '{{.Name}}\t{{.State}}' 2>/dev/null | awk -F'\t' '$2!="running"')"
EXPECTED="$(docker compose config --services 2>/dev/null | wc -l)"
RUNNING="$(docker compose ps --status running -q 2>/dev/null | wc -l)"

if [ -n "$NOT_RUNNING" ] || [ "$RUNNING" -lt "$EXPECTED" ]; then
  [ -n "$NOT_RUNNING" ] && log "not running:"$'\n'"$NOT_RUNNING"
  log "running: docker compose up -d (profiles: $COMPOSE_PROFILES)"
  docker network inspect ld-taiga >/dev/null 2>&1 || docker network create ld-taiga >/dev/null 2>&1 || true
  docker compose up -d 2>&1 | sed 's/^/    /'
fi

exit 0
