<p align="center">
  <img src="docs/logo.png" alt="Mailbox Mirror logo" width="400">
</p>

# Mailbox Mirror

Copy mail from one IMAP mailbox to another, automatically every five minutes.
Useful when your provider does not offer forwarding. By default, existing mail
in the destination is kept; matching messages can have their flags updated.

## Start

You need Docker with Docker Compose and IMAP access to both mailboxes.

1. Copy [`.env.example`](.env.example) to `.env`. For an existing installation,
   keep your current `.env`; no configuration migration is needed.
2. Fill in the six values. `1` means **source**, `2` means **destination**:

   ```dotenv
   HOST1=imap.source.example
   USER1=source@example.com
   PASSWORD1='replace-me'
   HOST2=imap.destination.example
   USER2=destination@example.com
   PASSWORD2='replace-me'
   ```

   Use your provider's app password if required. Keep passwords quoted as shown
   so `$` and `#` stay literal. For passwords containing a single quote, use
   [password files](docs/configuration.md#password-files).
3. Optional: add `DRY_RUN=true` to `.env` for a preview without copying mail.
   If you already use advanced arguments, remove any `--nodry` override first.
4. Start and watch the first sync:

   ```bash
   docker compose up -d
   docker compose logs -f --tail 50
   ```

The first sync runs immediately, then every five minutes. TLS is enabled by default.
Pressing Ctrl+C stops the log view; the container continues running.

If you enabled the preview, change `DRY_RUN` to `false` when satisfied, then run
`docker compose up -d` again to start copying mail.

## Everyday commands

| Task | Command |
| --- | --- |
| Check whether the container is healthy | `docker compose ps` |
| View recent activity | `docker compose logs --tail 100` |
| Inspect the last sync result (JSON) | `docker compose exec mailbox-mirror mailbox-mirror-status` |
| Apply changes to `.env` | `docker compose up -d` |
| Update to the published image | `docker compose pull` then `docker compose up -d` |
| Stop syncing | `docker compose stop` |

## Common changes

Add only the settings you need to `.env`, then run `docker compose up -d`.

| Goal | Setting |
| --- | --- |
| Sync every 15 minutes | `CRON_SCHEDULE=*/15 * * * *` |
| Copy only the inbox | `FOLDER_FILTER=INBOX` |
| Report unhealthy if no sync succeeds for 30 minutes | `HEALTHCHECK_MAX_AGE_MINUTES=30` |
| Receive failure and recovery events | `WEBHOOK_URL=https://your-endpoint.example/events` |

Allow enough time for the first copy before enabling a freshness limit.
Webhooks expect a generic JSON receiver.

- [Multiple mailboxes](docs/configuration.md#multiple-mailboxes): separate setup template and commands.
- [All settings and examples](docs/configuration.md): folders, limits, password files and explicit deletion mode.
- [Development and tests](docs/development.md): build the current checkout and run the test suites.
