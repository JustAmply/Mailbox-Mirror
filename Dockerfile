FROM gilleslamiral/imapsync:latest

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/run-imapsync.sh /usr/local/bin/run-imapsync.sh
COPY docker/cron-runner.sh /usr/local/bin/cron-runner.sh
COPY docker/healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
    /usr/local/bin/run-imapsync.sh \
    /usr/local/bin/cron-runner.sh \
    /usr/local/bin/healthcheck.sh \
    && touch /var/log/imapsync.log

ENV CRON_SCHEDULE="*/5 * * * *"
ENV RUN_ON_STARTUP="true"

HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
