# Mailbox Mirror Context

Mailbox Mirror is a small self-hosted IMAP mirror. This context names the mail sync concepts that should stay stable across scripts, configuration, tests, and documentation.

## Language

**Mailbox Mirror**:
The containerized tool that repeatedly mirrors mail from one IMAP mailbox into another.
_Avoid_: mail bridge, forwarder

**Mailbox Run**:
One attempted `imapsync` execution for a configured source mailbox and destination mailbox.
_Avoid_: migration, task

**Source Mailbox**:
The IMAP mailbox that Mailbox Mirror reads from.
_Avoid_: account1, host1

**Destination Mailbox**:
The IMAP mailbox that Mailbox Mirror writes into.
_Avoid_: account2, host2

**Sync Job**:
The scheduled recurring work that starts mailbox runs and records their result.
_Avoid_: cron job, runner

**Imapsync Adapter**:
The `imapsync` command-line integration used to perform a mailbox run.
_Avoid_: custom IMAP implementation

**Runtime Configuration**:
The validated settings that control Mailbox Mirror, its Sync Job, and its Mailbox Runs.
_Avoid_: raw environment

**Sync Job State**:
The recorded lifecycle and latest Mailbox Run result used to assess whether a Sync Job is healthy.
_Avoid_: health files, imapsync state
