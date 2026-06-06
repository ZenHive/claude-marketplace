---
name: tidewave-guide
description: Tidewave MCP tools for interacting with a running Elixir app. ALWAYS check before using project_eval, IEx-style evaluation, runtime code execution, database queries, or log viewing. Use when setting up Tidewave, exploring APIs at runtime, or following the "explore before coding" workflow.
allowed-tools: Read
---

# Tidewave Guide for Elixir Development

Tidewave provides MCP tools that let Claude Code interact directly with your running Elixir application.

## Scope

WHAT THIS SKILL DOES:
  ✓ Tidewave MCP tool usage (project_eval, database queries, log viewing)
  ✓ Runtime exploration of running Elixir apps
  ✓ "Explore before coding" workflow

WHAT THIS SKILL DOES NOT DO:
  ✗ General MCP server configuration (→ plugin-dev:mcp-integration)
  ✗ Static code analysis or compilation (→ mix compile, Dialyzer)
  ✗ Package API documentation lookup (→ hex-docs-search)

## When to use this skill

- Setting up Tidewave in a project
- Learning the "explore before coding" workflow
- Understanding what Tidewave can do

## What is Tidewave?

Tidewave exposes MCP endpoints from your running Elixir app, enabling Claude Code to:

- **Evaluate Elixir code** in your project's runtime context
- **Query your database** directly
- **Search documentation** for loaded packages
- **Find source locations** for modules/functions
- **View logs** with filtering

## Setup

### Phoenix projects

Add to `mix.exs`:

```elixir
{:tidewave, "~> 0.5", only: :dev}
```

Add to `lib/my_app_web/endpoint.ex` **ABOVE** `if code_reloading?`:

```elixir
if Code.ensure_loaded?(Tidewave) do
  plug Tidewave
end
```

### Non-Phoenix projects

Add to `mix.exs`:

```elixir
{:tidewave, "~> 0.5", only: :dev},
{:bandit, "~> 1.0", only: :dev}
```

Add alias:

```elixir
defp aliases do
  [
    tidewave: ["run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4001) end)'"]
  ]
end
```

Start with: `iex -S mix tidewave`

### Register with Claude Code (one-time)

```bash
# Phoenix (port 4000)
claude mcp add --transport http tidewave http://localhost:4000/tidewave/mcp

# Non-Phoenix (port 4001)
claude mcp add --transport http tidewave http://localhost:4001/tidewave/mcp
```

## Available MCP Tools

Check your available Tidewave tools - they follow the pattern `mcp__tidewave__*`. Common tools include:

| Tool | Purpose |
|------|---------|
| `get_docs` | Module/function documentation |
| `get_source_location` | Find source file locations |
| `project_eval` | Evaluate Elixir code in project context |
| `execute_sql_query` | Run SQL against your database |
| `get_ecto_schemas` | List all Ecto schemas |
| `search_package_docs` | Search Hex docs for dependencies |
| `get_logs` | View application logs with filtering |

**Important:** Tool availability and parameters may vary by Tidewave version. Check what's available in your current session.

## "Explore BEFORE Coding" Workflow

The key insight: **understand the running system before writing code**.

### Traditional (error-prone)
1. Read docs → Write code → Hit errors → Debug

### Explore-first (recommended)
1. **Explore with `project_eval`** - Test functions with real data
2. **Check schemas** - Understand data structures
3. **Query database** - See actual data patterns
4. **Look up docs** - Clarify behavior
5. **Write code** - Implementation matches reality

### Example workflow

**Task:** Add a function to get a user's recent orders

```elixir
# 1. What schemas exist?
mcp__tidewave__get_ecto_schemas()

# 2. What fields does Order have?
mcp__tidewave__project_eval("MyApp.Orders.Order.__schema__(:fields)")

# 3. What functions exist in the context?
mcp__tidewave__get_docs("MyApp.Orders")

# 4. Prototype the query
mcp__tidewave__project_eval("""
  import Ecto.Query
  MyApp.Orders.Order
  |> where([o], o.user_id == 1)
  |> order_by([o], desc: o.inserted_at)
  |> limit(10)
  |> MyApp.Repo.all()
""")

# 5. Now write the function - you know exactly what works
```

## Best Practices

1. **Explore first, code second** - Use `project_eval` before writing
2. **Check real data** - Don't assume; query it
3. **Prototype in eval** - Test logic before committing
4. **Be careful with mutations** - `project_eval` runs in dev; changes persist

## Troubleshooting

- **Tools not appearing**: Run `claude mcp list`, re-register if needed
- **Connection failed**: Check Phoenix server is running on expected port
- **Eval errors**: Verify code syntax and that project compiles
