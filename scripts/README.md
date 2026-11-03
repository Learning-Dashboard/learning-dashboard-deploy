# scripts/

Operació de l’stack Learning Dashboard en un host **Docker rootless**, sense sudo. Cron no carrega `.bashrc`, així que cap d’aquests scripts depèn de l’entorn del shell interactiu: reconstruixen `DOCKER_HOST` i el bus de sessió ells mateixos.

Plantilla de crontab: [`crontab.example`](crontab.example). Ajusta `LD` al camí real del repositori i enganxa-la amb `crontab -e`.

## `ld-cron-env.sh`

No s’executa sol: el fan servir (`source`) els altres scripts.

Posa:

- `XDG_RUNTIME_DIR` → `/run/user/<uid>`
- `DBUS_SESSION_BUS_ADDRESS` (cal per a `systemctl --user`)
- `DOCKER_HOST=unix:///run/user/<uid>/docker.sock` si el socket existeix

Sense això, `docker` busca `/var/run/docker.sock`, falla, i les tasques de cron acaben amb dumps de 0 bytes i un watchdog que només escriu `docker daemon not reachable`.

## `ld-watchdog.sh`

Es llança cada 5 minuts (i a `@reboot`). Cada execució:

1. Comprova que el daemon respon (`docker info`, timeout 60 s). Si la unitat systemd està parada, fa `systemctl --user start docker`. Si està `active` però no respon, la deixa: està penjat per pressió de memòria, no mort.
2. Cerca processos `postgres` / `mongod` / `java` / `gunicorn` / `nginx` d’aquest usuari (o del seu rang de subuid) que Docker ja no controla. Són **orfes**: el daemon ha caigut, els shims han mort i els processos han quedat vius amb el volum de dades obert. Els atura net (`SIGINT` a Postgres, `SIGTERM` a la resta) i espera fins a 90 s.
3. Només si no queda cap orfe, fa `docker compose up -d` (perfil `admin`) perquè tot el que estigui parat torni a arrencar. Si un orfe no mor, **no** aixeca l’stack: dos `postgres` sobre el mateix volum corrompen les dades.

Només toca processos d’aquest usuari. Un sol exemplar alhora (lock). El log (`~/ld-watchdog.log`) està buit si tot va bé; només escriu quan actua.

```bash
# Prova sense tocar res (com si fos cron: entorn buit)
WATCHDOG_DRY_RUN=1 env -i HOME=$HOME PATH=/usr/bin:/bin bash scripts/ld-watchdog.sh
```

Variables opcionals: `COMPOSE_DIR`, `COMPOSE_PROFILES` (per defecte `admin`), `WATCHDOG_DRY_RUN=1`.

## `ld-backup.sh`

Dump diari de Postgres (`pg_dumpall`) i Mongo (`mongodump --archive --gzip`) als contenidors `qrapids_postgres` i `ingest_mongodb`. Esborra fitxers de més de 14 dies.

```bash
bash scripts/ld-backup.sh
ls -lh ~/backups
```

`pg_YYYY-MM-DD.sql.gz` ha de ser de l’ordre de MB, no 20 bytes (gzip buit). `mongo_YYYY-MM-DD.archive.gz` no ha de ser 0 bytes.

Variables opcionals: `BACKUP_DIR` (per defecte `$HOME/backups`), `KEEP_DAYS` (per defecte `14`).

## Relació amb la resta de l’stack

Aquests scripts no substitueixen:

- `restart: unless-stopped` als serveis del `docker-compose.yml` (reinici si el procés mor)
- el contenidor `autoheal` (reinici si el healthcheck diu `unhealthy`; cal `DOCKER_SOCK=/run/user/<uid>/docker.sock` al `.env`)
- `wait-for-db.sh` a la imatge de Tomcat (espera Postgres i Mongo abans de desplegar el WAR)

El watchdog és la xarxa de seguretat per al cas que el daemon rootless caigui i deixi orfes, cosa que les altres peces no veuen.
