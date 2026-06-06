---
name: zen-websocket
description: ZenWebsocket library for Elixir WebSocket connections. Use when implementing WebSocket clients, handling reconnection logic, or integrating with trading APIs (Deribit, Binance). Covers the 5 core functions (connect, send_message, subscribe, get_state, close), message handling, heartbeats, and platform-specific patterns.
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion
---

<!-- Auto-synced from ~/.claude/includes/zen-websocket.md — do not edit manually -->

## ZenWebsocket Patterns

Gun-backed WebSocket client for financial APIs. 5 core functions, auto-reconnection, real-world tested.

### 5 Essential Functions

```elixir
{:ok, client} = ZenWebsocket.Client.connect("wss://api.example.com/ws")
:ok = ZenWebsocket.Client.send_message(client, Jason.encode!(%{method: "ping"}))
:ok = ZenWebsocket.Client.subscribe(client, ["channel.name"])           # JSON-RPC convenience
state = ZenWebsocket.Client.get_state(client)                           # :connected | :connecting | :disconnected
:ok = ZenWebsocket.Client.close(client)
```

### Connection Patterns

```elixir
# Dev — messages arrive at calling process as {:websocket_message, data}
{:ok, client} = ZenWebsocket.Client.connect(url)

# Prod — dynamic supervision
children = [ZenWebsocket.ClientSupervisor]
{:ok, client} = ZenWebsocket.ClientSupervisor.start_client(url, opts)

# Prod — fixed connection
children = [
  {ZenWebsocket.Client, [
    url: "wss://api.example.com/ws", id: :main_ws,
    heartbeat_config: %{type: :ping, interval: 30_000}
  ]}
]
```

### Three-Layer Architecture (ccxt_client pattern)

| Layer | Module | State | Use When |
|---|---|---|---|
| 1. Pure helpers | `MyApp.WS.Helpers` | None | URL resolution, config, message formatting |
| 2. Stateless client | Thin wrapper | None | One-off connections, simple subscribe/receive |
| 3. Stateful adapter | GenServer | Reconnection, auth, subs | Production with auth state machine |

Layer 3 optional. ccxt_client's adapter manages connection lifecycle, auth state machine (`:unauthenticated` → `:authenticating` → `:authenticated` → `:expired`), subscription restoration, exponential backoff. Layer 2 suffices for most cases.

### Configuration Options

```elixir
opts = [
  timeout: 5000,              # Connection timeout (ms)
  headers: [],                # Custom HTTP headers (redacted in inspect output)
  retry_count: 3,             # Max reconnection attempts (resets to 0 on successful reconnect)
  retry_delay: 1000,          # Initial backoff delay (exponential)
  max_backoff: 30_000,        # Max delay between retries
  reconnect_on_error: true,   # Auto-reconnect on recoverable errors
  restore_subscriptions: true, # Re-subscribe after reconnect
  request_timeout: 30_000,    # JSON-RPC correlation timeout
  handler: &MyApp.on_ws/1,    # Optional custom handler — see Message Handling
  on_connect: fn pid -> :ok end,    # Optional supervised-connect lifecycle hook
  on_disconnect: fn pid -> :ok end, # Optional terminate lifecycle hook
  heartbeat_config: %{
    type: :ping,              # :ping | :deribit | :custom
    interval: 30_000          # Heartbeat interval (ms)
  }
]
```

### Heartbeat Types

| Type | Behavior | Use For |
|------|----------|---------|
| `:ping` | Standard WebSocket ping/pong frames | Most exchanges |
| `:deribit` | Auto-responds to `test_request`, sends `public/test` | Deribit |
| `:custom` | Sends user-defined message at interval | Exchanges with custom ping format |

```elixir
# Custom heartbeat for exchanges that expect JSON ping
heartbeat_config: %{
  type: :custom,
  interval: 30_000,
  message: Jason.encode!(%{op: "ping"})
}
```

### Message Handling

Messages forward to the process that called `connect/2`. **JSON text frames arrive pre-decoded as maps (v0.4.0+)** — don't call `Jason.decode/1` on them.

```elixir
# JSON-RPC success / error / notification — pattern-match the decoded map
def handle_info({:websocket_message, %{"result" => r, "id" => id}}, state), do: ...
def handle_info({:websocket_message, %{"error" => err, "id" => id}}, state), do: ...
def handle_info({:websocket_message, %{"method" => m, "params" => p}}, state), do: ...
def handle_info({:websocket_message, %{} = decoded}, state), do: ...

# Non-JSON text + binary frames share the same tag
def handle_info({:websocket_message, data}, state) when is_binary(data), do: ...

# Orphan JSON-RPC reply (no pending caller matched id) — v0.4.1+
def handle_info({:websocket_unmatched_response, response}, state), do: ...

# Fatal frame-decode error — Client stops after delivering
def handle_info({:websocket_protocol_error, reason}, state), do: ...
```

