---
name: himalaya
description: Himalaya CLI (email) — pre-authed for Proton/Gmail/Stalwart accounts via IMAP, plus jmapcli for JMAP-only Stalwart ops. Use when sending, reading, searching, moving, or exporting email via the himalaya CLI, or discovering/managing mail accounts and folders. Covers account/folder discovery, the query DSL (flags-before-query), the non-interactive template send flow, raw .eml export, and Gmail Trash rescue within the 30-day window.
allowed-tools: Read, Bash, Grep
---

<!-- Auto-synced from ~/.claude/includes/himalaya.md — do not edit manually -->

# Himalaya CLI (email)

Himalaya is installed and pre-authed for all mail accounts (Proton via local Bridge, Gmail, Stalwart). Config: `~/Library/Application Support/himalaya/config.toml`. **Installed version: v2.0.0** (config migrated 2026-07-31; v1 backup: `config-v1-backup.toml` next to it). Everything below describes the v2 surface — v1 muscle memory (`folder list`, `envelope list <query>`, `-f`, `-o json`) fails to parse.

**Guardrails (always-on):** confirm with the user before sending or bulk deleting/moving; cite exact message IDs when acting; after ANY send error, check the Sent folder BEFORE retrying (duplicate-send risk).

## Accounts & mailboxes

