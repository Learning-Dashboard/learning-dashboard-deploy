#!/usr/bin/env bash
# Daily dumps of Postgres and Mongo. Safe to run from cron (sets rootless Docker env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ld-cron-env.sh
. "${SCRIPT_DIR}/ld-cron-env.sh"

BACKUP_DIR="${BACKUP_DIR:-${HOME}/backups}"
KEEP_DAYS="${KEEP_DAYS:-14}"
STAMP="$(date +%F)"

mkdir -p "$BACKUP_DIR"

if ! timeout 60 docker info >/dev/null 2>&1; then
  echo "$(date '+%F %T') ERROR: docker not reachable (DOCKER_HOST=${DOCKER_HOST:-unset})" >&2
  exit 1
fi

docker exec qrapids_postgres pg_dumpall -U postgres | gzip > "${BACKUP_DIR}/pg_${STAMP}.sql.gz"
docker exec ingest_mongodb sh -c 'mongodump -u admin -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin --archive --gzip' > "${BACKUP_DIR}/mongo_${STAMP}.archive.gz"
find "$BACKUP_DIR" -type f -mtime "+${KEEP_DAYS}" -delete

echo "$(date '+%F %T') backups written to ${BACKUP_DIR} (pg_${STAMP}.sql.gz, mongo_${STAMP}.archive.gz)"
