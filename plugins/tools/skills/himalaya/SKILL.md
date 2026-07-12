---
name: himalaya
description: Himalaya CLI (email) — pre-authed for Proton/Gmail/Stalwart accounts via IMAP, plus jmapcli for JMAP-only Stalwart ops. Use when sending, reading, searching, moving, or exporting email via the himalaya CLI, or discovering/managing mail accounts and folders. Covers account/folder discovery, the query DSL (flags-before-query), the non-interactive template send flow, raw .eml export, and Gmail Trash rescue within the 30-day window.
allowed-tools: Read, Bash, Grep
---

<!-- Auto-synced from ~/.claude/includes/himalaya.md — do not edit manually -->

# Himalaya CLI (email)

Himalaya is installed and pre-authed for all mail accounts (Proton via local Bridge, Gmail, Stalwart). Config: `~/Library/Application Support/himalaya/config.toml`. Upstream command reference: https://github.com/openclaw/openclaw/blob/main/skills/himalaya/SKILL.md

**Guardrails (always-on):** confirm with the user before sending or bulk deleting/moving; cite exact message IDs when acting; after ANY send error, check the Sent folder BEFORE retrying (duplicate-send risk).

## Accounts & folders

- `himalaya account list` to discover; **always pass `-a "<account>"`** when acting. Current accounts: `fries.pm proton` (default), `inetpeople proton`, `pulau-indah stalwart`, `deltahedge stalwart`, `ernesto.fries2 gmail`, `inetpeopleholding gmail`.
- Gmail folder names differ per account locale: `ernesto.fries2 gmail` → `[Google Mail]/All Mail`, `[Google Mail]/Sent Mail`, `[Google Mail]/Trash`, `[Google Mail]/Drafts`; `inetpeopleholding gmail` → `[Gmail]/...`. The sent/drafts/trash aliases are set in config.toml, but explicit `-f "<folder>"` is safer for All Mail (no alias).
- **Whole-thread work: search All Mail**, not INBOX/Sent — Sent misses received mail and vice versa.
- IDs are per-folder IMAP ids: the same message has DIFFERENT ids in different folders, and a move assigns a new id in the destination.

## Listing & searching

- **All CLI flags BEFORE the search query** — the query grammar swallows everything after it:
  ```
  himalaya envelope list -a "ernesto.fries2 gmail" -f "[Google Mail]/All Mail" --output json from dahm
  ```
  `... from dahm --output json` fails with ``cannot parse search emails query`` (the parser hits `-` and dies).
- Query DSL: space-separated filters, combinable with `and` / `or`: `from <word>`, `to <word>`, `subject <word>`, `before`/`after <date>`. **Single keywords work; quoted multi-word (`subject "Plot A32"`) has returned nothing** — search one distinctive word instead, filter the rest with jq.
- jq envelope shape: `from`/`to` are **objects** `{name, addr}`, not arrays — `.from.addr` works, `.to[0].addr` throws `Cannot index object with number`.
- stderr lines `imap_codec::response ... Rectified missing 'text'` are harmless codec noise. Don't blanket-`2>/dev/null` — you'll hide real errors; let them print and ignore.

## Reading & exporting

- `himalaya message read <id>` (add `-f` for non-INBOX); `--output json` for structured work.
- **Raw .eml export (evidence-grade original):** `himalaya message export -F <id> -d <dir>` — writes the full RFC822 message.

## Sending (non-interactive)

- Interactive editors don't work here; use the **template flow**:
  1. `himalaya template reply -a "<acct>" -f "<folder>" <id>` → emits headers (`From`/`To`/`In-Reply-To`/`Subject`) + quoted body.
  2. Write your own file: keep `From`/`To`/`In-Reply-To`, set any `Subject`, blank line, plain-text body. Keeping `In-Reply-To` preserves threading even with a changed Subject.
  3. `himalaya template send -a "<acct>" < file`
- Fresh (non-reply) mail: same template format without `In-Reply-To`, or `message send` with full RFC822.
- Gmail accounts are configured `message.send.save-copy = false` (Gmail's SMTP auto-saves to Sent; an IMAP append would duplicate — and the default `Sent` alias doesn't exist on the German-locale account).
- **Verify a send by listing Sent Mail, not by exit code:** a compound command can exit non-zero from a later pipe segment (e.g. a jq shape error) while `Message successfully sent!` was already printed.
- Attachments / rich compose: MML syntax in the template body.

## Moving / deleting / flags

- `himalaya message move -f "<src-folder>" "<dst-folder>" <id>` · `message delete <id>` · `flag add|remove <id> --flag seen`.
- **Gmail Trash auto-deletes after 30 days** — rescue evidence promptly: `message move -f "[Google Mail]/Trash" "[Google Mail]/All Mail" <id>`.
- Mass operations: IMAP via himalaya or a script beats webmail (Proton's select-all is page-only and slow). Confirm with the user first.

## Shell quirks (zsh)

- Quote `echo` separator args: `echo "==="` — a bare `===` triggers zsh path expansion and exits 1.

## JMAP for Stalwart mailboxes

`jmapcli` (https://boogie.digital/cli/) talks JMAP directly to the self-hosted Stalwart server — for account/mailbox-level ops himalaya's IMAP-only backend can't do (no released himalaya version has a `jmap` feature; `main`-branch-only — see the `self-hosted-email` runbook). `jmapcli accounts` lists configured accounts, JMAP URL, and the default (`efries@pulau-indah.com`, `efries@deltahedge.io` [default], both via https://mail.deltahedge.io).
