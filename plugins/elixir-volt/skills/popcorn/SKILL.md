---
name: popcorn
description: "Popcorn: run Elixir in the browser via WebAssembly. Use when building client-side Elixir apps, offline-first tools, browser-based calculators, or privacy-preserving analytics. Covers Popcorn setup, JavaScript interop, WASM limitations, and example patterns."
allowed-tools: Read, Bash
---

# Popcorn: Client-Side Elixir in the Browser

Popcorn is a library by Software Mansion that runs Elixir in browsers via WebAssembly. It enables offline-first, client-side Elixir applications with JavaScript interoperability.

## Architecture

```
Elixir Code → mix popcorn.cook → WASM Bundle → Browser
                                      ↓
                                  AtomVM (tiny Erlang VM)
                                      ↓
                                  WebAssembly Runtime
```

**How it works:**
1. Your Elixir code compiles to BEAM bytecode
2. `mix popcorn.cook` bundles it with AtomVM (a minimal Erlang VM)
3. AtomVM runs as WebAssembly in the browser
4. JavaScript bridge enables bidirectional communication

## When to Use Popcorn

### Ideal Use Cases

| Use Case | Why Popcorn Works |
|----------|-------------------|
| **Offline-first apps** | No server required, runs entirely in browser |
| **Client-side calculators** | P&L, position sizing, tax calculations |
| **Privacy-preserving analytics** | Data never leaves the browser |
| **Form validation** | Complex business logic without server round-trips |
| **Local data processing** | Filtering, sorting, transformations |
| **Educational tools** | Elixir REPL/playground in the browser |
| **Prototyping** | Quick demos without deploying a backend |

### NOT Recommended For

| Use Case | Why Not |
|----------|---------|
| **Real-time trading** | Latency-critical, needs persistent connections |
| **High-frequency data** | Streaming requires server-side infrastructure |
| **Persistent state** | Page reloads reset GenServer state |
| **Large datasets** | Browser memory constraints |
| **Server-side secrets** | API keys can't be safely stored in browser |
| **Database access** | No direct database connections from WASM |

## Project Setup

### Requirements

- **OTP 26.0.2** (currently pinned, working to lift)
- **Elixir 1.17.3** (currently pinned, working to lift)

### Installation

```elixir
# mix.exs
def application do
  [
    extra_applications: [],
    mod: {MyApp.Application, []}
  ]
end

def deps do
  [
    {:popcorn, "~> 0.1.0"}
  ]
end
```

### Configuration

```elixir
# config/config.exs
import Config
config :popcorn, out_dir: "static/wasm"
```

### Application Module

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MyApp.Worker
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Minimal Worker

```elixir
# lib/my_app/worker.ex
defmodule MyApp.Worker do
  use GenServer

  @process_name :main

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: @process_name)
  end

  @impl true
  def init(_init_arg) do
    Popcorn.Wasm.register(@process_name)
    IO.puts("Hello from WASM!")
    {:ok, %{}}
  end
end
```

### Build & Serve

```bash
# Install dependencies
mix deps.get

# Build WASM artifacts
mix popcorn.cook

# Generate a simple server
mix popcorn.simple_server

# Run the server
elixir server.exs
# Visit http://localhost:4000
```

### HTML Integration

```html
<!-- index.html -->
<html>
  <script type="module">
    import { Popcorn } from "./wasm/popcorn.js";
    await Popcorn.init({ onStdout: console.log });
  </script>
  <body></body>
</html>
```

### Required HTTP Headers

