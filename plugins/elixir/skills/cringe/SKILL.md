---
name: cringe
description: cringe — OTP-native terminal UI (TUI) toolkit for Elixir. Use when building a supervised terminal app with a canvas/painter repaint model, DSL widget primitives, and Ghostty TTY input. Alpha, and redundant with the drafter framework — see the drafter-vs-cringe decision table. Covers Cringe.App, the process model, widgets, and Cringe.Case/Driver test helpers.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/cringe.md — do not edit manually -->

## Cringe — OTP-Native TUI Toolkit (early alpha)

Document-first, OTP-supervised terminal UI for Elixir. No template language: compose
UIs from plain Elixir data structures, render deterministically, test with ExUnit helpers.

**Min version: `{:cringe, "~> 0.5.0"}`.** Early alpha — APIs may change before 1.0.

**Core runtime depends on `{:ghostty, "~> 0.4.9"}`** for TTY input; not optional.

**Three required `Cringe.App` callbacks:** `init/1`, `handle_event/2`, `render/1`.

**Rendering pipeline:** Document → Layout.Node tree → Draw/Canvas → Frame → Painter → Backend.
Only changed lines repaint; painter compares frames before emitting ANSI sequences.

**Caveat:** `ghostty` is a required runtime dep, not just optional input glue — ensure it
compiles on CI (may need `Ghostty.TTY` native components). Library is pre-1.0; check the
changelog before upgrading minor versions.

**Does NOT cover:** drafter (separate TUI lib — see comparison below), LiveView-based TUI,
SSH multi-session, mouse support, tree-sitter syntax highlighting.

---

**Portfolio fit — drafter vs cringe decision:** Your own `drafter` library is the
production-grade TUI choice (30+ widgets, SSH, OTP 28 raw mode, animation engine); use
cringe when you want a lightweight dependency with fewer moving parts, or when the
`ghostty`-input + painter model better fits the context (e.g. integrating into a vibe
agent TUI that already uses ghostty). See comparison table below.

---

### Cringe.App (supervised process model)

```elixir
defmodule Counter do
  use Cringe.App

  # Required — returns {:ok, initial_state} | {:stop, reason}
  def init(_opts), do: {:ok, %{count: 0}}

  # Required — returns {:noreply, state} | {:stop, reason}
  def handle_event(%Cringe.Event.Key{key: :up}, state),
    do: {:noreply, %{state | count: state.count + 1}}
  def handle_event(_event, state),
    do: {:noreply, state}

  # Required — returns Cringe.Document.t()
  def render(state) do
    text("Count: #{state.count}")
  end
end
```

**Starting the app:**

```elixir
# Linked to calling process — dies with caller
{:ok, _pid} = Cringe.run(Counter,
  backend: {Cringe.Runtime.Backend.Terminal, alternate_screen: true},
  ansi: true
)

# OTP supervision — survives caller exit; returns supervisor pid
{:ok, _sup} = Cringe.run_supervised(Counter, ansi: true)
```

`run/2` → `GenServer.on_start()`. `run_supervised/2` → `Supervisor.on_start()`.
The supervisor manages `Cringe.Runtime` + `TerminalSession` + (optional) `TickManager`
child processes. Pass `:child_supervisor` option to plug into your own `DynamicSupervisor`.

### Event Types

| Struct | When |
|---|---|
| `%Cringe.Event.Key{key: atom}` | Key press (`:up`, `:down`, `:enter`, `:esc`, etc.) |
| `%Cringe.Event.Text{text: String.t()}` | Printable character input |
| `%Cringe.Event.Resize{width: integer, height: integer}` | Terminal resize |
| `%Cringe.Event.Tick{}` | Periodic tick (requires `TickManager` / tick interval config) |

Input comes through `Ghostty.TTY` — semantic events, not raw escape sequences.

### DSL Primitives

Import via `use Cringe` or `import Cringe`. All return `Cringe.Document.t()`.