- `himalaya account list` to discover; **always pass `-a "<account>"`** when acting. Current accounts: `fries.pm proton` (default), `inetpeople stalwart`, `pulau-indah stalwart`, `deltahedge stalwart`, `tapakly stalwart`, `ernesto.fries2 gmail`, `inetpeopleholding gmail`.
- ⚠️ **`inetpeople.net` lives on Stalwart — `-a "inetpeople stalwart"`.** The old `inetpeople proton` account was REMOVED from the config on 2026-08-18 (backup: `config.toml.bak-20260818`) after a send through it failed silently — no Bridge submit, no Sent copy — while its mailbox still looked alive (it kept receiving some mail and its Sent folder mirrors the migrated history). The Proton mailbox still exists server-side; reach it via Apple Mail / Bridge, not himalaya. **Sender address is `efries@inetpeople.net`**; `e.fu@inetpeople.net` is a receive-only alias and Stalwart rejects it at MAIL FROM (`501 5.5.4 You are not allowed to send from this address`) — reply to mail addressed to `e.fu@` from `efries@`.
- Mailbox flag is **`-m/--mailbox`** (v1's `-f` on list/read is gone). Names resolve case-insensitively through the per-account `[mailbox.alias]` map first; all accounts have `inbox`/`sent`/`drafts`/`trash` aliases configured, so `-m trash` works everywhere. Raw names still work: Gmail per locale (`[Google Mail]/All Mail` on ernesto.fries2, `[Gmail]/...` on inetpeopleholding), Stalwart `Sent Items`/`Deleted Items`, Bridge `Sent`/`Trash`.
- `mailbox list` (alias `mbox`) replaces `folder list`. **v2 JSON no longer carries special-use attributes** — you cannot autodetect `\Trash` from it; use the configured alias or known names.
- **Whole-thread work: search All Mail**, not INBOX/Sent — Sent misses received mail and vice versa.
- IDs are per-mailbox IMAP ids: the same message has DIFFERENT ids in different mailboxes, and a move assigns a new id in the destination.

## Listing & searching

- `envelope list` no longer accepts a query — **queries live in `envelope search`**: conditions `date/after <yyyy-mm-dd>`, `from/to/subject/body <pattern>` (case-insensitive substring), `flag <seen|answered|flagged|draft>`, combinable with `and`/`or`/`not`, parentheses, `order by date desc`.
- **All CLI flags BEFORE the query** — the variadic `[QUERY]...` swallows everything after it:
  ```
  himalaya envelope search -a "ernesto.fries2 gmail" -m "[Google Mail]/All Mail" -s 500 --json from dahm
  ```
- JSON output is **`--json`** (not `-o json`), accepted in subcommand position, and results are wrapped: `{"envelopes": [...]}`, `{"mailboxes": [...]}`. Error objects also come back as JSON (`{"error": ...}`) with exit 0 in some paths — check the shape, not just the exit code.
- **Envelope `from`/`to` are LISTS of `{name, email}`** (v1 had a single `{name, addr}` object): `.from[0].email`, not `.from.addr`.
- ⚠️ **`from`/`to` search matches the DISPLAY NAME, not the address.** Verified 2026-08-09 on pulau-indah: `search from ocbc` returned dozens of OCBC hits but silently omitted the monthly e-statements (ids 1365/1269/932) whose header is a bare `From: notifikasi@ocbc.id` with no display name — `from notifikasi` and `subject koran` both found them. **A `from <domain>` search is not proof a message is absent**; cross-check with a `subject`/`body` term or the local-part before concluding anything is missing.
- Large result sets: fetch one big page (`-s 5000`) rather than trusting `-p` pagination (v1's page-repeat bug against Gmail is unverified on v2 — the big-page pattern stays the safe default). Small pages window by IMAP UID, not date — low-UID imported mail (e.g. `Import-2026-07`) is invisible in a `-s 5` listing.
- stderr codec noise may still appear — don't blanket-`2>/dev/null`; let it print and ignore.

## Reading & exporting

- `himalaya message read -m <mailbox> <id>`; `--raw` for the full RFC822 source. **v1's `--preview` and `-H <header>` are gone** — fetch `--raw` and parse headers locally.
- Raw export to file: `message read --raw` redirected, or `attachment` subcommands for parts.

## Sending (non-interactive)

- **A self-authored `.eml` MUST carry a `Date:` header.** himalaya passes the raw message through without adding one, and the send dies at the save step with `IMAP APPEND failed: BAD invalid rfc5322 message: Required header field 'Date' not found or empty`. Build it with `LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000"`. Refresh the header if the draft sits overnight — a stale `Date:` ships as-is.
- `message send` takes the message as positional/stdin. **Sent-copy is now opt-in per send: `--save <mailbox>`** (v1's `message.send.save-copy` config key is gone). **Gmail AND Proton: NEVER pass `--save`** — both auto-save server-side and an append duplicates the row. Verified 2026-08-22 on `fries.pm proton`: one `message send --save sent` produced TWO Sent entries 7s apart — Proton's own copy (`…@protonmail.internalid`) plus himalaya's append (`…@fries.fr`) — one delivery, two rows. Stalwart: pass `--save sent` when you want a Sent copy.
- **A send that errors may still have been DELIVERED — but not every error class.** SMTP submit happens before the *save* step, so a failure attributed to saving can sit on either side of an actual delivery. **Exception, verified 2026-08-22: `IMAP APPEND failed: BAD invalid rfc5322 …` means NOTHING was sent** — himalaya aborts before the submit. Proven by replaying the identical malformed message to a self address: same error, and the probe never appeared in Inbox, Spam, Archive or Sent.
- **Ground truth for "did it go out", in order of strength:** the server delivery log — for Stalwart, `ssh root@mail.deltahedge.io` and grep `/var/log/stalwart/stalwart.<date>` for `delivery.delivered` / `queue.` events, a `250` per recipient being proof. **Proton Bridge does NOT log SMTP** (`logSMTP="false"` in `~/Library/Application Support/protonmail/bridge-v3/logs/*_bri_*.log`), so there the Sent folder IS the signal: because Proton auto-saves every real send, an absent Sent copy is genuine evidence nothing left. Allow ~60s for Bridge sync before concluding. When still unsure, replay the exact failure to a self address rather than retrying at a real recipient.
- **A missing Sent-folder copy does NOT mean a send failed.** Apple Mail files sent copies by thread association, not From address — check the OTHER accounts' Sent folders (esp. `fries.pm proton`) before advising a resend. Full writeup: `~/_DATA/hosting/self-hosted-email/README.md` § "Apple Mail files the Sent copy under the WRONG account".
- Proton Bridge SMTP (1025) is implicit TLS with a self-signed cert — himalaya v1 could not send through Bridge; v2 with `smtp.server = "smtps://127.0.0.1:1025"` **works (verified 2026-08-10: send from `fries.pm proton` with From-alias ernesto@fries.fr, delivered + Sent copy)**. Two setup traps hit on first use: the account's `-smtp` keychain entry didn't exist (Bridge uses ONE password for IMAP+SMTP — copy the `-imap` entry: `security add-generic-password -a '<acct>' -s 'himalaya-<acct>-smtp' -w "$(security find-generic-password -a '<acct>' -s 'himalaya-<acct>-imap' -w)"`), and the config had port 465 instead of Bridge's 1025. Bridge queues sends asynchronously — the Sent copy appears ~10–60s after "Message successfully sent"; a missing Sent copy right after sending is normal, not a failure.

## Moving / deleting / flags

- `himalaya message move -f <src> -t <dst> <id>...` — **`-t/--to` is a mandatory FLAG now**, no positional destination. Both resolve through `[mailbox.alias]`.
- ⚠️ **`message add -m drafts` does NOT set `\Draft`** — the message lands with `seen` only, and Apple Mail then shows it as an ordinary received message: **read-only, no edit, only reply/forward**. Always follow an add-to-Drafts with `himalaya flag add -a "<acct>" -m drafts -f draft <id>...` (flag values: `seen|answered|flagged|draft`). Verified 2026-08-13 on pulau-indah; it silently made every prior mail-agent draft uneditable for the user. Re-select the mailbox in Apple Mail to pick up the flag change.
- `message delete <id>` · `flag add|remove <id> --flag seen`.
- **Gmail Trash auto-deletes after 30 days** — rescue evidence promptly (`message move -f "[Gmail]/Trash" -t "[Gmail]/All Mail" <id>`), and refresh the local mbsync backup BEFORE bulk-trashing on Gmail.
- **Gmail bulk `message move` can report failure after succeeding** (empty error, moves executed server-side — observed 2026-07-31, ~60 messages across 3 batches). Verify by re-searching source and destination before retrying a "failed" batch.
- Mass operations: IMAP via himalaya or a script beats webmail. Confirm with the user first.

## Shell quirks (zsh)

- Quote `echo` separator args: `echo "==="` — a bare `===` triggers zsh path expansion and exits 1.

## JMAP for Stalwart mailboxes

himalaya v2 ships a `jmap` backend/subcommand tree, but the configured accounts run IMAP. `jmapcli` (https://boogie.digital/cli/) remains the tool for JMAP-level ops against Stalwart (`jmapcli accounts`; default `efries@deltahedge.io`, plus `efries@pulau-indah.com`, via https://mail.deltahedge.io).
