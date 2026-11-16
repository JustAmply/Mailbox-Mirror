# Development

[Back to setup](../README.md)

## Test the current checkout

Use Bash (Git Bash on Windows) with Docker Compose installed:

```bash
bash tests/test.sh
```

This checks shell syntax, runtime configuration, sync state, adapter arguments,
notification behavior and Compose mappings. It does not contact an IMAP server.

For container and integration checks, start Docker and run:

```bash
docker build --tag mailbox-mirror:smoke-test .
bash tests/container-smoke-test.sh
bash tests/runtime-container-test.sh
bash tests/webhook-container-test.sh
bash tests/imap-integration-test.sh
```

These commands build and test the current source. The normal Compose setup uses
the published image, so `docker compose up -d` alone does not test local changes.

- The container, runtime and webhook suites use fake credentials and adapters
  with `--network none`; they cover startup, timeouts, locks and graceful shutdown.
- The IMAP suite builds two disposable Dovecot servers on an internal Docker
  network with no published ports. Synthetic mail tests contents, flags, dates,
  folders, deletion modes, upgrades from UID matching and recovery after interruption.
- Image and package downloads need network access during builds. No test uses a
  real mailbox.

GitHub Actions runs these checks on pull requests, `main` and `codex/**` pushes.
Only `main` publishes images. Feature-branch pushes do not replace `latest`.
