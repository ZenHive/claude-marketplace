---
name: portfolio-strategy
description: Apply the power-law portfolio rule to cross-repo decisions. Use when starting, continuing, or killing a project; evaluating portfolio health across repos; deciding where to spend the next week of attention; or reviewing a strategy document like api-strategy.md. NOT for within-project task prioritization (use roadmap-planning). Classifies bets as normal-distribution (consistency wins) vs power-law (outliers dominate), checks independence and activation energy, and enforces kill criteria.
allowed-tools: Read, Write
---

<!-- Auto-synced from ~/.claude/includes/portfolio-strategy.md — do not edit manually -->

## Portfolio Strategy: Power-Law Portfolio Rule

Apply this frame when evaluating whether to **start, continue, or kill** a project or cross-repo bet.

**Scope:** Cross-repo / portfolio-level decisions. NOT for within-project task prioritization — use `roadmap-planning` (D/B/U scoring) for that.

### 1. Classify the game first

State explicitly which distribution domain the decision lives in:

- **Normal-distribution** — consistency wins. Trading execution, hedging, ops, recurring per-call revenue, uptime-critical infrastructure. Optimize for risk control and steady output. **Do NOT apply the rest of this rule.**
- **Power-law** — outliers dominate. Distribution plays (open-source libraries, Hex publishes), market-creation bets, content, research, moonshots. One hit pays for many misses.

Mixing these up is the single most common error. Demanding moonshot thinking from a normal-distribution business produces chaos; demanding steady returns from a power-law bet produces premature kills.

### 2. For power-law bets — check portfolio health

- **Independence** — are current bets genuinely independent (different failure modes, different markets), or correlated variants of one thesis? Correlated bets all fail together.
- **Bounded budget** — does each active bet have an explicit time / capital / attention cap AND an explicit kill criterion?
- **Activation energy** — does each bet get enough fuel to actually compete, or is the portfolio spread so thin that none can catch fire?

### 3. Before adding a new bet

- Is downside capped?
- Is upside asymmetric (10x+ possible)?
- **What existing bet gets deprioritized or killed to fund this?** No free additions.

### 4. Before killing a bet

- Has it had a fair shot, or is this bailing before activation energy kicked in?
- Is it failing on its own terms, or just slower than hoped? Power laws are slow until they aren't.
- Has it hit its kill criterion, or is "I'm bored / frustrated" driving the call?

### 5. Push back when the operator is

- Running too many parallel bets for any to get real momentum.
- Treating a power-law domain like normal (demanding steady returns from moonshots).
- Treating a normal domain like power-law (taking outlier risk where consistency pays).
- Keeping zombie projects alive past their kill criterion out of sunk cost.
- Adding a new bet without deprioritizing an existing one.
- Running a distribution play (Hex publish, content) on a weekly-revenue metric — wrong metric.

### Tone

Be direct. Structural feedback on portfolio health ("you're spread too thin", "that's three correlated bets, not three bets") beats polite validation. The operator explicitly asked for this — deliver it.