```elixir
text("Label", color: :green, bold: true)           # styled text node
row([text("a"), text("b")], gap: 1)                # horizontal, gap in cells
column([text("a"), text("b")], gap: 1)             # vertical, gap in rows

box padding: 1 do                                  # padded wrapper, block syntax
  column gap: 1 do
    text("Title", color: :cyan, bold: true)
    progress(value: 0.42, width: 16, label: "Build")
  end
end

# Render to string (for testing / non-terminal output)
Cringe.render(doc, width: 80)                      # :: String.t()
Cringe.frame(doc, width: 80)                       # :: Cringe.Frame.t()
```

### Widget Layer

**Render-only** (stateless DSL calls):

| Widget | Call | Notes |
|---|---|---|
| `spinner/1` | `spinner(frames: ["⠋", "⠙", ...], index: n)` | Pass index from app state for animation |
| `progress/1` | `progress(value: 0.5, width: 20, label: "Build")` | Value 0.0–1.0 |
| `input/1` | `input(value: "text", cursor: 4)` | Render-only; pair with `Widgets.Input.State` |
| `select/1` | `select(items: [...], selected: 0)` | Render-only |

**Stateful widget structs** (explicit state management in your app):

| Module | `new/1` → state | `update/2` returns |
|---|---|---|
| `Cringe.Widgets.Input.State` | `new(value: "")` | `{:ok, s}` / `{:cancel, s}` |
| `Cringe.Widgets.SelectList` | `new(items: [...])` | `{:ok, s}` / `{:select, item, s}` |
| `Cringe.Widgets.Editor.State` | `new(value: "")` | `{:ok, s}` — tracks line/col |
| `Cringe.Widgets.Menu` | `new(sections: [...])` | `{:ok, s}` / `{:select, action, s}` |
| `Cringe.Widgets.Dialog` | `new(title: ..., body: ..., actions: [...])` | `{:select, action, s}` |
| `Cringe.Widgets.Tabs` | `new(tabs: [...])` | `{:ok, s}` |
| `Cringe.Widgets.Table` | `new(columns: [...], rows: [[...]])` | `{:ok, s}` / `{:select, row, s}` |
| `Cringe.Widgets.Form` | `new(fields: [...])` | Focus delegation to child widgets |

Pattern: call `render(widget_state)` to get the `Document.t()`, call `update(widget_state, event)` to advance state.

### Layout, Focus, Overlays

```elixir
# Layout engine — positions documents into a node tree
tree = Cringe.Layout.Engine.layout(doc, width: 80, height: 24)

# Look up by ID, find focusable ring, hit-test by position
Cringe.Layout.find(tree, :my_input_id)
Cringe.Layout.focusable(tree)                      # [{id, node}, ...]
Cringe.Layout.at(tree, x, y)                       # hit detection

# Deterministic focus ring
focus = Cringe.Focus.new(ids)
focus = Cringe.Focus.next(focus)
Cringe.Focus.current(focus)

# Overlays — layer composition without runtime coupling
Cringe.Runtime.show_overlay(app, :dialog, content, anchor: :center)
Cringe.Runtime.hide_overlay(app, :dialog)
Cringe.Runtime.clear_overlays(app)
```

### Testing (Cringe.Case + Cringe.Driver)

**`Cringe.Case`** — wraps `use ExUnit.Case` with convenience imports:

```elixir
defmodule MyWidgetTest do
  use ExUnit.Case, async: true
  use Cringe.Case    # imports Cringe DSL + Cringe.Assertions

  test "renders a box" do
    assert_render box(text("hi"), padding: 1), """
    ╭────╮
    │    │
    │ hi │
    │    │
    ╰────╯
    """
  end

  test "renders an app frame" do
    {:ok, app} = Cringe.Driver.start(Counter)
    assert_app_text app, "Count: 0"
  end
end
```

`assert_render/2,3` — renders document to string and compares against heredoc.
Heredoc indentation is normalized automatically (`clean_heredoc/1` strips common indent).

**`Cringe.Driver`** — drive apps under test:

```elixir
{:ok, app} = Cringe.Driver.start(MyApp)           # spawn in test backend
:ok        = Cringe.Driver.keys(app, [:up, :up, :enter])  # dispatch keystrokes
true       = Cringe.Driver.await_state(app, fn s -> s.count == 2 end)
true       = Cringe.Driver.await_frame(app, fn frame -> frame =~ "Count: 2" end)
```

