---
name: integration-testing
description: Integration testing patterns for Elixir — external API tests, credential handling, environment configuration. ALWAYS invoke when writing tests that call real APIs, need API keys, or connect to external services. Covers credential management, conditional test execution, and never-skip-silently patterns.
allowed-tools: Read
---

# Integration Testing Patterns

Patterns for writing robust integration tests that require external credentials, API keys, or service access.

## Scope

WHAT THIS SKILL DOES:
  ✓ Tests against real external services (APIs, databases)
  ✓ Credential handling patterns (flunk with setup instructions)
  ✓ Environment-specific test configuration
  ✓ Never-skip-silently patterns

WHAT THIS SKILL DOES NOT DO:
  ✗ General ExUnit patterns or unit testing (→ CLAUDE.md testing rules)
  ✗ Mocking/stubbing strategies (→ this skill advocates real-first)
  ✗ Test output formatting (→ ex-unit-json skill)

## When to use this skill

- Writing tests that require API credentials
- Testing against external services (APIs, databases, etc.)
- Setting up integration test infrastructure
- Handling environment-specific test configuration

## Core Principle: Never Skip Silently

**Tests that skip silently are worse than no tests.** A test suite showing "0 failures" with "0 tests run" is lying.

```elixir
# ❌ BAD: Silent skip - test appears to pass when it didn't run
setup do
  api_key = System.get_env("API_KEY")
  if is_nil(api_key), do: :skip
  {:ok, api_key: api_key}
end

# ❌ BAD: Returns :ok on nil - same problem
test "authenticated endpoint", %{credentials: nil} do
  :ok  # Test silently passes without testing anything
end

# ✅ GOOD: Fails loudly with actionable instructions
test "authenticated endpoint", %{credentials: credentials} do
  if is_nil(credentials) do
    flunk("""
    Missing credentials!

    Set these environment variables:
      export API_KEY="your_key"
      export API_SECRET="your_secret"

    Get credentials at: https://example.com/api-keys
    """)
  end

  # Actual test code...
end
```

## Integration Helper Module

Create a helper module to reduce duplication across integration tests:

```elixir
defmodule MyApp.Test.IntegrationHelper do
  @moduledoc """
  Helper macros and functions for integration tests.
  """

  import ExUnit.Assertions

  @doc """
  Flunks with a helpful message if credentials are nil.

  ## Options

    * `:testnet` - If true, env var names include TESTNET prefix (default: false)
    * `:passphrase` - If true, mentions passphrase in error message (default: false)
    * `:url` - URL where to get credentials (optional)

  ## Examples

      require_credentials!(credentials, "stripe")
      require_credentials!(credentials, "binance", testnet: true, url: "https://testnet.binance.vision")
      require_credentials!(credentials, "okx", passphrase: true)
  """
  defmacro require_credentials!(credentials, service_name, opts \\ []) do
    quote bind_quoted: [credentials: credentials, service_name: service_name, opts: opts] do
      if is_nil(credentials) do
        MyApp.Test.IntegrationHelper.flunk_missing_credentials(service_name, opts)
      end
    end
  end

  @doc """
  Flunks with a formatted error message for missing credentials.
  """
  def flunk_missing_credentials(service_name, opts \\ []) do
    testnet = Keyword.get(opts, :testnet, false)
    passphrase = Keyword.get(opts, :passphrase, false)
    url = Keyword.get(opts, :url)

    prefix = String.upcase(service_name)
    testnet_part = if testnet, do: "_TESTNET", else: ""

    env_vars =
      if passphrase do
        """
          export #{prefix}#{testnet_part}_API_KEY="your_key"
          export #{prefix}#{testnet_part}_API_SECRET="your_secret"
          export #{prefix}_PASSPHRASE="your_passphrase"
        """
      else
        """
          export #{prefix}#{testnet_part}_API_KEY="your_key"
          export #{prefix}#{testnet_part}_API_SECRET="your_secret"
        """
      end

    url_line = if url, do: "\nGet credentials at: #{url}", else: ""

    flunk("""
    Missing #{if testnet, do: "testnet ", else: ""}credentials!

    Set these environment variables:
    #{String.trim(env_vars)}#{url_line}
    """)
  end

  @doc """
  Standard setup for integration tests that loads credentials from env.

  Returns `{:ok, credentials: credentials}` for use in ExUnit setup.

  ## Options

    * `:testnet` - If true, env var names include TESTNET prefix (default: false)
    * `:passphrase` - If true, also loads passphrase from env (default: false)
    * `:sandbox` - Value for sandbox mode (default: value of `:testnet`)
    * `:secret_suffix` - Override the secret env var suffix (default: "API_SECRET")

  ## Examples

      # Standard API (SERVICE_API_KEY, SERVICE_API_SECRET)
      setup_credentials("stripe")

      # Testnet (BINANCE_TESTNET_API_KEY, BINANCE_TESTNET_API_SECRET)
      setup_credentials("binance", testnet: true)

      # With passphrase (OKX_API_KEY, OKX_API_SECRET, OKX_PASSPHRASE)
      setup_credentials("okx", passphrase: true)

      # Custom secret suffix (DERIBIT_API_KEY, DERIBIT_SECRET_KEY)
      setup_credentials("deribit", secret_suffix: "SECRET_KEY")
  """
  def setup_credentials(service_name, opts \\ []) do
    testnet = Keyword.get(opts, :testnet, false)
    passphrase_opt = Keyword.get(opts, :passphrase, false)
    sandbox = Keyword.get(opts, :sandbox, testnet)
    secret_suffix = Keyword.get(opts, :secret_suffix, "API_SECRET")

    prefix = String.upcase(service_name)
    testnet_part = if testnet, do: "_TESTNET", else: ""

    api_key = System.get_env("#{prefix}#{testnet_part}_API_KEY")
    secret = System.get_env("#{prefix}#{testnet_part}_#{secret_suffix}")

    passphrase =
      if passphrase_opt do
        System.get_env("#{prefix}_PASSPHRASE")
      end

    credentials =
      cond do
        passphrase_opt and api_key && secret && passphrase ->
          %{
            api_key: api_key,
            secret: secret,
            passphrase: passphrase,
            sandbox: sandbox
          }

        not passphrase_opt and api_key && secret ->
          %{
            api_key: api_key,
            secret: secret,
            sandbox: sandbox
          }

        true ->
          nil
      end

    {:ok, credentials: credentials}
  end
end
```

