<p align="center">
  <img src="docs/logo.png" alt="Mailbox Mirror logo" width="400">
</p>

# Mailbox Mirror

Mailbox Mirror runs `imapsync` on a cron schedule so one IMAP mailbox is mirrored into another. Use it when simple forwarding is not available and you want a small self-hosted sync.

If your provider supports server-side forwarding, use that instead. It is simpler and usually more reliable than running your own sync container.

## Project Background

This project started as a practical response to a very specific failure mode in the modern email stack: Gmail is shutting down Gmailify and POP-based fetching for external accounts, while Yahoo keeps simple forwarding behind tighter restrictions on the free tier. That combination removes the two obvious low-effort ways to keep third-party mail flowing into Gmail.

I wanted a replacement that was boring in the good sense: self-hosted, inspectable, cheap to run, and based on proven IMAP behavior instead of another opaque mail bridge. The result is `Mailbox Mirror`: a small wrapper around `imapsync` that turns a one-off migration tool into a dependable recurring sync job.

The core idea is straightforward but intentional. If forwarding is available, forwarding is still the smarter choice and should be preferred. But when Gmailify disappears, POP fetching goes away, and Yahoo will not forward for free, a scheduled IMAP-to-IMAP mirror is a clean fallback that keeps control on your side without inventing a custom mail system from scratch.

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
- `AUTHMECH1`, `AUTHMECH2` to force an authentication mechanism
- `FOLDER_FILTER` to sync only selected folders such as `INBOX`
- `MAXAGE_DAYS` to limit how much old mail is scanned
- `HEALTHCHECK_MAX_AGE_MINUTES` to fail health checks when sync is too old
- `IMAPSYNC_EXTRA_ARGS` for extra `imapsync` flags
- `MAX_LOG_SIZE_MB` to limit the active log file before rotation

The container validates the documented runtime configuration on startup and before every mailbox run, so bad config fails fast.

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

## Development Checks

Run the fast contract checks with Bash and the Docker Compose plugin installed:

```bash
bash tests/test.sh
```

The checks validate shell syntax, runtime configuration, Sync Job state, complete Mailbox Run outcomes through a fake Imapsync Adapter, and documented Compose mappings and overrides. They do not connect to an IMAP server.

To validate the built container lifecycle without connecting to an IMAP server:

```bash
docker build --tag mailbox-mirror:smoke-test .
bash tests/container-smoke-test.sh
```

## Credentials from files

Existing `PASSWORD1` / `PASSWORD2` configurations remain supported. Passwords
are passed to imapsync through private temporary files instead of command-line
arguments. The cron environment snapshot is readable only by root and includes
only runtime settings, not unrelated environment secrets.

For mounted secrets, set `PASSWORD1_FILE` and/or `PASSWORD2_FILE` to a readable
file **inside the container**. The first line contains the password. A file
setting takes precedence over the corresponding password variable. Mount your
secret read-only using a local Compose override (or Compose secrets); the base
Compose files do not mount host secrets automatically. The multi-mailbox example
maps `MAILBOX_A_PASSWORD1_FILE` / `MAILBOX_A_PASSWORD2_FILE`, likewise for B/C.
Never commit the secret files or a populated `.env`. Container administrators
can still access credentials; secret files do not protect against host root.

## Run health, time limits, and status

Existing schedules and optional freshness limits remain unchanged. For a five-minute
schedule, consider `HEALTHCHECK_MAX_AGE_MINUTES=30` to detect missing progress and
`HEALTHCHECK_MAX_RUN_MINUTES=60` to detect stuck runs. Choose limits that allow the
initial mailbox copy to finish. The freshness limit provides one interval of grace
on first container startup. An actual failed run is unhealthy immediately. Successful
dry runs update a separate timestamp and never count as actual synchronization;
in `DRY_RUN=true` health checks assess the dry-run timestamp instead.

`RUN_TIMEOUT_SECONDS` optionally terminates an overlong adapter execution (exit 124, or 137 after
forced termination). The default has no total runtime limit. `SHUTDOWN_GRACE_SECONDS`
(default 10) gives the adapter time to stop before forced termination. The supplied Compose files allow 30 seconds for shutdown. Set Compose
`stop_grace_period` longer than this value plus five seconds if you increase it.
Shutdown also handles an initial sync that is still running.

`LOCK_WAIT_SECONDS` (default 0) lets a mailbox wait for the shared lock rather than
immediately skip. Only one active/waiting run per mailbox is allowed; overlapping
scheduled attempts cannot overwrite its state. Waiting is bounded and does not
guarantee FIFO ordering. Combine a wait with freshness monitoring to detect
starvation. In the multi-mailbox example use the corresponding `MAILBOX_A_`,
`MAILBOX_B_`, or `MAILBOX_C_` setting, including freshness and runtime limits.

Run `docker compose exec mailbox-mirror mailbox-mirror-status` to get JSON containing
last status, real/dry success timestamps, duration, exit code, failure and skip
counts, and transferred-message count when the adapter reports it. Missing metrics
are `null`, not zero. Status is local to the container unless you mount its state
directory `/var/lib/imapsync`; use a separate state volume for each mailbox. The
shared lock volume is not a shared state directory.

