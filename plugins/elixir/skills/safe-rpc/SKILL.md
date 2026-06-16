---
name: safe-rpc
description: safe_rpc — capability-scoped RPC over safe ETF for Elixir. Use when building authenticated RPC between BEAM nodes with per-capability grants, an Authorizer behaviour, sharded client pools, or async/await calls over a Unix socket transport. Early prototype. Covers Server/Client, Capability grants, ClientPool, and Adapter.Service/Dispatcher.
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/safe-rpc.md — do not edit manually -->

## SafeRPC — Capability-Scoped RPC over Safe ETF

GenServer-like RPC over Erlang external term format for BEAM-native control-plane channels that need narrow, auditable authority — not the broad trust of Erlang distribution.

**Min version: `{:safe_rpc, "~> 0.1"}`.** Current release is v0.1.3, self-described as "early prototype."

**Unix socket-first.** The only shipped transport is `SafeRPC.Transport.Unix` (`:gen_tcp` over `{:local, path}`). TCP/TLS/stdio are defined in the transport behaviour but not yet implemented.

**Wire format is safe ETF.** Framing: `:gen_tcp` packet-4 (4-byte length prefix). All decoding uses `:erlang.binary_to_term(binary, [:safe])` — no code loading from the wire.

**Two authorization layers stack independently:** `SafeRPC.Capability` (token + op allowlist, constant-time compare) and `SafeRPC.Authorizer` behaviour (custom policy). Both optional. Neither defines users, tenants, roles, or resources — those belong in your authorizer.

**Caveat:** Early prototype. API surface is small and may change before a stable release. No TCP/TLS transport yet — both ends must share a filesystem path for the Unix socket.

**Does NOT cover:** Erlang distribution, cross-node fanout/multicall (planned but unimplemented), TCP/TLS transports, streaming responses, schema validation.

**Portfolio fit:** Replaces the HTTP/Finch-over-WireGuard agent↔backend control channel in servernodes with structured ETF calls; the capability grant model maps directly onto delegatr's scoped-agent-credential thesis — each credential token becomes a `SafeRPC.Capability` with an explicit ops allowlist.

---

### Module Map

| Module | Role |
|---|---|
| `SafeRPC` | Top-level API: `call`, `cast`, `async`, `await`, `yield`, `cancel`, `shutdown` |
| `SafeRPC.Client` | GenServer holding a persistent Unix socket connection; also one-shot helpers |
| `SafeRPC.ClientPool` | Sharded pool of `Client` processes, keyed by `:erlang.phash2/2` |
| `SafeRPC.Server` | `use` macro + acceptor loop; spawns `Server.Connection` per accepted client |
| `SafeRPC.Capability` | Token/op allowlist struct; constant-time token comparison via `:crypto.hash_equals/2` |
| `SafeRPC.Authorizer` | Behaviour for application-specific authorization (`authorize/2`) |
| `SafeRPC.Protocol` | ETF encode/decode for requests, replies, and cancel frames |
| `SafeRPC.Transport` | Behaviour — `connect/1`, `listen/1`, `accept/2`, `send/3`, `recv/2`, `close/1` |
| `SafeRPC.Transport.Unix` | Sole shipped transport; `:gen_tcp` over Unix domain socket |
| `SafeRPC.Adapter.Service` | Behaviour for framework-agnostic services (`init/1`, `call/4` with meta) |
| `SafeRPC.Adapter.Server` | `use` macro wrapping a `Service` module into a full server |
| `SafeRPC.Adapter.Dispatcher` | Op-to-MFA routing table — keeps MFA off the wire |
| `SafeRPC.Adapter.Plug` | Bridges Phoenix/Plug endpoints to adapter HTTP envelopes |
| `SafeRPC.Task` | Struct for in-flight async requests: `%{client, id, op}` |

---

### Server (define operations)

```elixir
defmodule MyBackend do
  use SafeRPC.Server

  # Required: initialize server state
  def init(opts), do: {:ok, %{count: Keyword.get(opts, :count, 0)}}

  # handle_call/3 — synchronous; must return {:reply, result, state}
  def handle_call(:status, _payload, state),
    do: {:reply, {:ok, %{count: state.count}}, state}

  # handle_cast/3 — fire-and-forget; must return {:noreply, state}
  # default no-op is injected by `use SafeRPC.Server` — override to handle
  def handle_cast(:inc, amount, state),
    do: {:noreply, %{state | count: state.count + amount}}
end

# Start under a supervisor or directly:
{:ok, _} = MyBackend.start_link(
  socket: "/tmp/mybackend.sock",  # required — Unix socket path
  capability: cap,                 # optional SafeRPC.Capability
  authorizer: MyAuthz,             # optional module implementing SafeRPC.Authorizer
  auth_context: %{env: :prod},    # passed as second arg to authorizer.authorize/2
  recv_timeout: 10_000            # ms, default 5_000
)
```