Those four are the complete emitted set. Ping/pong/close control frames never reach the consumer.

**Custom handler** (`handler: fun` to `connect/2`) — distinguish text/binary, or avoid the `:websocket_` prefix:

```elixir
handler = fn
  {:message, %{} = json} -> MyApp.route(json)
  {:message, text} when is_binary(text) -> ...
  {:binary, bin} -> ...
  {:unmatched_response, response} -> ...
  {:protocol_error, reason} -> ...
end

{:ok, client} = ZenWebsocket.Client.connect(url, handler: handler)
```

### JSON-RPC Support

```elixir
# Build and send JSON-RPC request (auto-generates unique ID)
{:ok, request} = ZenWebsocket.JsonRpc.build_request("public/subscribe", %{channels: channels})

# When the message has an "id" field, send_message/2 blocks and returns the correlated response
case ZenWebsocket.Client.send_message(client, Jason.encode!(request)) do
  {:ok, response} -> ...
  {:error, :duplicate_request_id} -> ...  # another caller is already waiting on this id (v0.4.1+)
  {:error, :disconnected} -> ...          # Gun socket went away while waiting (v0.4.1+)
  {:error, reason} -> ...
end
# Messages without an "id" return plain :ok
```

### Error Categories

| Category | Errors | Action |
|----------|--------|--------|
| **Recoverable** | `:timeout`, `:econnrefused`, `:nxdomain`, `:ehostunreach`, `:gun_down`, `:gun_error`, `:tls_alert` | Auto-reconnect with backoff |
| **Fatal** | `:invalid_frame`, `:frame_too_large`, `:bad_frame`, `:unauthorized`, `:invalid_credentials`, `:token_expired` | Stop connection, notify caller |

### Reconnection Behavior

When a recoverable error occurs:
1. Current connection cleaned up
2. Backoff calculated: `retry_delay * 2^attempt` (capped at `max_backoff`)
3. Reconnection attempted after backoff
4. If `restore_subscriptions: true`, previous subscriptions re-sent
5. After `retry_count` failures, connection stops permanently

### Rate Limiting

Token bucket backed by named ETS. Config is a **map**. Two things before `init/2`:

1. **Caller owns the refill timer** — `init/2` sends `{:refill, name}` to the calling process; that process must call `RateLimiter.refill(name)` or tokens never replenish.
2. **Tables aren't auto-cleaned** — call `shutdown/1` when done.

```elixir
alias ZenWebsocket.RateLimiter

config = %{
  tokens: 100,                             # initial + max
  refill_rate: 100,
  refill_interval: 1000,                   # ms
  request_cost: &RateLimiter.simple_cost/1
  # max_queue_size: 100                    # optional, default 100
}
{:ok, :my_conn} = RateLimiter.init(:my_conn, config)

def handle_info({:refill, name}, state) do
  RateLimiter.refill(name)
  {:noreply, state}
end

case RateLimiter.consume(:my_conn, msg) do
  :ok -> ZenWebsocket.Client.send_message(client, msg)
  {:error, :rate_limited} -> :queued                     # auto-retried on refill
  {:error, :queue_full}   -> drop_or_backpressure(msg)
end

{:ok, %{tokens: _, queue_size: _, pressure_level: _, suggested_delay_ms: _}} =
  RateLimiter.status(:my_conn)
:ok = RateLimiter.shutdown(:my_conn)
```

**Cost functions** (or supply your own `(request -> pos_integer())`):

| Function | Model | For |
|---|---|---|
| `simple_cost/1`   | Fixed 1 per request | Coinbase, most |
| `deribit_cost/1`  | Credits per JSON-RPC method | Deribit |
| `binance_cost/1`  | Weight per JSON-RPC method | Binance |

### Common Issues

