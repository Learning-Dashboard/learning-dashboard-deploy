#!/usr/bin/env bash
# Entrypoint wrapper: wait until PostgreSQL and MongoDB accept TCP connections
# before starting Tomcat.
#
# Why: the ROOT.war fails to deploy (and Tomcat keeps running, serving 404) if the
# database is not reachable at startup. `depends_on` only helps for `docker compose up`;
# the Docker restart policy (daemon restart, host reboot) starts all containers at once.
#
# If the databases do not show up in time we exit non-zero so the restart policy
# retries with back-off instead of leaving a half-dead Tomcat around.

set -u

DB_WAIT_HOST="${DB_WAIT_HOST:-db}"
DB_WAIT_PORT="${DB_WAIT_PORT:-5432}"
MONGO_WAIT_HOST="${MONGO_WAIT_HOST:-mongodb}"
MONGO_WAIT_PORT="${MONGO_WAIT_PORT:-27017}"
WAIT_TRIES="${WAIT_TRIES:-150}"   # 150 x 2s = 5 minutes

wait_tcp() {
  local host="$1" port="$2" i
  for ((i = 1; i <= WAIT_TRIES; i++)); do
    if (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null; then
      echo "[wait-for-db] ${host}:${port} is reachable"
      return 0
    fi
    echo "[wait-for-db] waiting for ${host}:${port} (${i}/${WAIT_TRIES})"
    sleep 2
  done
  echo "[wait-for-db] ${host}:${port} not reachable after ${WAIT_TRIES} tries, exiting so Docker retries" >&2
  return 1
}

wait_tcp "$DB_WAIT_HOST" "$DB_WAIT_PORT" || exit 1
wait_tcp "$MONGO_WAIT_HOST" "$MONGO_WAIT_PORT" || exit 1

# Give Postgres a moment to finish crash recovery after the port opens.
sleep 3

exec "$@"