## Usage in Tests

```elixir
defmodule MyApp.ExternalServiceIntegrationTest do
  use ExUnit.Case, async: false
  import MyApp.Test.IntegrationHelper

  @moduletag :integration

  setup do
    setup_credentials("stripe")
  end

  test "creates a customer", %{credentials: credentials} do
    require_credentials!(credentials, "stripe", url: "https://dashboard.stripe.com/apikeys")

    # Test code with credentials...
    assert {:ok, customer} = StripeClient.create_customer(credentials, %{email: "test@example.com"})
    assert customer.email == "test@example.com"
  end
end
```

## Running Integration Tests

Tag integration tests and exclude by default:

```elixir
# test/test_helper.exs
ExUnit.configure(exclude: [:integration])
ExUnit.start()
```

```bash
# Run unit tests only (default)
mix test

# Run integration tests only
mix test --only integration

# Run all tests
mix test --include integration
```

## Credentials Struct Pattern

For projects with typed credentials, define a struct:

```elixir
defmodule MyApp.Credentials do
  @moduledoc """
  Credentials for external service authentication.
  """

  @enforce_keys [:api_key, :secret]
  defstruct [:api_key, :secret, :passphrase, sandbox: false]

  @type t :: %__MODULE__{
          api_key: String.t(),
          secret: String.t(),
          passphrase: String.t() | nil,
          sandbox: boolean()
        }
end
```

Then update the helper to return structs:

```elixir
def setup_credentials(service_name, opts \\ []) do
  # ... same logic ...

  credentials =
    cond do
      passphrase_opt and api_key && secret && passphrase ->
        %MyApp.Credentials{
          api_key: api_key,
          secret: secret,
          passphrase: passphrase,
          sandbox: sandbox
        }

      not passphrase_opt and api_key && secret ->
        %MyApp.Credentials{
          api_key: api_key,
          secret: secret,
          sandbox: sandbox
        }

      true ->
        nil
    end

  {:ok, credentials: credentials}
end
```

## Anti-Patterns to Avoid

### Never Hide Errors

```elixir
# ❌ MAKES ANY OUTCOME PASS - COMPLETELY WORTHLESS
case result do
  {:ok, _} -> assert true
  {:error, _} -> assert true  # This makes ALL failures pass silently!
end

# ❌ COMMENTS DON'T VALIDATE BEHAVIOR
{:error, reason} ->
  IO.puts("Error may be normal: #{inspect(reason)}")
  assert true  # Still worthless!

# ✅ EXPLICIT ABOUT WHAT'S ACCEPTABLE
case result do
  {:ok, data} -> assert is_map(data)
  {:error, :rate_limited} -> :ok  # This specific error is expected
  {:error, other} -> flunk("Unexpected error: #{inspect(other)}")
end
```

### Test Specific Behavior

```elixir
# ❌ Tests both success AND failure (tests nothing)
test "API call" do
  case call_api() do
    {:ok, _} -> :ok
    {:error, _} -> :ok
  end
end

# ✅ Separate tests for specific behaviors
test "returns data when authenticated" do
  assert {:ok, %{balance: _}} = call_api(valid_credentials())
end

test "returns unauthorized when credentials invalid" do
  assert {:error, :unauthorized} = call_api(invalid_credentials())
end
```

## Environment Variable Conventions

Consistent naming makes credentials discoverable:

| Pattern | Example | Use Case |
|---------|---------|----------|
| `{SERVICE}_API_KEY` | `STRIPE_API_KEY` | Production API key |
| `{SERVICE}_API_SECRET` | `STRIPE_API_SECRET` | Production secret |
| `{SERVICE}_TESTNET_API_KEY` | `BINANCE_TESTNET_API_KEY` | Testnet/sandbox key |
| `{SERVICE}_TESTNET_API_SECRET` | `BINANCE_TESTNET_API_SECRET` | Testnet/sandbox secret |
| `{SERVICE}_PASSPHRASE` | `OKX_PASSPHRASE` | Additional auth (some APIs) |

## Summary

1. **Never skip silently** - Use `flunk/1` with actionable instructions
2. **Create a helper module** - Reduce duplication across test files
3. **Tag integration tests** - Exclude by default, run explicitly
4. **Test specific behaviors** - Separate tests for success and error cases
5. **Use consistent env vars** - Follow naming conventions for discoverability
