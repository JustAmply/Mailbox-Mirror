# Working in Mailbox Mirror

## Validation

- Run `bash tests/test.sh` for every change. On Windows, use Git Bash explicitly; do not assume WSL is installed.
- After changing `Dockerfile`, `docker/*.sh`, the image-build workflow, or the container smoke test, build `mailbox-mirror:smoke-test` and run `bash tests/container-smoke-test.sh`.
- Keep the container smoke test network-isolated and use fake credentials. It validates the container lifecycle, not a live IMAP service.

## Configuration contract

- When adding or changing an environment option, keep `.env.example`, the Compose files, runtime validation, README guidance, and the relevant contract tests aligned.
- Preserve documented `.env` overrides. A Compose default must remain overridable and needs a regression assertion in `tests/compose-config-test.sh`.

## Credentials

- Never commit `.env` or real mailbox credentials. Tests and examples must use unmistakably fake values.
