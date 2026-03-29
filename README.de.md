# Mailbox Mirror

Mailbox Mirror baut ein Docker-Image auf Basis von `gilleslamiral/imapsync`, das `imapsync` per Cron zyklisch ausführt. Da `imapsync` standardmäßig inkrementell arbeitet, werden bei jedem Lauf nur neue/fehlende E-Mails synchronisiert.

## Wann dieses Projekt sinnvoll ist

Ein typischer Usecase ist der Wegfall von Gmailify bzw. dem POP-Abruf externer Postfächer in Gmail: Dieses Projekt kann Mails aus einem externen IMAP-Postfach fortlaufend in ein Gmail-Postfach spiegeln, damit neue Nachrichten weiterhin in Gmail ankommen.

Wichtig: Wenn dein Mail-Provider eine einfache serverseitige Weiterleitung an Gmail anbietet, ist diese Lösung klar zu bevorzugen. Eine Weiterleitung ist einfacher, ressourcenschonender und robuster als ein eigener `imapsync`-Container. `Mailbox Mirror` ist vor allem dann sinnvoll, wenn keine Weiterleitung verfügbar ist oder wenn du bewusst eine selbst gehostete IMAP-zu-IMAP-Synchronisierung brauchst.

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

## Drei Yahoo-Postfächer mit wenig RAM

Für drei Yahoo-Postfächer, die in ein Gmail-Postfach gespiegelt werden sollen, gibt es jetzt ein Compose-Beispiel mit gestaffelten Sync-Zeiten und einem gemeinsamen Lock:

1. `.env.mailbox-a.example`, `.env.mailbox-b.example` und `.env.mailbox-c.example` jeweils nach `.env.mailbox-a`, `.env.mailbox-b` und `.env.mailbox-c` kopieren.
2. Zugangsdaten eintragen.
3. Multi-Mailbox-Compose starten:

```bash
docker compose -f docker-compose.multi-mailbox.yml up -d
```

Das Beispiel setzt:

- `RUN_ON_STARTUP=false`, damit ein Container-Neustart keinen dreifachen Initial-Sync auslöst
- gestaffelte Cron-Schedules im Abstand von 5 Minuten
- `FOLDER_FILTER=INBOX`, um nur neue Inbox-Mails zu spiegeln
- `LOCK_FILE=/var/lock/mailbox-mirror/global.lock` auf einem gemeinsamen Docker-Volume, damit über alle drei Container hinweg immer nur ein `imapsync`-Prozess gleichzeitig läuft

Wenn du nur aktuelle Mails nachziehen willst und ältere Ordner nicht mehr regelmäßig prüfen musst, kannst du zusätzlich in den mailbox-spezifischen `.env`-Dateien `MAXAGE_DAYS=30` setzen.

Eine Docker-Speichergrenze wie `mem_limit: 256m` ist im Compose-Beispiel vorbereitet, sollte aber erst nach einem erfolgreichen Test ohne Limit aktiviert werden.

## Wichtige Environment-Variablen

- `HOST1`, `USER1`, `PASSWORD1`: Quell-Postfach
- `HOST2`, `USER2`, `PASSWORD2`: Ziel-Postfach
- `CRON_SCHEDULE`: Cron-Ausführungsintervall (Default: alle 5 Minuten)
- `RUN_ON_STARTUP`: `true|false` für direkten ersten Sync beim Start
- `DRY_RUN`: `true|false` für einen sicheren Testlauf mit `imapsync --dry`
- `LOCK_FILE`: optionaler Pfad für `flock`; mit gemeinsamem Volume können mehrere Container einen globalen Sync-Lock teilen
- `MAX_LOG_SIZE_MB`: rotiert `imapsync.log` bei Erreichen der Größe nach `imapsync.log.1` (Default: 10 MB)
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
