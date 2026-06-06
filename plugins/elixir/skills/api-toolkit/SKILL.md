---
name: api-toolkit
description: ApiToolkit — reusable infrastructure for Elixir API services. Use when adding rate limiting (InboundLimiter for protecting endpoints with sliding-window per-key counts; RateLimiter for throttling outbound calls with a token bucket GenServer), caching API responses with TTL via ApiToolkit.Cache, tracking per-endpoint metrics with ApiToolkit.Metrics, or defining API providers with the `defapi` macro and auto-generated discovery (ApiToolkit.Provider, ApiToolkit.Discovery). Covers correct module choice (inbound vs outbound throttling), supervisor wiring, and the discovery surface (8 generated functions including `providers/0`, `all_endpoints/0`, `search/1`, `help/0`).
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/api-toolkit.md — do not edit manually -->

## ApiToolkit — Reusable API Infrastructure

**Package:** `api_toolkit` on Hex | **We maintain this** | **Pin:** see `elixir-setup.md`

Shared infrastructure for API services. Zero runtime deps beyond the BEAM.

### Modules

| Module | Purpose | When to Use |
|--------|---------|-------------|
| `ApiToolkit.InboundLimiter` | Per-key sliding window rate limiter (ETS + persistent_term) | Protecting endpoints from abuse. Per-IP, per-API-key, or any term. |
| `ApiToolkit.RateLimiter` | Token bucket GenServer (outbound throttling) | Calling external APIs with rate limits. Blocks until token available. |
| `ApiToolkit.Metrics` | ETS-based request tracking (counts, response times, hit rates) | Tracking per-endpoint usage, response times, cache effectiveness. |
| `ApiToolkit.Cache` | ETS cache with TTL and periodic cleanup | Caching API responses with expiration. |
| `ApiToolkit.Provider` | Behaviour + `defapi` macro for API providers | Defining API providers with auto-generated discovery metadata. |
| `ApiToolkit.Discovery` | `use` macro generating 8 discovery functions from providers | Central discovery: `providers/0`, `all_endpoints/0`, `search/1`, `help/0`, etc. |

### InboundLimiter (protect my endpoints)

Sliding window (Cloudflare/Nginx algorithm). Hot path is direct ETS — sub-μs latency, no GenServer call. GenServer only handles periodic cleanup. Per-node only.

```elixir
{ApiToolkit.InboundLimiter, name: MyApp.IPLimiter, limit: {100, :minute}}

case ApiToolkit.InboundLimiter.check(MyApp.IPLimiter, client_ip) do
  :ok -> handle_request(conn)
  {:rate_limited, retry_after_ms} -> send_resp(conn, 429, "Too Many Requests")
end

ApiToolkit.InboundLimiter.status(MyApp.IPLimiter, client_ip)  # {:ok, count} | :not_found
ApiToolkit.InboundLimiter.reset(MyApp.IPLimiter, client_ip)
```

Options: `:name` (req), `:limit` (req, `{count, :second | :minute | :day}`), `:cleanup_interval_ms` (default 60000).

### RateLimiter (throttle my outbound calls)

Token bucket — **blocks** callers until a token is available. One GenServer per rate limit. Queue, don't reject.

```elixir
{ApiToolkit.RateLimiter, name: MyApp.RateLimiter.Brave, rate: {1, :second}}
ApiToolkit.RateLimiter.acquire(MyApp.RateLimiter.Brave)   # blocks
ApiToolkit.RateLimiter.status(MyApp.RateLimiter.Brave)    # %{tokens_available:, max_tokens:, queue_depth:}
```

### Metrics (request tracking)

ETS, atomic writes. Per-endpoint: count, duration, cache hit/miss, last request.

```elixir
ApiToolkit.Metrics                                # supervision tree

ApiToolkit.Metrics.record("/api/hex/encode", :miss, 1200)   # (path, :hit | :miss, duration_μs)
ApiToolkit.Metrics.get_all()
ApiToolkit.Metrics.summary()
ApiToolkit.Metrics.reset()
```

For services without caching, pass `:miss`.

### Cache (TTL ETS)

```elixir
ApiToolkit.Cache                                  # or {ApiToolkit.Cache, cleanup_interval_ms: 120_000}

ApiToolkit.Cache.put("key", value, ttl_ms: 300_000)
ApiToolkit.Cache.get("key")                       # {:ok, value} | :miss
```

### Provider + Discovery (API Provider DSL)

For building API proxy/cache services with multiple providers (like api_cache).

```elixir
# Define a provider
defmodule MyApp.Providers.Brave do
  use ApiToolkit.Provider,
    name: "Brave Search",
    description: "Web search via Brave API",
    rate_limit: "1 req/sec",
    cache_ttl_ms: 300_000

  defapi :search,
    path: "/brave/search",
    description: "Search the web",
    params: [%{name: "q", type: :string, required: true, description: "Search query"}]
end

# Central discovery
defmodule MyApp.Discovery do
  use ApiToolkit.Discovery, providers: [MyApp.Providers.Brave, ...]
end

# Generated functions
MyApp.Discovery.providers()        # List all providers with metadata
MyApp.Discovery.all_endpoints()    # Flat list of all endpoints
MyApp.Discovery.search("search")   # Search by keyword
MyApp.Discovery.help()             # Compact LLM-friendly help string
MyApp.Discovery.by_provider()      # Grouped by provider
MyApp.Discovery.categories()       # All unique categories
MyApp.Discovery.by_category(:web)  # Filter by category
MyApp.Discovery.describe("/brave/search")  # Single endpoint detail
```

### Choosing the Right Module

| Need | Module | Key Difference |
|------|--------|----------------|
| Protect my endpoints from abuse | `InboundLimiter` | Returns `:ok | {:rate_limited, ms}` immediately |
| Throttle my calls to external APIs | `RateLimiter` | Blocks until token available |
| Track request counts and latency | `Metrics` | Atomic ETS writes, query with `summary/0` |
| Cache responses with expiration | `Cache` | TTL-based, periodic cleanup |
| Define API providers with discovery | `Provider` + `Discovery` | Macro DSL, auto-generated metadata |
