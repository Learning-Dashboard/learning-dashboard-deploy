#!/usr/bin/env bash
# Source this from cron jobs that talk to rootless Docker.
# Cron does not load .bashrc, so DOCKER_HOST / XDG_RUNTIME_DIR / the session bus
# are missing and `docker` looks for /var/run/docker.sock (which does not exist).

_uid="$(id -u)"
export PATH="${HOME}/bin:/usr/local/bin:/usr/bin:/bin:${PATH:-}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${_uid}}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
if [ -z "${DOCKER_HOST:-}" ] && [ -S "${XDG_RUNTIME_DIR}/docker.sock" ]; then
  export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/docker.sock"
fi
