FROM debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends dovecot-imapd python3 \
    && groupadd --gid 5000 vmail \
    && useradd --uid 5000 --gid 5000 --home-dir /mail vmail \
    && mkdir /mail \
    && chown vmail:vmail /mail \
    && rm -rf /var/lib/apt/lists/*

COPY dovecot.conf /etc/dovecot/dovecot.conf
COPY mailbox.py /test/mailbox.py
ENTRYPOINT ["dovecot", "-F"]