The adapter now uses normal message identification instead of forcing UID-only
matching. This prevents duplicates after container recreation when the old UID
cache is gone. Existing messages from UID-mode runs are recognized by the normal
matching rules. Explicit `--useuid` in `IMAPSYNC_EXTRA_ARGS` remains supported but
requires managing a persistent imapsync cache. No existing duplicate messages are
automatically removed.

## Folder selection and deletion policy

The default `SYNC_MODE=additive` preserves destination-only messages. It still
updates flags on matching messages and copies missing messages; it is a one-way
sync, not an independent immutable backup or bidirectional sync. Source messages
are not deleted by the built-in modes. Moving a source message copies it into the
new folder; additive mode retains the previous destination copy.

`SYNC_MODE=mirror` additionally removes destination messages absent from the
corresponding source folder, and **requires `ALLOW_DELETIONS=true`**. This mode
uses `--delete2 --expunge2`; it does not delete destination-only folders. Test with
`DRY_RUN=true` first. Do not use mirror mode when several sources share the same
destination folders or when destination-only mail must be retained. Take care
with age/selection filters; review the adapter's dry-run output before enabling
real deletions. Existing `IMAPSYNC_EXTRA_ARGS` remain authoritative and may enable
other destructive behavior even in additive mode; this compatibility escape
hatch is not restricted by `ALLOW_DELETIONS`.

New optional settings accept newline-separated entries (single-quoted multiline
values in `.env`). Blank lines are ignored; spaces within folder names are kept:

```dotenv
FOLDER_INCLUDE='INBOX
Sent Items'
FOLDER_EXCLUDE='^Trash$
^Spam$'
FOLDER_MAP='Sent Items=Archive/Sent'
DESTINATION_PREFIX=Source/
```

`FOLDER_INCLUDE` selects exact source folders and combines with the existing
`FOLDER_FILTER`. `FOLDER_EXCLUDE` contains regular expressions. `FOLDER_MAP` uses
`source=destination` pairs and does not itself select folders. `DESTINATION_PREFIX`
is literal text, including the desired separator (for example `/`); it disables
automatic special-folder mapping so the prefix is applied consistently. Explicit
`FOLDER_MAP` destinations are complete names and bypass the prefix. Match the
destination server's folder separator.

The multi-mailbox example exposes the same settings with `MAILBOX_A_` / `B_` /
`C_`. It retains its `INBOX` filter by default; set `MAILBOX_A_FOLDER_FILTER=`
explicitly when selecting other folders or all folders.

## Optional notifications

Set `WEBHOOK_URL` to an HTTP(S) endpoint accepting JSON POST requests. No message
is sent unless you configure an endpoint. `WEBHOOK_FAILURE_THRESHOLD` defaults
to 3 consecutive failed mailbox runs. Configure `HEALTHCHECK_MAX_AGE_MINUTES`
to also alert on missing progress, including repeated lock skips, and optionally
`HEALTHCHECK_MAX_RUN_MINUTES` for overlong runs. Each mailbox in the multi-mailbox
example has its own `MAILBOX_A_WEBHOOK_URL` and threshold (likewise B/C); use
distinct endpoint paths when the receiver needs to distinguish mailboxes.

A separate monitor checks every 30 seconds, including during the initial sync.
It sends one `event=alert` per incident and one `event=recovery` after a successful
run clears it. Reasons are `failure`, `stale`, or `run_timeout`. Failed deliveries
are retried on the next check; a lost HTTP acknowledgment can cause a duplicate,
so receivers should handle repeated events. Payloads contain operational status,
counts and timestamps, never passwords, mailbox addresses or the webhook URL.
This is a generic JSON endpoint, not a provider-specific Slack/Discord payload.

The monitor is independent of the Docker healthcheck and sync execution: a slow
or unavailable receiver does not turn a successful sync into a failure. Each
request has a ten-second deadline. Notification state is retained only as long
as the sync state directory is retained.

## Integration checks

After building `mailbox-mirror:smoke-test`, also run:

```bash
bash tests/runtime-container-test.sh
bash tests/webhook-container-test.sh
bash tests/imap-integration-test.sh
```

The runtime suite uses a fake adapter with `--network none` to test timeouts,
lock contention and shutdown, including startup races. The IMAP suite builds two
disposable Dovecot servers on an internal Docker network with no published ports,
fake credentials and synthetic messages. It checks real contents, flags, dates,
folder routing, deletion modes, upgrades from UID-only matching and interrupted
transfer recovery. Images/package downloads need network access during the build;
the actual mail tests have no external network access. No real mailbox is used.

GitHub Actions runs contracts, image build, lifecycle, runtime, webhook and IMAP tests on
pull requests, `main`, and `codex/**` pushes. Image publication remains limited to
`main`; feature-branch checks do not publish or replace the `latest` image.
