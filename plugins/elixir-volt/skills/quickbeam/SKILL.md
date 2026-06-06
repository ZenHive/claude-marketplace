---
name: quickbeam
description: "QuickBEAM JavaScript runtime for the BEAM — run JS libraries, npm packages, and async code inside Elixir GenServers via Zig NIFs. ALWAYS use this skill when you need to execute JavaScript at runtime, load npm browser bundles, bridge Elixir and JS with handlers, manage JS runtime pools or lightweight contexts, or evaluate TypeScript on the BEAM. Covers start/eval/call lifecycle, correct browser global stub pattern (critical — the common pattern is wrong), handler pattern (Beam.call/Beam.callSync), Pool and ContextPool for concurrency, DOM access, and the define-then-call recipe. Use this even if you think you know QuickBEAM — it contains runtime-verified corrections."
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/quickbeam.md — do not edit manually -->

## QuickBEAM: JavaScript Runtime for the BEAM

QuickJS-NG as a Zig NIF. Each runtime is a GenServer with a persistent JS context — run JS libraries, bridge Elixir↔JS bidirectionally. No Node.js.

**Min version: `{:quickbeam, "~> 0.10.15"}`.** Requires `oxc ~> 0.15.0` (atom-keyed AST — see `oxc.md`). Ships `QuickBEAM.Cover` (JS line coverage via `mix test --cover`), `Beam.XML.parse` (xmerl), and a default `max_stack_size` of 8MB. The bundler exposes oxc's `module_types` per-extension loader option. Vendored C symbols are hidden in the native library, so QuickBEAM can be loaded alongside other Zig/C NIFs without symbol collisions.

**`npm_ex` is optional.** QuickBEAM does not pull `npm_ex` into your dep tree. The runtime / `eval` / `call` / `load_module` path works without it. Add `{:npm, "~> 0.7.4"}` to your own `mix.exs` only when you actually need `mix npm.install`, lockfile resolution, or browser-bundle hot-loading. The public `QuickBEAM.JS` surface (`parse`, `transform`, `minify`, `bundle`, `bundle_file`) does NOT depend on npm.

**Does NOT cover:** static JS/TS analysis (→ OXC), installing npm packages (→ `mix npm.install`), frontend builds (→ Volt).

### Lifecycle

```elixir
# Start a runtime (GenServer)
{:ok, rt} = QuickBEAM.start()

# With options
{:ok, rt} = QuickBEAM.start(
  name: MyApp.JSRuntime,       # register name
  script: "priv/js/app.ts",   # file to run at startup (auto-bundles imports)
  apis: :browser,              # :browser | :node | [:browser, :node] | false
  handlers: %{},               # Elixir functions callable from JS
  define: %{},                 # compile-time globals (JSON-encoded)
  memory_limit: 256_000_000,   # 256MB default
  max_stack_size: 8_000_000,   # 8MB default — ~55 recursive frames
  max_convert_depth: 32,       # nested structure depth limit
  max_convert_nodes: 10_000    # total nodes in conversion
)

# Stop and free resources
QuickBEAM.stop(rt)

# Reset to fresh context (clears all state)
QuickBEAM.reset(rt)

# Diagnostics
QuickBEAM.info(rt)
QuickBEAM.memory_usage(rt)     # => %{malloc_size: ..., memory_used_size: ..., obj_count: ..., ...}
QuickBEAM.globals(rt)          # list all global names
QuickBEAM.globals(rt, user_only: true)  # only user-defined globals
```

**API surfaces:**

| `:apis` | Provides | Does NOT provide |
|---|---|---|
| `:browser` (default) | `fetch`, `document`, `crypto`, `WebSocket`, `URL`, `TextEncoder` | `self`, `window`, `process` |
| `:node` | `process`, `path`, `fs`, `os` | `fetch`, `document` |
| `[:browser, :node]` | Both | — |
| `false` | Bare QuickJS | Everything above |

`:browser` does NOT define `self`/`window` — see "npm Browser Bundles" for the correct stub pattern.