`await_state/2` and `await_frame/3` retry with configurable backoff; return boolean.
Test backend renders deterministically — no Ghostty TTY required in tests.

### Painter / Canvas (repaint model)

The Painter holds the last-emitted `Frame.t()`. On each repaint cycle:
1. App's `render/1` produces a `Document.t()`
2. Layout engine computes positions → `Layout.Node` tree
3. Canvas rasterises the tree to a fixed-size `Frame.t()`
4. Painter diffs against the previous frame; emits only changed rows as ANSI sequences
5. Terminal width is clamped to `max(width - 1, 1)` to avoid cursor-wrap artifacts

On `Cringe.Event.Resize`, painter rebuilds from scratch. The Backend (Terminal or Test)
owns the final write/buffer; swap backends without changing app code.

### Drafter vs Cringe

Your `drafter` library is the production-ready choice. Use this table to decide:

| Concern | drafter | cringe |
|---|---|---|
| Widget count | 30+ (DataTable, Tree, Charts, Markdown, CodeView, …) | ~10 core widgets |
| SSH multi-session | Yes | No |
| Mouse support | Yes | No |
| Animations | 30+ easing functions | No |
| Theming | HSL/RGB/hex, full theme system | Basic color opts on `text/2` |
| Syntax highlight | Optional tree-sitter | No |
| Navigation | Push/pop screens, modals, panels, toasts | Overlay layer only |
| Focus model | Automatic focus management | Explicit `Cringe.Focus` ring |
| Input backend | OTP 28 raw terminal mode | `ghostty ~> 0.4.9` (required dep) |
| OTP architecture | GenServer + PubSub (global registry — known pre-1.0 issue) | `run/run_supervised`, `DynamicSupervisor` hook |
| Test helpers | Headless ExUnit harness | `Cringe.Case` + `Cringe.Driver` |
| Status | 0.2.0 (announced Mar 2026) | 0.5.0 early alpha |
| Dep weight | Heavier (theming, SSH, tree-sitter optional) | Lighter — ghostty + BEAM only |

**Use cringe when:** you're integrating into a `ghostty`-based pipeline (e.g. vibe agent
TUI), you want the painter's diffing model without pulling in drafter's full dep tree, or
you need a narrow-surface widget set with first-class ExUnit helpers. **Use drafter when:**
you need rich widgets, SSH, mouse, animations, or a theme system.

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| Compilation fails on CI | `ghostty ~> 0.4.9` has native components | Add ghostty NIF compilation step in CI; see ghostty docs |
| Overlay not clearing on state reset | `clear_overlays/1` not called | Call `Cringe.Runtime.clear_overlays(app)` before re-rendering |
| `await_frame/3` returns `false` in tests | Async repaint race | Pass `timeout:` or increase retry opts to `await_frame` |
| `assert_render` indentation mismatch | Heredoc has extra leading spaces | `Cringe.Case` normalizes common indent; don't mix tab/space in expected |
| `handle_event` never reached for `Tick` | `TickManager` not started | Pass `tick_interval:` option to `run/2` or `run_supervised/2` |
| Painter emits garbage on narrow terminal | Width includes scroll column | Expected — painter clamps to `max(width - 1, 1)` |

### DO NOT

1. Call `Cringe.render/2` in the `render/1` callback — `render/1` must return `Document.t()`, not a string.
2. Hold `Layout.Node` trees across repaint cycles — recompute fresh each cycle.
3. Mutate widget state inside `render/1` — keep side effects in `handle_event/2`.
4. Use the Terminal backend in ExUnit tests — use `Cringe.Driver.start/1` (Test backend).
5. Pin `{:ghostty, "~> 0.4"}` expecting API stability — cringe pins `0.4.9`; match exactly.
6. Share one `Cringe.Runtime` pid across multiple SSH sessions — cringe has no session isolation; use drafter for SSH.

### Dependencies

```elixir
# mix.exs
{:cringe, "~> 0.5.0"}
# ghostty is a transitive runtime dep — pulled automatically
# Dev/test only (cringe's own toolchain, not required in your app):
# benchee ~> 1.3, credo ~> 1.7, dialyxir ~> 1.4, reach ~> 2.6
```