| Problem | Cause | Fix |
|---------|-------|-----|
| Connection keeps timing out | Network/firewall, wrong URL | Increase `timeout: 10_000`, verify `wss://` vs `ws://` |
| Messages not received | Wrong process | Messages go to the process that called `connect/2` — verify with `get_state/1`, or pass a `:handler` function |
| `FunctionClauseError` on handler | Calling `Jason.decode/1` on `{:websocket_message, _}` payload | Since v0.4.0, JSON text frames are delivered pre-decoded — pattern-match on the map directly |
| Reconnection not working | Fatal error category | Fatal errors stop permanently — check if error is recoverable |
| Subscriptions lost after reconnect | `restore_subscriptions` disabled | Set `restore_subscriptions: true` (default) |
| `{:error, :duplicate_request_id}` | Two callers used the same JSON-RPC id concurrently | Let `JsonRpc.build_request/2` generate ids; don't reuse integers |
| Callers hang on disconnect | (pre-v0.4.1) pending requests not drained | Upgrade to v0.4.1+ — pending callers now get `{:error, :disconnected}` immediately |

### DO NOT

1. Don't create wrapper modules — use the 5 functions directly.
2. Don't mock WebSocket behavior — test against real endpoints or `ZenWebsocket.Testing`.
3. Don't `Jason.decode/1` on `{:websocket_message, _}` — already decoded (v0.4.0+).
4. Don't add custom reconnection — use built-in retry; `Client.reconnect/1` preserves config (v0.4.1+).
5. Don't skip heartbeats in production.

### Platform-Specific: Deribit

```elixir
{:ok, client} = ZenWebsocket.Client.connect("wss://test.deribit.com/ws/api/v2", [
  heartbeat_config: %{type: :deribit, interval: 30_000}
])
# Auto-responds to test_request heartbeats
# Sends JSON-RPC public/test as heartbeat

# Subscribe to channels
ZenWebsocket.Client.subscribe(client, ["book.BTC-PERPETUAL.raw", "trades.BTC-PERPETUAL.raw"])

# Authentication (manual JSON-RPC)
auth = %{"jsonrpc" => "2.0", "id" => :erlang.unique_integer([:positive]),
  "method" => "public/auth",
  "params" => %{"grant_type" => "client_credentials",
    "client_id" => client_id, "client_secret" => client_secret}}
:ok = ZenWebsocket.Client.send_message(client, Jason.encode!(auth))
```

### Testing

```elixir
# Integration — real endpoints
@tag :integration
test "real WebSocket" do
  {:ok, client} = ZenWebsocket.Client.connect("wss://test.deribit.com/ws/api/v2")
  assert ZenWebsocket.Client.get_state(client) == :connected
  ZenWebsocket.Client.close(client)
end

# Controlled — use ZenWebsocket.Testing (not MockWebSockServer directly)
alias ZenWebsocket.{Client, Testing}

setup do
  {:ok, server} = Testing.start_mock_server()
  on_exit(fn -> Testing.stop_server(server) end)
  {:ok, server: server}
end

test "handles server message", %{server: server} do
  {:ok, client} = Client.connect(server.url)
  Testing.inject_message(server, ~s({"type": "pong"}))
  assert_receive {:websocket_message, %{"type" => "pong"}}, 1000
  Testing.simulate_disconnect(server, :going_away)
  Client.close(client)
end

# Assert client sent an expected frame (string, regex, map, or fn matcher)
Testing.assert_message_sent(server, %{"method" => "public/subscribe"}, 1000)
```

### Monitoring

```elixir
Client.get_heartbeat_health(client)  # %{active:, failure_count:, last_heartbeat_at:}
Client.get_latency_stats(client)     # %{p50:, p99:, last:, count:}  — nil before first sample
Client.get_state_metrics(client)     # %{connection_state:, pending_requests_size:, subscriptions_size:, state_memory:, ...}
```

### Telemetry

Events grouped under `:connection`, `:heartbeat`, `:rate_limiter`, `:request_correlator`, `:subscription_manager`, `:pool`. Full reference in `docs/guides/performance_tuning.md` + `USAGE_RULES.md`.

```elixir
:telemetry.attach("ws-upgrade", [:zen_websocket, :connection, :upgrade],
  fn _event, %{connect_time_ms: ms}, metadata, _ ->
    Logger.info("Connected in #{ms}ms to #{metadata[:url]}")
  end, nil)
```

### Runtime Discovery (Descripex)

```elixir
ZenWebsocket.describe()                        # library overview
ZenWebsocket.describe(:client)                 # Client functions
ZenWebsocket.describe(:client, :send_message)  # full contract
```

### Performance

- Connect: < 100ms typical · Message latency: < 1ms processing · Memory: ~50KB/connection
- Reconnection: exponential backoff (1s, 2s, 4s, … capped at `max_backoff`)
