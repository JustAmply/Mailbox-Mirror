# Configuration

[Back to setup](../README.md)

Edit `.env`, then run `docker compose up -d` to apply changes. Existing variable
names and defaults are unchanged. Omit options you do not need.

## Settings reference

`1` is the source mailbox; `2` is the destination. Booleans use `true` or `false`.
Time and size limits are positive whole numbers; `LOCK_WAIT_SECONDS` also accepts 0.

| Setting | Default | Purpose |
| --- | --- | --- |
| `HOST1`, `USER1`, `HOST2`, `USER2` | Required | IMAP servers and usernames |
| `PASSWORD1`, `PASSWORD2` | Required unless a file is set | Mailbox passwords |
| `PASSWORD1_FILE`, `PASSWORD2_FILE` | Unset | Read the password from a mounted file; takes precedence over the password variable |
| `PORT1`, `PORT2` | Adapter default (993 with TLS) | Override the IMAP port |
| `SSL1`, `SSL2` | `true` | Request implicit TLS; `false` leaves transport negotiation to imapsync |
| `AUTHMECH1`, `AUTHMECH2` | Automatic | Force an authentication mechanism |
| `CRON_SCHEDULE` | `*/5 * * * *` | Sync schedule; standard five-field cron syntax or a supported macro such as `@hourly` |
| `RUN_ON_STARTUP` | `true` | Sync immediately when the container starts |
| `DRY_RUN` | `false` | Preview operations without copying or deleting mail |
| `FOLDER_FILTER` | All folders | Select one source folder, for example `INBOX` |
| `FOLDER_INCLUDE` | Unset | Select multiple source folders, one per line |
| `FOLDER_EXCLUDE` | Unset | Exclude folders by regular expression, one per line |
| `FOLDER_MAP` | Automatic mapping | Set `source=destination` folder pairs, one per line |
| `DESTINATION_PREFIX` | Unset | Prefix destination folder names, for example `Source/` |
| `MAXAGE_DAYS` | Unset | Limit the age of messages considered by imapsync |
| `SYNC_MODE` | `additive` | Preserve destination-only messages; `mirror` opts into deletion |
| `ALLOW_DELETIONS` | `false` | Required for `SYNC_MODE=mirror` |
| `HEALTHCHECK_MAX_AGE_MINUTES` | Unset | Detect missing successful runs |
| `HEALTHCHECK_MAX_RUN_MINUTES` | Unset | Detect an overlong active run |
| `RUN_TIMEOUT_SECONDS` | Unset | Terminate an overlong adapter execution |
| `SHUTDOWN_GRACE_SECONDS` | `10` | Time to stop before forced termination |
| `LOCK_FILE` | `/tmp/imapsync.lock` | Lock path inside the container |
| `LOCK_WAIT_SECONDS` | `0` | Wait for the shared lock; 0 skips immediately if busy |
| `WEBHOOK_URL` | Unset | Send JSON failure/recovery events to this endpoint |
| `WEBHOOK_FAILURE_THRESHOLD` | `3` | Failed runs required for a failure alert |
| `MAX_LOG_SIZE_MB` | `10` | Rotate the active log before a run once it reaches this size |
| `IMAPSYNC_EXTRA_ARGS` | Unset | Advanced adapter flags, split on whitespace; shell quoting is not interpreted |
| `TZ` | `Europe/Berlin` in Compose | Time zone for scheduling |

## Multiple mailboxes

For a new setup, copy [`.env.multi-mailbox.example`](../.env.multi-mailbox.example)
to `.env`. Fill in the six values for each mailbox you need. If they share a
destination, repeat its three values for each source.

The template includes `COMPOSE_FILE=docker-compose.multi-mailbox.yml`, so you can
use ordinary Compose commands. **Start only the configured services**, for example:

```bash
docker compose up -d mailbox-mirror-a mailbox-mirror-b
docker compose logs -f --tail 50
```

Use the same service names when applying configuration changes. To inspect A:

```bash
docker compose exec mailbox-mirror-a mailbox-mirror-status
```

Existing multi-mailbox `.env` files still work. Add the `COMPOSE_FILE` line to
use these shorter commands, or keep using `docker compose -f docker-compose.multi-mailbox.yml`.
Do not replace an existing `.env` with the new template.

Each mailbox defaults to **INBOX only**, runs every 15 minutes at staggered
five-minute offsets, and skips the initial sync. The shared lock allows one
adapter at a time. The default single-mailbox schedule and folder selection are
different; these multi-mailbox defaults remain unchanged.

For per-mailbox settings, prefix the following names with `MAILBOX_A_`,
`MAILBOX_B_`, or `MAILBOX_C_`:

- `HOST1`, `PORT1`, `USER1`, `PASSWORD1`, `PASSWORD1_FILE`, `SSL1`, `AUTHMECH1`
  and their destination equivalents ending in `2`.
- `DRY_RUN`, `MAXAGE_DAYS`, `IMAPSYNC_EXTRA_ARGS`.
- `FOLDER_FILTER`, `FOLDER_INCLUDE`, `FOLDER_EXCLUDE`, `FOLDER_MAP`,
  `DESTINATION_PREFIX`, `SYNC_MODE`, `ALLOW_DELETIONS`.