WASM requires these headers (included in Popcorn's servers):

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

### Live Reloading (Development)

```bash
# Generate dev server
mix popcorn.dev_server

# Run with live reload
elixir dev_server.exs
```

```html
<!-- Add dev_server.js for live reload -->
<html>
  <script type="text/javascript" src="/dev_server.js"></script>
  <script type="module">
    import { Popcorn } from "./wasm/popcorn.js";
    await Popcorn.init({ onStdout: console.log });
  </script>
  <body></body>
</html>
```

## JavaScript Interoperability

### Calling JS from Elixir

Use `Popcorn.Wasm.run_js/3` to execute JavaScript:

```elixir
# Run JS and get tracked references
{:ok, refs} = Popcorn.Wasm.run_js("""
  ({ args }) => {
    const n = args.n;
    return [n * 2, n * 3];
  }
""", %{n: 5})

# Get values from tracked objects
values = Popcorn.Wasm.get_tracked_values!(refs)
# => [10, 15]
```

### Run JS Options

```elixir
# Return values directly instead of tracked refs
{:ok, value} = Popcorn.Wasm.run_js("""
  ({ args }) => [args.x + args.y]
""", %{x: 1, y: 2}, return: :value)
# => {:ok, 3}
```

### DOM Manipulation

```elixir
# Update DOM element
Popcorn.Wasm.run_js!("""
  ({ args }) => {
    document.getElementById(args.id).innerText = args.text;
    return [];
  }
""", %{id: "result", text: "Hello from Elixir!"})
```

### Register Event Listeners

```elixir
# Listen for button clicks
{:ok, listener_ref} = Popcorn.Wasm.register_event_listener(:click,
  target_node: button_ref,
  receiver_name: "main",
  event_keys: [:target, :type]
)

# In your GenServer, handle incoming events
def handle_info({:emscripten, {:cast, data}}, state) do
  Popcorn.Wasm.handle_message!({:emscripten, {:cast, data}}, fn
    {:wasm_cast, %{type: "click"}} ->
      IO.puts("Button clicked!")
      :ok
  end)
  {:noreply, state}
end

# Cleanup when done
Popcorn.Wasm.unregister_event_listener(listener_ref)
```

### Calling Elixir from JS

JavaScript can send messages to Elixir processes:

```javascript
// In your HTML/JS
import { Popcorn } from "./wasm/popcorn.js";

const popcorn = await Popcorn.init({ onStdout: console.log });

// Send a message to the registered Elixir process
popcorn.cast("main", { action: "calculate", value: 42 });

// Or call and await response
const result = await popcorn.call("main", { action: "get_result" });
```

```elixir
# In your GenServer
def handle_info({:emscripten, msg}, state) do
  Popcorn.Wasm.handle_message!(msg, fn
    {:wasm_cast, %{action: "calculate", value: n}} ->
      IO.puts("Calculating: #{n * 2}")
      :ok

    {:wasm_call, %{action: "get_result"}, promise} ->
      {:resolve, 42, :ok}
  end)
  {:noreply, state}
end
```

### Data Type Mapping

| Elixir | JavaScript |
|--------|------------|
| `integer` | `number` |
| `float` | `number` |
| `binary/string` | `string` |
| `list` | `array` |
| `map` | `object` |
| `atom` | `string` |
| `tuple` | `array` |
| `boolean` | `boolean` |
| `nil` | `null` |

## Limitations & Workarounds

### No Direct API Calls

WASM can't make HTTP requests directly. Use the JS bridge:

```elixir
# DON'T: Direct HTTP (won't work)
# HTTPoison.get("https://api.example.com/data")

# DO: Bridge through JavaScript
{:ok, [data]} = Popcorn.Wasm.run_js("""
  async ({ args }) => {
    const response = await fetch(args.url);
    const data = await response.json();
    return [data];
  }
""", %{url: "https://api.example.com/data"}, return: :value)
```

### No State Persistence Across Page Reloads

GenServer state resets on reload. Use localStorage via JS:

```elixir
# Save state to localStorage
def save_state(state) do
  Popcorn.Wasm.run_js!("""
    ({ args }) => {
      localStorage.setItem('app_state', JSON.stringify(args.state));
      return [];
    }
  """, %{state: state})
end

# Restore state on init
def restore_state do
  {:ok, [state]} = Popcorn.Wasm.run_js("""
    ({ args }) => {
      const saved = localStorage.getItem('app_state');
      return [saved ? JSON.parse(saved) : null];
    }
  """, %{}, return: :value)
  state
end
```

### Limited OTP Features

Some OTP features have limited support:
- **Supervision trees**: Fully supported
- **GenServer**: Fully supported
- **ETS**: Limited support
- **Ports/NIFs**: Not supported (no native code in WASM)
- **File I/O**: Not supported (no filesystem)
- **Network**: Must bridge through JS

### Performance Considerations

| Operation | Native Elixir | Popcorn/WASM |
|-----------|--------------|--------------|
| Computation | Baseline | ~2-5x slower |
| Pattern matching | Fast | Comparable |
| Process spawning | Fast | Slightly slower |
| JS bridge calls | N/A | Overhead per call |

**Tips:**
- Batch JS calls to reduce bridge overhead
- Keep hot paths in pure Elixir
- Use tracked objects instead of copying large data

### Browser Memory Constraints

Browser tabs have memory limits (~2-4GB typically):

```elixir
# BAD: Load everything at once
data = load_huge_dataset()  # May crash

# GOOD: Stream or paginate
data
|> Stream.chunk_every(100)
|> Enum.each(&process_batch/1)
```

## Example Patterns

### Client-Side Calculator

```elixir
defmodule Calculator.Worker do
  use GenServer

  @process_name :calculator

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: @process_name)
  end

  @impl true
  def init(_) do
    Popcorn.Wasm.register(@process_name)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:emscripten, msg}, state) do
    Popcorn.Wasm.handle_message!(msg, fn
      {:wasm_call, %{op: "pnl", entry: entry, exit: exit, size: size}, _promise} ->
        pnl = (exit - entry) * size
        {:resolve, %{pnl: pnl, percentage: pnl / (entry * size) * 100}, :ok}

      {:wasm_call, %{op: "position_size", capital: cap, risk: risk, stop: stop}, _promise} ->
        size = (cap * risk / 100) / stop
        {:resolve, %{size: size, risk_amount: cap * risk / 100}, :ok}
    end)
    {:noreply, state}
  end
end
```

### Offline Data Filter

```elixir
defmodule DataFilter.Worker do
  use GenServer

  @process_name :filter

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{data: []}, name: @process_name)
  end

  @impl true
  def init(state) do
    Popcorn.Wasm.register(@process_name)
    {:ok, state}
  end

  @impl true
  def handle_info({:emscripten, msg}, state) do
    Popcorn.Wasm.handle_message!(msg, fn
      {:wasm_call, %{action: "load", data: data}, _promise} ->
        {:resolve, :ok, %{state | data: data}}

      {:wasm_call, %{action: "filter", field: field, value: value}, _promise} ->
        filtered = Enum.filter(state.data, &(&1[field] == value))
        {:resolve, filtered, state}

      {:wasm_call, %{action: "sort", field: field, dir: dir}, _promise} ->
        sorter = if dir == "asc", do: &<=/2, else: &>=/2
        sorted = Enum.sort_by(state.data, &(&1[field]), sorter)
        {:resolve, sorted, state}
    end)
    {:noreply, state}
  end
end
```

### Form Validation

```elixir
defmodule FormValidator.Worker do
  use GenServer

  @process_name :validator

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: @process_name)
  end

  @impl true
  def init(_) do
    Popcorn.Wasm.register(@process_name)
    {:ok, %{}}
  end

  @impl true
  def handle_info({:emscripten, msg}, state) do
    Popcorn.Wasm.handle_message!(msg, fn
      {:wasm_call, %{action: "validate", form: form}, _promise} ->
        errors = validate_form(form)
        {:resolve, %{valid: errors == [], errors: errors}, :ok}
    end)
    {:noreply, state}
  end

  defp validate_form(form) do
    []
    |> validate_required(form, :email, "Email is required")
    |> validate_email_format(form)
    |> validate_required(form, :password, "Password is required")
    |> validate_min_length(form, :password, 8, "Password must be at least 8 characters")
  end

  defp validate_required(errors, form, field, msg) do
    if blank?(form[field]), do: [{field, msg} | errors], else: errors
  end

  defp validate_email_format(errors, form) do
    email = form[:email] || ""
    if String.contains?(email, "@"), do: errors, else: [{:email, "Invalid email format"} | errors]
  end

  defp validate_min_length(errors, form, field, min, msg) do
    value = form[field] || ""
    if String.length(value) >= min, do: errors, else: [{field, msg} | errors]
  end

  defp blank?(nil), do: true
  defp blank?(""), do: true
  defp blank?(_), do: false
end
```

## Mix Tasks Reference

| Task | Description |
|------|-------------|
| `mix popcorn.cook` | Build WASM artifacts to `out_dir` |
| `mix popcorn.simple_server` | Generate simple HTTP server script |
| `mix popcorn.dev_server` | Generate dev server with live reload |
| `mix popcorn.build_runtime` | Build AtomVM from source |

## Resources

- **GitHub**: https://github.com/software-mansion/popcorn
- **HexDocs**: https://hexdocs.pm/popcorn
- **Examples**: https://popcorn.swmansion.com
- **Language Tour**: https://elixir-language-tour.swmansion.com
- **AtomVM**: https://github.com/atomvm/AtomVM

## Status

Popcorn is in **early stages** (v0.1.0). Expect breaking changes. Report issues on GitHub.

**Current limitations being addressed:**
- OTP/Elixir version constraints
- Expanding OTP feature support
- Performance optimizations