### Code Execution

```elixir
# Evaluate JS — supports top-level await
{:ok, 42} = QuickBEAM.eval(rt, "40 + 2")
{:ok, 42} = QuickBEAM.eval(rt, "await Promise.resolve(42)")

# With timeout (runtime remains usable after timeout)
{:error, %QuickBEAM.JSError{}} = QuickBEAM.eval(rt, "while(true){}", timeout: 1000)

# With vars — injected as globals, auto-cleaned up after execution (even on error)
{:ok, "QUICKBEAM"} = QuickBEAM.eval(rt, "name.toUpperCase()", vars: %{"name" => "quickbeam"})
{:ok, 40} = QuickBEAM.eval(rt, "items.map(i => i.price * i.qty).reduce((a, b) => a + b, 0)",
  vars: %{"items" => [%{"price" => 10, "qty" => 3}, %{"price" => 5, "qty" => 2}]})

# Evaluate TypeScript (transforms via OXC, then evaluates)
{:ok, 42} = QuickBEAM.eval_ts(rt, "const x: number = 42; x")

# Call a global JS function — auto-awaits promises
{:ok, 5} = QuickBEAM.call(rt, "add", [2, 3])
{:ok, result} = QuickBEAM.call(rt, "fetchData", [url], timeout: 10_000)
```

**`call` vs `eval`:** prefer `call` for invoking functions — native arg passing (no string interpolation), auto-awaits Promises. Use `eval` for defining functions, running scripts, or `:vars`.

### Globals

```elixir
# Set a JS global from Elixir (native BEAM->JS conversion, not JSON)
QuickBEAM.set_global(rt, "config", %{"key" => "value"})
QuickBEAM.set_global(rt, "items", [1, 2, 3])

# Get a JS global back to Elixir — returns STRING-keyed maps (not atom-keyed)
{:ok, %{"key" => "value"}} = QuickBEAM.get_global(rt, "config")

# Inline objects from eval/call are also string-keyed
{:ok, %{"x" => 1, "y" => 2}} = QuickBEAM.eval(rt, "({x: 1, y: 2})")
```

**Key type difference:** OXC AST uses atom keys; QuickBEAM returns string keys. Matters for pattern matching.

### Module Loading

```elixir
# Load ES module — top-level evaluation errors propagate as {:error, %JSError{}}
QuickBEAM.load_module(rt, "utils", "export function add(a, b) { return a + b; }")

# Compile to bytecode (for reuse across runtimes)
{:ok, bytecode} = QuickBEAM.compile(rt, code)
QuickBEAM.load_bytecode(rt, bytecode)

# Disassemble bytecode for inspection
{:ok, bc} = QuickBEAM.disasm(bytecode)
# => %QuickBEAM.Bytecode{opcodes: [{0, :push_i32, 40}, ...], ...}
```

### Handlers: JS Calling Elixir

Define Elixir functions that JavaScript can invoke:

```elixir
{:ok, rt} = QuickBEAM.start(handlers: %{
  "fetchData" => fn [url] ->
    case Req.get(url) do
      {:ok, %{body: body}} -> body
      {:error, _} -> nil
    end
  end,
  "log" => fn [message] ->
    Logger.info("JS: #{message}")
    :ok
  end
})
```

JS invokes handlers two ways:
```javascript
const data = Beam.callSync("fetchData", "https://api.example.com");    // blocks
const data = await Beam.call("fetchData", "https://api.example.com");  // Promise
```

Arguments arrive as a flat list: `Beam.callSync("fn", "a", "b")` → handler receives `["a", "b"]`.

### Loading npm Browser Bundles

```elixir
{:ok, rt} = QuickBEAM.start()

# Stub browser globals. self/window must BE globalThis, not just defined.
# set_global with an atom converts to STRING — won't work here.
QuickBEAM.eval(rt, "globalThis.self = globalThis; globalThis.window = globalThis")
QuickBEAM.set_global(rt, "navigator", %{"userAgent" => "QuickBEAM"})
QuickBEAM.set_global(rt, "location", %{"protocol" => "https:"})

bundle = File.read!("node_modules/library/dist/library.browser.min.js")
{:ok, _} = QuickBEAM.call(rt, "eval", [bundle])
{:ok, result} = QuickBEAM.eval(rt, "libraryName.doThing('input')")
```

