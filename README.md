# Mailbox Mirror

Mailbox Mirror baut ein Docker-Image auf Basis von `gilleslamiral/imapsync`, das `imapsync` per Cron zyklisch ausführt. Da `imapsync` standardmäßig inkrementell arbeitet, werden bei jedem Lauf nur neue/fehlende E-Mails synchronisiert.

## Was enthalten ist

- `Dockerfile` auf Basis `gilleslamiral/imapsync:latest`
- `docker/entrypoint.sh` für Cron-Setup + optionalen Initiallauf
- `docker/run-imapsync.sh` für den eigentlichen Sync-Lauf
- `docker/cron-runner.sh` lädt Container-Environment für Cron
- `.github/workflows/docker-build.yml` für den CI-Build
- `docker-compose.yml` als Compose-Beispiel

## Lokaler Build

```bash
docker build -t mailbox-mirror-imapsync:local .
```

## Starten des Containers

1. Variablen aus `.env.example` übernehmen und anpassen.
2. Container starten:

```bash
docker run --rm --name mailbox-mirror --env-file .env mailbox-mirror-imapsync:local
```

## Docker Compose Beispiel

1. `.env.example` nach `.env` kopieren und Werte anpassen.
2. Compose-Datei nutzen:

```bash
docker compose -f docker-compose.yml up -d
```

## Wichtige Environment-Variablen

- `HOST1`, `USER1`, `PASSWORD1`: Quell-Postfach
- `HOST2`, `USER2`, `PASSWORD2`: Ziel-Postfach
- `CRON_SCHEDULE`: Cron-Ausführungsintervall (Default: alle 5 Minuten)
- `RUN_ON_STARTUP`: `true|false` für direkten ersten Sync beim Start
- `DRY_RUN`: `true|false` für einen sicheren Testlauf mit `imapsync --dry`
- `MAX_LOG_SIZE_MB`: rotiert `imapsync.log` bei Erreichen der Größe nach `imapsync.log.1`
- `HEALTHCHECK_MAX_AGE_MINUTES`: optionales Alterslimit für den letzten erfolgreichen Sync
- `IMAPSYNC_EXTRA_ARGS`: optionale zusätzliche imapsync-Argumente

Beim Container-Start werden Pflichtvariablen und das Cron-Format früh validiert, damit Konfigurationsfehler sofort auffallen.

## Betrieb

Das Image enthält einen Docker-`HEALTHCHECK`. Standardmäßig gilt der Container als gesund, wenn Cron läuft und der letzte Sync-Versuch nicht auf `failure` steht. Mit `HEALTHCHECK_MAX_AGE_MINUTES` kannst du zusätzlich erzwingen, dass ein erfolgreicher Sync nicht zu alt sein darf.

## Smoke Test

Für einen sicheren Ersttest kannst du `DRY_RUN=true` setzen und den Container einmal starten:

```bash
docker run --rm --name mailbox-mirror --env-file .env -e DRY_RUN=true mailbox-mirror-imapsync:local
```

Ein erfolgreicher Testlauf endet mit `imapsync finished successfully.` im Log, ohne dass E-Mails geschrieben werden.

## GitHub Actions

Workflow: `.github/workflows/docker-build.yml`

Trigger:
- Pull Requests
- Push auf `main`
- Manueller Start (`workflow_dispatch`)

Der Workflow baut das Docker-Image via Buildx. Auf `main` wird zusätzlich nach GHCR (`ghcr.io/<owner>/<repo>`) gepusht; bei Pull Requests wird nur gebaut.
