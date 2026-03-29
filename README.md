# Mailbox Mirror

Mailbox Mirror runs `imapsync` on a cron schedule so one IMAP mailbox is mirrored into another. Use it when simple forwarding is not available and you want a small self-hosted sync.

If your provider supports server-side forwarding, use that instead. It is simpler and usually more reliable than running your own sync container.

## Quick Start

1. Copy `.env.example` to `.env`.
2. Fill in the required source and destination credentials.
3. Start the container:

```bash
docker compose up -d
```

4. Check the first run:

```bash
docker compose logs -f mailbox-mirror
```

Required values:

- `HOST1`, `USER1`, `PASSWORD1` for the source mailbox
- `HOST2`, `USER2`, `PASSWORD2` for the destination mailbox

Common optional values:

- `PORT1`, `PORT2`, `SSL1`, `SSL2` if you need non-default IMAP settings
- `CRON_SCHEDULE` to change the sync interval
- `RUN_ON_STARTUP=false` to skip the initial sync on container start
- `DRY_RUN=true` for a safe first test without writing mail

Advanced-only values:

- `LOCK_FILE` to share one lock across multiple containers
- `FOLDER_FILTER` to sync only selected folders such as `INBOX`
- `MAXAGE_DAYS` to limit how much old mail is scanned
- `HEALTHCHECK_MAX_AGE_MINUTES` to fail health checks when sync is too old
- `IMAPSYNC_EXTRA_ARGS` for extra `imapsync` flags

The container validates required variables and the cron schedule on startup, so bad config fails fast.

## Advanced Example

The repo includes [`docker-compose.multi-mailbox.yml`](docker-compose.multi-mailbox.yml) for three staggered mailbox mirrors that share one lock file. It is meant for low-RAM setups where only one `imapsync` process should run at a time.

1. Open `.env`.
2. Uncomment and fill the `MAILBOX_A_*`, `MAILBOX_B_*`, and `MAILBOX_C_*` values in the advanced section.
3. Start the advanced stack:

```bash
docker compose -f docker-compose.multi-mailbox.yml up -d
```

The advanced example keeps these defaults:

- `RUN_ON_STARTUP=false` for all three containers
- staggered schedules with 5-minute offsets
- `FOLDER_FILTER=INBOX`
- one shared `LOCK_FILE` volume

If all three source mailboxes mirror into the same destination account, reuse the same `MAILBOX_*_HOST2`, `MAILBOX_*_USER2`, and `MAILBOX_*_PASSWORD2` values for each service.
