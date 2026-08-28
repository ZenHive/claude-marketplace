#!/usr/bin/env bash
# PreToolUse:Bash|Edit|Write|MultiEdit — BLOCK filing a task that is an
# INSTANCE of a class already represented by existing tasks.
#
# The recurring failure mode this guards: findings arrive one at a time, so the
# task gets titled after the symptom in front of you, and the CLASS is never
# represented anywhere. Worked example from the bourse roadmap:
#
#   658 "bybit dated future carries the venue-native date form"        done
#   660 "...STILL carries DDMMMYY after the 658 pass-through"          done
#   661 "bybit InverseFutures native ids are quarterly codes"          superseded
#   + BUGS.md 2026-08-28: DOGEUSDT-28AUG26 does not normalize          still open
#
# Four instances, three tasks, class still unfixed. Same shape at 664 (deribit
# option notional, the instance) -> 666 ("derived per venue with no shared
# rule", the class) — the class task was filed AFTER the instance shipped.
#
# Why an existing gate does not catch this: `task-writing`'s "refine, don't
# duplicate" merges against the PENDING set. 658 was already `done` when 660
# was filed, so a sibling of a LANDED task passes that filter every time. This
# hook searches every status.
#
# Fires on: `rmap new` (Bash) and a `[[task]]`-shaped edit to */roadmap/tasks.toml
# (Edit|Write|MultiEdit) — closing the same bypass DD-5 closes for DD-3 — when
# the proposed title shares strong tokens with existing task titles.
# Silent on: no roadmap in cwd, no extractable title, no sibling above threshold,
# and any missing dependency (jq/python3/rmap) — this hook fails OPEN.
#
# Bypass, deliberately evidence-shaped: put RMAP_SIBLING_CHECKED=1 in the
# command (Bash) or as a comment line in the task block (Edit), naming which
# siblings you checked and why this is not the same class. The justification
# then lives next to the task, where the next session reads it.

set -eo pipefail

emit_suppress() { jq -n '{"suppressOutput": true}'; exit 0; }

emit_deny() {
  jq -n --arg reason "$1" --arg msg "$2" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    },
    systemMessage: $msg
  }'
  exit 0
}

command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0

INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[[ -z "$CWD" || "$CWD" == "null" ]] && CWD="$PWD"

case "$TOOL_NAME" in
  Bash)
    HAYSTACK=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    [[ -z "$HAYSTACK" || "$HAYSTACK" == "null" ]] && emit_suppress
    echo "$HAYSTACK" | grep -qE '(^|[[:space:]]|;|&|\|)rmap[[:space:]]+new([[:space:]]|$)' \
      || emit_suppress
    ;;
  Edit|Write|MultiEdit)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    case "$FILE" in
      */roadmap/tasks.toml) ;;
      *) emit_suppress ;;
    esac
    case "$TOOL_NAME" in
      Write)     HAYSTACK=$(echo "$INPUT" | jq -r '.tool_input.content // empty') ;;
      Edit)      HAYSTACK=$(echo "$INPUT" | jq -r '.tool_input.new_string // empty') ;;
      MultiEdit) HAYSTACK=$(echo "$INPUT" | jq -r '[.tool_input.edits[]?.new_string] | join("\n")') ;;
    esac
    # Only an edit that introduces a task block is a filing.
    echo "$HAYSTACK" | grep -qE '^[[:space:]]*\[\[task' || emit_suppress
    ;;
  *) emit_suppress ;;
esac

# Acknowledged bypass — the caller named the siblings they checked.
echo "$HAYSTACK" | grep -q 'RMAP_SIBLING_CHECKED=1' && emit_suppress

command -v rmap >/dev/null 2>&1 || exit 0
EXISTING=$(cd "$CWD" 2>/dev/null && rmap list --json --fields id,title,status 2>/dev/null) || emit_suppress
[[ -z "$EXISTING" ]] && emit_suppress

export RMAP_EXISTING="$EXISTING"

REPORT=$(printf '%s' "$HAYSTACK" | python3 -c '
import json, re, sys, os, math

haystack = sys.stdin.read()
try:
    existing = json.loads(os.environ.get("RMAP_EXISTING", "") or "[]")
except Exception:
    sys.exit(0)
if isinstance(existing, dict):
    existing = existing.get("tasks", []) or []
if not existing:
    sys.exit(0)

titles = re.findall(r"""title\s*=\s*["'"'"'](.+?)["'"'"']""", haystack)
if not titles:
    sys.exit(0)

STOP = set("""a an the and or but not no nor so that this these those there here
is are was were be been being has have had do does did can cannot could should
would will shall may might must of in on at to for from with without into onto
by as if then than when while every each one only just still never always both
all any some its their they them we our you your what which who whom how why
where because after before during per own more most less least new old same
other another such via using use used make makes made get gets got give also
even much many few first last next up down out off over under again
task tasks roadmap""".split())

def toks(s):
    return {t for t in re.split(r"[^A-Za-z0-9]+", s.lower())
            if len(t) >= 4 and t not in STOP}

corpus = []
for t in existing:
    tid = t.get("id"); title = t.get("title") or ""; status = t.get("status") or "?"
    corpus.append((tid, title, status, toks(title)))

df = {}
for _, _, _, tk in corpus:
    for w in tk:
        df[w] = df.get(w, 0) + 1
n = max(len(corpus), 1)

out = []
for proposed in titles:
    ptk = toks(proposed)
    if not ptk:
        continue
    hits = []
    for tid, title, status, tk in corpus:
        shared = ptk & tk
        if not shared:
            continue
        # Precision over recall: a single shared word — even a rare one — is
        # not a class signal ("release", "changelog"). A false positive here
        # trains the caller to reflex-bypass, which costs more than a miss.
        if len(shared) < 2:
            continue
        specific = any(df.get(w, n) <= 5 for w in shared)
        if not specific and len(shared) < 3:
            continue
        score = sum(math.log(1 + n / df.get(w, 1)) for w in shared)
        hits.append((score, tid, status, title, sorted(shared, key=lambda w: df.get(w, 0))))
    hits.sort(reverse=True)
    if hits:
        out.append((proposed, hits[:6]))

if not out:
    sys.exit(0)

lines = []
for proposed, hits in out:
    lines.append("Proposed: %s" % proposed)
    for _, tid, status, title, shared in hits:
        lines.append("  - %s [%s] %s" % (tid, status, title))
        lines.append("      shared: %s" % ", ".join(shared))
    lines.append("")
print("\n".join(lines).rstrip())
' 2>/dev/null) || emit_suppress

[[ -z "$REPORT" ]] && emit_suppress

emit_deny \
"[DD-8] This task shares its surface with tasks that already exist — including \`done\` and \`superseded\` ones:

$REPORT

Before filing, answer one question: is your finding an INSTANCE of the same class as those, or genuinely a different surface?

- Same class -> do NOT file the instance. Either widen the scope to the class (the invariant, stated once, that makes the next instance impossible), or fold the finding into the existing task.
- Different surface -> re-issue with \`RMAP_SIBLING_CHECKED=1\` in the command (or as a comment line in the task block), naming the ids you checked and why this is not the same class.

Why the usual dedupe misses this: \"refine, don't duplicate\" merges against the PENDING set, so a sibling of a LANDED task passes it every time. Worked example (bourse): 658 -> 660 (\"still ... after the 658 pass-through\") -> 661, three tasks on one symbol class, and a fourth instance still open in BUGS.md." \
"dev-discipline [DD-8]: proposed task overlaps existing tasks (all statuses) — file the class, not the instance"