**Server lifecycle:** on terminate, the loop closes the listen socket and removes the socket file via `File.rm/1`.

---

### Client — Persistent Connection

```elixir
{:ok, client} = SafeRPC.Client.start_link(
  socket: "/tmp/mybackend.sock",  # required
  cap: "my-secret-token",         # sent with every request; matched by Capability
  connect_timeout: 5_000,         # default 5_000 ms
  timeout: 5_000                  # per-request default; overridable per call
)

# Synchronous call
{:ok, result}        = SafeRPC.call(client, :status, %{})
{:ok, :noreply}      = SafeRPC.cast(client, :inc, 5)
{:error, :timeout}   = SafeRPC.call(client, :slow_op, %{}, timeout: 500)
```

**One-shot (no persistent client process):** pass the socket path as a binary. Opens a connection, sends, reads reply, closes — suitable for infrequent control-plane pings:

```elixir
{:ok, result} = SafeRPC.call("/tmp/mybackend.sock", :status, %{}, cap: "my-secret-token")
```

---

### Async / Await (Task-Like)

Mirrors `Task.async/await` semantics. `async/3` sends the request and returns a `%SafeRPC.Task{}` immediately; the reply arrives as a message `{SafeRPC.Task, id, result}`.

```elixir
# Fire and wait
task = SafeRPC.async(client, :status, %{})
{:ok, result} = SafeRPC.await(task, 5_000)   # exits with {:timeout, ...} on timeout

# Non-blocking poll — returns nil if no reply yet
case SafeRPC.yield(task, 0) do
  {:ok, result} -> handle(result)
  nil           -> :still_pending
end

# Cancel an in-flight request (sends cancel frame to server)
:ok = SafeRPC.cancel(task)

# shutdown/2 is an alias for cancel/1; timeout arg accepted but unused (planned)
:ok = SafeRPC.shutdown(task, 5_000)
```

Multiple in-flight `async` calls on the same `client` PID are safe — each gets a unique `make_ref()` request ID and its own reply mailbox message.

---

### Sharded Client Pool

Shard count defaults to `System.schedulers_online()`. Key is hashed via `:erlang.phash2/2` to pick the shard — use a stable key (tenant ID, connection ID) for affinity.

```elixir
{:ok, pool} = SafeRPC.ClientPool.start_link(
  socket: "/tmp/mybackend.sock",
  shards: 4,                       # optional; default = schedulers_online()
  cap: "my-secret-token"
)

# All Client functions available; key routes to a shard
{:ok, result}  = SafeRPC.ClientPool.call(pool, {:tenant, :alice}, :status, %{})
{:ok, :noreply} = SafeRPC.ClientPool.cast(pool, "conn-id-123", :inc, 1)
task            = SafeRPC.ClientPool.async(pool, {:tenant, :bob}, :status, %{})
{:ok, result}  = SafeRPC.await(task)

# Fetch the shard PID for direct Client calls
client_pid = SafeRPC.ClientPool.client(pool, some_key)
```

---

### Capability Grants (Per-Op Token)

`SafeRPC.Capability` restricts which operations a token may call. Token comparison is constant-time (`:crypto.hash_equals/2`) — safe for shared secrets.

```elixir
# Restrict a token to specific ops
cap = SafeRPC.Capability.new(token: "agent-secret", ops: [:status, :metrics])

# Allow all ops for a token (ops: :all is the default)
admin_cap = SafeRPC.Capability.new(token: "admin-secret")

# Start server with capability enforcement
{:ok, _} = MyBackend.start_link(socket: "/tmp/mybackend.sock", capability: cap)

# Client must pass matching token
{:ok, _}             = SafeRPC.call(client, :status, %{}, cap: "agent-secret")
{:error, :unauthorized} = SafeRPC.call(client, :drop_table, %{}, cap: "agent-secret")
```

If `capability:` is not set on the server, all requests are allowed through to the authorizer (or directly to handler if no authorizer either).

---

### Custom Authorizer (Application Policy)

```elixir
defmodule MyAuthz do
  @behaviour SafeRPC.Authorizer

  # context is the auth_context: value passed to start_link
  def authorize(%{op: :status}, _ctx), do: :ok
  def authorize(%{op: :metrics, meta: %{role: :admin}}, _ctx), do: :ok
  def authorize(_request, _ctx), do: {:error, :forbidden}
end

{:ok, _} = MyBackend.start_link(
  socket: "/tmp/mybackend.sock",
  authorizer: MyAuthz,
  auth_context: %{env: :prod}
)
```

Request map passed to `authorize/2`: `%{id: ref, cap: token_string, kind: :call | :cast, op: atom, payload: term, meta: map}`.

Authorization runs: Capability check → Authorizer → handler. Either can short-circuit with `{:error, reason}`.

