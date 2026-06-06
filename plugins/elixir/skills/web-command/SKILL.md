---
name: web-command
description: Web browsing in Claude Code using the `web` command. Use `web` for browser interactions: form submission, JavaScript execution, LiveView testing, screenshots, authenticated sessions. Use WebFetch for read-only content extraction (documentation, articles). Invoke when fetching pages, submitting forms, testing LiveView, or taking screenshots.
allowed-tools: Bash, Read
---

<!-- Auto-synced from ~/.claude/includes/web-command.md — do not edit manually -->

## Web Browsing: `web` vs `WebFetch`

- **`WebFetch`** — read-only content extraction (docs, articles). LLM-processed, clean.
- **`web` command** (`/usr/local/bin/web`) — real browser for forms, JS, LiveView, screenshots, sessions. Raw HTML→markdown (includes nav/chrome noise — bad for pure reading).

Repo: https://github.com/chrismccord/web

### When to Use Which

| Task | Tool |
|------|------|
| Read docs, articles, extract data from a page | `WebFetch` |
| Submit forms, Phoenix LiveView, screenshots, JS execution, session/cookie persistence, JS-rendered pages | `web` |

### `web` Usage

```bash
web https://example.com                           # default: 100k char markdown
web https://example.com --truncate-after 5000
web https://example.com --screenshot /tmp/page.png
web https://example.com --js "document.querySelector('button').click()"
```

### Phoenix LiveView Form Submission (auto-waits for `.phx-connected`)

```bash
web http://localhost:4000/users/log-in \
    --form "login_form" \
    --input "user[email]" --value "test@example.com" \
    --input "user[password]" --value "secret123" \
    --after-submit "http://localhost:4000/dashboard"
```

### Session Persistence

```bash
web --profile "myapp" http://localhost:4000/login ...
web --profile "myapp" http://localhost:4000/protected-page
```

### Key Flags

| Flag | Purpose |
|------|---------|
| `--raw` | Raw HTML instead of markdown |
| `--truncate-after N` | Limit output (default 100000) |
| `--screenshot PATH` | Full-page screenshot |
| `--form ID` / `--input NAME` / `--value V` / `--after-submit URL` | Form submission |
| `--js CODE` | Run JS after page loads |
| `--profile NAME` | Named session profile |
