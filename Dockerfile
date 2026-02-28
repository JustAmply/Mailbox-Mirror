FROM gilleslamiral/imapsync:latest

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends cron ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/run-imapsync.sh /usr/local/bin/run-imapsync.sh
COPY docker/cron-runner.sh /usr/local/bin/cron-runner.sh

RUN chmod +x /usr/local/bin/entrypoint.sh \
    /usr/local/bin/run-imapsync.sh \
    /usr/local/bin/cron-runner.sh \
    && touch /var/log/imapsync.log

ENV CRON_SCHEDULE="*/5 * * * *"
ENV RUN_ON_STARTUP="true"

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]