### Returning Complex Data

Simple values and nested objects convert natively up to `max_convert_depth` (32). Beyond that, leaves become `nil` silently — return `JSON.stringify(result)` from JS and decode with Jason.

### Pools

**Pool** (full runtimes, ~2MB each — use when each needs heavy init like large bundles):
```elixir
{:ok, pool} = QuickBEAM.Pool.start_link(
  name: MyApp.JSPool, size: 10,
  init: fn rt -> QuickBEAM.eval(rt, File.read!("priv/js/app.js")) end,   # runs after creation AND reset
  lazy: false
)

result = QuickBEAM.Pool.run(pool, fn rt ->
  {:ok, val} = QuickBEAM.call(rt, "process", [data]); val
end)   # default 5000ms timeout
```

**ContextPool** (lightweight, ~58-429KB — many cheap isolated environments, per-connection/request):
```elixir
{:ok, pool} = QuickBEAM.ContextPool.start_link(name: MyApp.CtxPool, size: System.schedulers_online())
{:ok, ctx} = QuickBEAM.Context.start_link(pool: MyApp.CtxPool)
{:ok, 42} = QuickBEAM.Context.eval(ctx, "40 + 2")
QuickBEAM.Context.set_global(ctx, "x", 42)
QuickBEAM.Context.stop(ctx)
```

### DOM Access

With `:browser` APIs, native DOM is included:

```elixir
{:ok, el}   = QuickBEAM.dom_find(rt, "div.container")
{:ok, els}  = QuickBEAM.dom_find_all(rt, "li.item")
{:ok, text} = QuickBEAM.dom_text(rt, "h1")
{:ok, href} = QuickBEAM.dom_attr(rt, "a.link", "href")
```

### QuickBEAM.JS — TypeScript Toolchain

Mirrors OXC's API but runs inside a runtime. Same atom-keyed AST contract as OXC.

```elixir
{:ok, ast} = QuickBEAM.JS.parse(source, "file.ts")
{:ok, js}  = QuickBEAM.JS.transform(source, "file.ts")
{:ok, min} = QuickBEAM.JS.minify(source, "file.js")
{:ok, js}  = QuickBEAM.JS.bundle(files, entry: "main.ts")
{:ok, js}  = QuickBEAM.JS.bundle_file("entry.ts")       # resolves from disk
```

Prefer OXC (Rust NIF) for performance. Use `QuickBEAM.JS` when you need `bundle_file` (disk resolution) or are already in a runtime.

### QuickBEAM.Cover — JS Line Coverage

Integrates with `mix test --cover`:

```elixir
# mix.exs
def project, do: [..., test_coverage: [tool: QuickBEAM.Cover]]
```

**Sidecar with excoveralls:**
```elixir
# test/test_helper.exs
QuickBEAM.Cover.start()
ExUnit.after_suite(fn _ -> QuickBEAM.Cover.stop() end)
```

Writes to `cover/js_lcov.info`.

| Function | Signature | Purpose |
|---|---|---|
| `start/0`, `start/2` | `start()` / Mix callback | Begin recording |
| `stop/1`, `results/1` | `(opts \\ [])` — **not** runtime | Stop / snapshot |
| `record/1` | `(coverage_map)` — **not** runtime | Merge a runtime snapshot into global |
| `export_lcov/2`, `export_istanbul/2` | `(path, data)` — data from `results/1`/`stop/1` | Export |
| `enabled?/0` | — | Is recording active? |

Cover is centered on a `coverage_map`, not runtimes — `record`/`export` take that map, not an `rt`.

### Recipes