- `HEALTHCHECK_MAX_AGE_MINUTES`, `HEALTHCHECK_MAX_RUN_MINUTES`,
  `RUN_TIMEOUT_SECONDS`, `SHUTDOWN_GRACE_SECONDS`, `LOCK_WAIT_SECONDS`.
- `WEBHOOK_URL`, `WEBHOOK_FAILURE_THRESHOLD`.

For example, add these to `.env` to select folders for A and let it wait briefly
when another mailbox holds the lock:

```dotenv
MAILBOX_A_FOLDER_FILTER=
MAILBOX_A_FOLDER_INCLUDE='INBOX
Sent Items'
MAILBOX_A_LOCK_WAIT_SECONDS=240
```

An explicitly empty `MAILBOX_A_FOLDER_FILTER` removes the example's INBOX filter.
Schedule, startup behavior, time zone, shared lock path and service-level settings
are set in the multi-mailbox Compose file; they are not mapped from prefixed variables.

## Password files

Set `PASSWORD1_FILE` and/or `PASSWORD2_FILE` to a readable file **inside the
container**, mounted read-only with a Compose override or Compose secrets. Its
first line is the password; it takes precedence over `PASSWORD1` / `PASSWORD2`.
The supplied Compose files do not mount host password files automatically.
For multiple mailboxes, prefix the variables with `MAILBOX_A_`, `B_` or `C_`.

Existing password variables still work. They are passed to imapsync through
private temporary files. The cron environment snapshot is readable only by root
and excludes unrelated environment secrets. Do not commit `.env` or password
files; container/host administrators can still access them.

## Health and time limits

For a five-minute schedule, `HEALTHCHECK_MAX_AGE_MINUTES=30` detects missing
progress. Set limits high enough for the first copy. A new container gets one
freshness interval to complete its first run; a failed run is unhealthy immediately.
Dry-run success has its own timestamp and never counts as an actual sync.

`HEALTHCHECK_MAX_RUN_MINUTES` reports an overlong run; `RUN_TIMEOUT_SECONDS`
actually terminates an overlong adapter execution (exit 124, or 137 if forced).
Both are disabled unless configured. Shutdown allows `SHUTDOWN_GRACE_SECONDS`
(default 10) before forcing termination. Compose allows 30 seconds; increase
`stop_grace_period` if you increase the shutdown limit.

`LOCK_WAIT_SECONDS` allows bounded waiting for a shared lock. Its default, 0,
skips immediately when busy. Waiting is not FIFO; use freshness monitoring to
detect repeatedly skipped mailboxes. Only one run per mailbox can run or wait.

`mailbox-mirror-status` reports timestamps, duration, exit code, failure/skip
counts and transferred messages as JSON. Unavailable metrics are `null`. State
lives in `/var/lib/imapsync`; mount a separate volume per mailbox to keep it
across container replacement. The shared lock volume does not preserve status.

## Folders and deletion

Use single-quoted multiline values in `.env`; empty lines are ignored and spaces
inside folder names are preserved:

```dotenv
FOLDER_INCLUDE='INBOX
Sent Items'
FOLDER_EXCLUDE='^Trash$
^Spam$'
FOLDER_MAP='Sent Items=Archive/Sent'
DESTINATION_PREFIX=Source/
```

- `FOLDER_INCLUDE` and `FOLDER_FILTER` select exact source folders together.
- `FOLDER_EXCLUDE` contains regular expressions.
- `FOLDER_MAP` routes folders but does not select them. Each explicit destination
  is a complete name and bypasses the prefix.
- `DESTINATION_PREFIX` is literal text including the destination's folder
  separator. It disables automatic special-folder mapping.

The default `SYNC_MODE=additive` copies missing mail, updates matching message
flags and keeps destination-only mail. A source move copies mail to the new folder
without removing the old destination copy. This is a one-way sync, not an immutable
backup. Built-in modes do not delete source mail.

To remove destination messages missing from the corresponding source folder, set
**both** `SYNC_MODE=mirror` and `ALLOW_DELETIONS=true`. This uses
`--delete2 --expunge2`; destination-only folders are not deleted. Test with
`DRY_RUN=true` first, especially with age or folder filters. Do not use mirror mode
when multiple sources share destination folders or destination-only mail must stay.

`IMAPSYNC_EXTRA_ARGS` remains supported and can enable destructive flags even in
additive mode, independently of `ALLOW_DELETIONS`. It splits on whitespace; use
the dedicated folder settings for names containing spaces.

Normal message identification avoids UID-cache-related duplicates after container
replacement, including messages previously copied in UID mode. An explicit
`--useuid` override requires managing a persistent cache. Existing duplicates are
not automatically deleted.

## Notifications

Set `WEBHOOK_URL` to an HTTP(S) endpoint accepting generic JSON POST requests.
It is not a Slack/Discord-specific payload. The monitor checks every 30 seconds
and sends one `alert` per incident and one `recovery` after a successful run
clears it. The default threshold is three failed runs.

With the corresponding health limits enabled, alerts also cover missing progress
(`stale`) and overlong runs (`run_timeout`); other failure alerts use `failure`.
Failed delivery is retried on the next check and never changes sync health or
results. Each request has a ten-second limit. Receivers should tolerate duplicate
events if an HTTP acknowledgment is lost.

Payloads contain operational status, counts and timestamps, not passwords or
mailbox addresses. For multiple mailboxes, use distinct endpoint paths to identify
them. Notification history persists only as long as the sync state directory.
