"""Seed and inspect real IMAP mailboxes using only Python's standard library."""

import email
import imaplib
import re
import sys
import time
from contextlib import contextmanager


PASSWORD = "FAKE-integration-password"
INTERNAL_DATE = '"14-Feb-2020 12:34:56 +0000"'
FOLDERS = ("INBOX", "Projects", "Projects/Archive")


def quoted_folder(name):
    return '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'


def check(result):
    status, data = result
    assert status == "OK", (status, data)
    return data


@contextmanager
def mailbox(host, user="fixture"):
    client = imaplib.IMAP4(host, timeout=10)
    try:
        check(client.login(user, PASSWORD))
        yield client
    finally:
        client.logout()


def append(client, folder, identifier, flags="", size=30):
    message = (
        f"From: sender@example.test\r\nTo: recipient@example.test\r\n"
        f"Date: Fri, 14 Feb 2020 12:34:56 +0000\r\n"
        f"Message-ID: <{identifier}@example.test>\r\n"
        f"Subject: Fixture {identifier}\r\n\r\n"
    ).encode() + (b"Synthetic test content.\r\n" * size)
    check(client.append(quoted_folder(folder), flags, INTERNAL_DATE, message))


def snapshot(host, folders=FOLDERS, user="fixture"):
    result = {}
    with mailbox(host, user) as client:
        for folder in folders:
            check(client.select(quoted_folder(folder), readonly=True))
            entries = []
            for uid in check(client.uid("search", None, "ALL"))[0].split():
                data = check(client.uid("fetch", uid, "(FLAGS INTERNALDATE BODY.PEEK[])"))
                metadata, body = next(item for item in data if isinstance(item, tuple))
                flags = set(imaplib.ParseFlags(metadata)) - {b"\\Recent"}
                internal_date = re.search(rb'INTERNALDATE "([^"]+)"', metadata).group(1)
                identifier = email.message_from_bytes(body)["Message-ID"]
                entries.append((identifier, flags, internal_date, body))
            result[folder] = sorted(entries, key=lambda item: item[0])
    return result


def main():
    action = sys.argv[1]
    if action == "ready":
        deadline = time.monotonic() + 30
        while True:
            try:
                with mailbox("localhost"):
                    return
            except (OSError, imaplib.IMAP4.error):
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.25)
    elif action == "seed":
        with mailbox("localhost") as client:
            for folder in FOLDERS[1:]:
                check(client.create(quoted_folder(folder)))
            append(client, "INBOX", "inbox-unread")
            append(client, "INBOX", "inbox-read", "(\\Seen)")
            append(client, "Projects", "project", "(\\Flagged)")
            append(client, "Projects/Archive", "archive", "(\\Seen \\Answered)")
    elif action in ("verify", "verify-additive"):
        source = snapshot("source")
        destination = snapshot("destination")
        for folder, messages in destination.items():
            ids = [message[0] for message in messages]
            assert len(ids) == len(set(ids)), f"Duplicate messages in {folder}"
        if action == "verify-additive":
            extras = [entry for entry in destination["INBOX"] if entry[0] == "<destination-only@example.test>"]
            assert len(extras) == 1, "Additive sync removed a destination-only message"
            destination["INBOX"].remove(extras[0])
        assert source == destination, "Source and destination contents, flags or internal dates differ"
        print("ok - real IMAP contents, folders, flags, dates and duplicate-free repeat")
    elif action == "change-flags":
        with mailbox("localhost") as client:
            check(client.select(quoted_folder("INBOX")))
            uid = check(client.uid("search", None, "HEADER", "Message-ID", "inbox-unread"))[0]
            assert uid, "Seed message missing"
            check(client.uid("store", uid, "+FLAGS.SILENT", "(\\Seen \\Flagged)"))
    elif action == "seed-recovery":
        with mailbox("localhost") as client:
            for index in range(12):
                append(client, "INBOX", f"recovery-{index:02d}", size=3000)
    elif action == "seed-destination-only":
        with mailbox("localhost") as client:
            append(client, "INBOX", "destination-only", "(\\Seen)")
    elif action == "verify-routing":
        mapping = {"INBOX": "Source/INBOX", "Projects": "Mapped Projects"}
        source = snapshot("source", folders=mapping)
        destination = snapshot("destination", folders=mapping.values(), user="routed")
        assert source == {key: destination[value] for key, value in mapping.items()}, "Folder routing changed contents"
        with mailbox("destination", "routed") as client:
            assert client.select(quoted_folder("Source/Projects/Archive"), readonly=True)[0] == "NO", "Excluded folder was copied"
        print("ok - include, exclude, explicit mapping and destination prefix")
    elif action == "wait-partial":
        deadline = time.monotonic() + 60
        with mailbox("localhost") as client:
            while time.monotonic() < deadline:
                check(client.select(quoted_folder("INBOX"), readonly=True))
                ids = check(client.uid("search", None, "HEADER", "Subject", "recovery-"))[0].split()
                if 0 < len(ids) < 12:
                    return
                assert len(ids) < 12, "Transfer completed before interruption could be tested"
                time.sleep(0.2)
        raise AssertionError("No partial transfer observed within 60 seconds")
    else:
        raise ValueError(f"Unknown action: {action}")


if __name__ == "__main__":
    main()
