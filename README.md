# Mailbox Mirror

Mailbox Mirror builds a Docker image based on `gilleslamiral/imapsync` and runs `imapsync` on a recurring cron schedule. Since `imapsync` works incrementally by default, each run only synchronizes new or missing emails.

## When This Project Makes Sense

A typical use case is the shutdown of Gmailify or Gmail's POP fetching for external mailboxes: this project can continuously mirror emails from an external IMAP mailbox into a Gmail mailbox so new messages still arrive in Gmail.

Important: if your mail provider offers simple server-side forwarding to Gmail, that option should be preferred. Forwarding is simpler, more resource-efficient, and more robust than running your own `imapsync` container. `Mailbox Mirror` is mainly useful when forwarding is not available or when you explicitly want a self-hosted IMAP-to-IMAP sync.

## What's Included

- `Dockerfile` based on `gilleslamiral/imapsync:latest`
- `docker/entrypoint.sh` for cron setup and an optional initial run
- `docker/run-imapsync.sh` for the actual sync job
- `docker/cron-runner.sh` to load the container environment for cron
- `.github/workflows/docker-build.yml` for the CI image build
- `docker-compose.yml` as a Compose example

## Local Build

```bash
docker build -t mailbox-mirror-imapsync:local .
```

## Start the Container

1. Copy the variables from `.env.example` and adjust them.
2. Start the container:

```bash
docker run --rm --name mailbox-mirror --env-file .env mailbox-mirror-imapsync:local
```

## Docker Compose Example

1. Copy `.env.example` to `.env` and adjust the values.
2. Use the Compose file:

```bash
docker compose -f docker-compose.yml up -d
```

## Three Yahoo Mailboxes With Low RAM Usage

For three Yahoo mailboxes that should be mirrored into a Gmail mailbox, there is now a Compose example with staggered sync times and a shared lock:

1. Copy `.env.mailbox-a.example`, `.env.mailbox-b.example`, and `.env.mailbox-c.example` to `.env.mailbox-a`, `.env.mailbox-b`, and `.env.mailbox-c`.
2. Fill in the credentials.
3. Start the multi-mailbox Compose stack:

```bash
docker compose -f docker-compose.multi-mailbox.yml up -d
```

The example uses:

- `RUN_ON_STARTUP=false` so a container restart does not trigger a triple initial sync
- staggered cron schedules with 5-minute offsets
- `FOLDER_FILTER=INBOX` to mirror only new inbox mail
- `LOCK_FILE=/var/lock/mailbox-mirror/global.lock` on a shared Docker volume so only one `imapsync` process runs across all three containers at a time

If you only want to catch up recent mail and do not need to re-check older folders regularly, you can also set `MAXAGE_DAYS=30` in the mailbox-specific `.env` files.

A Docker memory limit like `mem_limit: 256m` is prepared in the Compose example, but it should only be enabled after a successful test run without a limit.

## Important Environment Variables

- `HOST1`, `USER1`, `PASSWORD1`: source mailbox
- `HOST2`, `USER2`, `PASSWORD2`: destination mailbox
- `CRON_SCHEDULE`: cron interval for execution (default: every 5 minutes)
- `RUN_ON_STARTUP`: `true|false` to run an immediate first sync on startup
- `DRY_RUN`: `true|false` for a safe test run with `imapsync --dry`
- `LOCK_FILE`: optional path for `flock`; with a shared volume, multiple containers can use one global sync lock
- `MAX_LOG_SIZE_MB`: rotates `imapsync.log` to `imapsync.log.1` once it reaches the configured size (default: 10 MB)
- `HEALTHCHECK_MAX_AGE_MINUTES`: optional maximum age for the last successful sync
- `IMAPSYNC_EXTRA_ARGS`: optional additional `imapsync` arguments

On container startup, required variables and the cron format are validated early so configuration mistakes fail fast.

## Operation

The image includes a Docker `HEALTHCHECK`. By default, the container is considered healthy when cron is running and the last sync attempt is not marked as `failure`. With `HEALTHCHECK_MAX_AGE_MINUTES`, you can additionally require that the last successful sync is not too old.

## Smoke Test

For a safe first test, set `DRY_RUN=true` and start the container once:

```bash
docker run --rm --name mailbox-mirror --env-file .env -e DRY_RUN=true mailbox-mirror-imapsync:local
```

A successful test run ends with `imapsync finished successfully.` in the log without writing any emails.