---

### Adapter Layer (Service + Dispatcher)

Use `SafeRPC.Adapter.Service` when you want to separate the operation implementation from the transport:

```elixir
defmodule AgentService do
  @behaviour SafeRPC.Adapter.Service

  def init(_opts), do: {:ok, %{}}

  # call/4: op, payload, meta (from request), state
  def call(:status, _payload, meta, state) do
    {:ok, %{status: :ok, trace: meta[:trace_id]}}
  end

  def call(_op, _payload, _meta, _state), do: {:error, :unknown_op}
end

defmodule AgentServer do
  use SafeRPC.Adapter.Server, service: AgentService
end

{:ok, _} = AgentServer.start_link(socket: "/tmp/agent.sock")

# Callers can pass meta through the request
{:ok, result} = SafeRPC.call(client, :status, %{}, meta: %{trace_id: "abc-123"})
```

For op-to-MFA dispatch tables:

```elixir
routes = %{
  status:     {MyAPI, :status, 3},     # arity 3: op, payload, meta
  user_by_id: {MyAPI, :user_by_id, 3}
}

# Call from inside a handle_call/request implementation:
SafeRPC.Adapter.Dispatcher.call(routes, :status, payload, meta, state)
```

---

### Wire Protocol

```
Request:  {:safe_rpc,        1, id, cap, :call | :cast, op, payload, meta}
Reply:    {:safe_rpc_reply,  1, id, result}
Cancel:   {:safe_rpc_cancel, 1, id}
```

All terms encoded via `:erlang.term_to_binary/1`; decoded via `:erlang.binary_to_term(binary, [:safe])`. The `:safe` flag blocks atoms-from-binary and function references — terms with new atoms or funs will raise `ArgumentError`, caught and returned as `{:error, {:invalid_term, error}}`.

Protocol version is hard-coded to `1`; mismatched version produces `{:error, {:invalid_request, term}}`.

---

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| `{:error, :enoent}` on connect | Socket file doesn't exist | Server not started or wrong path |
| `{:error, :econnrefused}` | Server stopped but socket file lingered | Server manages cleanup on terminate; check if it crashed |
| `{:error, :unauthorized}` | Token missing, wrong token, or op not in `ops` list | Pass `cap:` in call opts; check `Capability.new` ops list |
| `{:error, {:invalid_term, _}}` | Binary contains atoms not yet in atom table or funs | Sender is not using `:safe`-compatible encoding — audit sender side |
| `exit {:timeout, ...}` from `await` | Reply didn't arrive in timeout window | Raise timeout in `await/2`, or use `yield/2` to avoid exit |
| Pool shard imbalance | Low-cardinality key space with few shards | Use a higher-cardinality key or increase `shards:` |
| Socket file not cleaned up on crash | Server process exited abnormally (skipped `terminate`) | Wrap in a supervisor with restart strategy; server removes file on normal terminate |

---

### DO NOT

1. Pass `ops: :all` in a `Capability` given to untrusted clients — enumerate the exact op set.
2. Use raw `:erlang.binary_to_term/1` anywhere in the call path — always pass `[:safe]`.
3. Expose MFA on the wire (that is `:rpc`/`gen_rpc` territory); keep op dispatch internal.
4. Share the Unix socket path across security boundaries without a capability token — the path itself is not a secret.
5. Call `SafeRPC.async/3` on a one-shot socket path string (binary); `async` requires a persistent client PID.
6. Assume `shutdown/2` waits for the handler to finish — current impl is an alias for `cancel/1` (cancel frame, no drain).
7. Use this as a cross-language transport — ETF is BEAM-native; payloads are opaque bytes on any other runtime.

---

### Testing Notes

Both ends can run in the same test process. Use a temp path from `System.tmp_dir!/0`:

```elixir
setup do
  path = Path.join(System.tmp_dir!(), "test-#{:rand.uniform(1_000_000)}.sock")
  {:ok, server} = MyBackend.start_link(socket: path, count: 0)
  {:ok, client} = SafeRPC.Client.start_link(socket: path)
  on_exit(fn -> File.rm(path) end)
  %{client: client, server: server}
end

test "increments count", %{client: client} do
  assert {:ok, :noreply} = SafeRPC.cast(client, :inc, 3)
  assert {:ok, %{count: 3}} = SafeRPC.call(client, :status)
end
```

No sandbox or async isolation issues — each test gets its own socket path.

---

### Dependencies

```elixir
# mix.exs — safe_rpc only requires plug at runtime
{:safe_rpc, "~> 0.1"}
# Requires Elixir ~> 1.20
# Transitive runtime dep: {:plug, "~> 1.18"} (for SafeRPC.Adapter.Plug)
```

No Hex-published third-party deps beyond Plug. No NIF, no native extension. The `:crypto` application must be started (it is by default in OTP 24+).