**Define-then-Call (standard pattern):**
```elixir
{:ok, rt} = QuickBEAM.start()
QuickBEAM.eval(rt, "globalThis.self = globalThis; globalThis.window = globalThis")
QuickBEAM.call(rt, "eval", [File.read!("node_modules/lib/dist/lib.browser.min.js")])
QuickBEAM.eval(rt, """
  globalThis.doWork = async (input) => JSON.stringify(await lib.process(input));
""")
{:ok, json} = QuickBEAM.call(rt, "doWork", [input])
result = Jason.decode!(json)
```

**Long-lived runtime in supervision tree:** wrap `QuickBEAM.start/1` in a GenServer; call `QuickBEAM.stop/1` in `terminate/2`.

**Handler bridge:**
```elixir
{:ok, rt} = QuickBEAM.start(handlers: %{
  "httpGet" => fn [url] -> Req.get!(url).body end,
  "readFile" => fn [path] -> File.read!(path) end
})
QuickBEAM.eval(rt, """
  const html = Beam.callSync("httpGet", "https://example.com");
  const config = JSON.parse(Beam.callSync("readFile", "config.json"));
""")
```

### WebSocket

Mint-backed, full JS `WebSocket` API — `onopen`, `onmessage`, `onclose`, `onerror`, `send()`, `close()`, subprotocol negotiation:

```elixir
{:ok, rt} = QuickBEAM.start(apis: :browser)

{:ok, log} = QuickBEAM.eval(rt, """
  new Promise((resolve, reject) => {
    const ws = new WebSocket("wss://stream.binance.com:9443/ws/btcusdt@trade");
    const log = [];
    ws.onopen    = () => log.push("open");
    ws.onmessage = (e) => { log.push("msg"); ws.close(); };
    ws.onclose   = (e) => { log.push("close:" + e.code); resolve(log.join(" | ")); };
    ws.onerror   = () => reject(new Error("WS error"));
  });
""", timeout: 15_000)
```

### WebAssembly

WAMR-backed, standard JS `WebAssembly` API — `Module`, `Instance`, `Memory`, `Table`, `Global`, `compile`, `instantiate`, `validate`, `CompileError`, `LinkError`, `RuntimeError`.

```elixir
{:ok, 42} = QuickBEAM.eval(rt, """
  (async () => {
    const bytes = new Uint8Array([/* add(a,b)→i32 */]);
    const inst = new WebAssembly.Instance(new WebAssembly.Module(bytes));
    return inst.exports.add(40, 2);
  })()
""", timeout: 10_000)
```

### Common Pitfalls

| Problem | Cause | Fix |
|---|---|---|
| Globals missing after bundle load | `self`/`window` set as strings | `QuickBEAM.eval(rt, "globalThis.self = globalThis")` — never `set_global` with atoms |
| `ReferenceError: self is not defined` | Library expects browser globals | Stub `self`, `window`, `navigator`, `location` before loading |
| Deep nested `nil` leaves | Exceeds `max_convert_depth` (32) | Return `JSON.stringify(result)`, decode with Jason |
| Memory grows unbounded | Runtime accumulates state | `QuickBEAM.reset/1` or stop/restart |
| Timeout on large bundle load | No default timeout | Pass `timeout: 30_000` |
| String keys unexpected | JS objects always string-keyed | Unlike OXC (atom keys) |

### DO NOT

1. Don't interpolate Elixir values into JS strings — use `call/3` with args or `:vars`.
2. Don't forget to stop runtimes — each holds native memory.
3. Don't use QuickBEAM for static JS/TS analysis — OXC is orders of magnitude faster.

### Performance

| Operation | ~Time | Notes |
|---|---|---|
| Start runtime | 5ms | GenServer + QuickJS init |
| Load 5MB bundle | 2s | One-time per runtime |
| Function call overhead | 1ms | NIF, no IPC |
| HTTP via fetch | 140ms | Network-bound (~84ms native Elixir) |
| Context creation | 1ms | Shares runtime thread |
| Runtime memory | ~2MB | With JS heap |
| Context memory | ~58-429KB | Depends on API surface |
