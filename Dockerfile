FROM gilleslamiral/imapsync:latest@sha256:ece980cb0fd2806369975d2989a3e8d9fbf28d632cdd45a05961a1e511612ed5

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron ca-certificates tzdata \
    && mkdir -p /usr/local/lib/mailbox-mirror \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/run-imapsync.sh /usr/local/bin/run-imapsync.sh
COPY docker/cron-runner.sh /usr/local/bin/cron-runner.sh
COPY docker/healthcheck.sh /usr/local/bin/healthcheck.sh
COPY docker/config.sh /usr/local/lib/mailbox-mirror/config.sh
COPY docker/mailbox-run.sh /usr/local/lib/mailbox-mirror/mailbox-run.sh
COPY docker/sync-job-state.sh /usr/local/lib/mailbox-mirror/sync-job-state.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
    /usr/local/bin/run-imapsync.sh \
    /usr/local/bin/cron-runner.sh \
    /usr/local/bin/healthcheck.sh \
    && touch /var/log/imapsync.log

HEALTHCHECK --interval=30s --timeout=5s --start-period=5m --retries=3 CMD ["/usr/local/bin/healthcheck.sh"]

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
