# Sample Queries for hex-docs-search

Quick reference for common search patterns and expected outputs.

## Basic Function Documentation (HexDocs)

**Query**: "How do I use Jason.decode!/2?"

**Expected behavior**:
1. Fetch HexDocs directly:
   ```bash
   web "https://hexdocs.pm/jason/Jason.html#decode!/2" "Extract documentation for decode!/2 function"
   ```
2. Present documentation with signature and examples

**Output format**:
```
Found jason documentation on HexDocs:

**Package**: jason
**URL**: https://hexdocs.pm/jason/Jason.html#decode!/2

**Documentation**:
@doc """
Decodes a JSON string...
"""
@spec decode!(String.t(), [decode_opt()]) :: term()
def decode!(input, opts \\ [])
```

---

## Module Overview

**Query**: "What does Phoenix.LiveView.JS do?"

**Expected behavior**:
1. Fetch module documentation:
   ```bash
   web "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.JS.html" "Extract overview and available commands"
   ```
2. Present module purpose and key functions

**Key sections to include**:
- Module purpose
- Available commands (push, toggle, show, hide, etc.)
- Basic usage examples

---

## Exploratory Search

**Query**: "Search for changeset in Ecto docs"

**Expected behavior**:
1. Search HexDocs:
   ```bash
   web "https://hexdocs.pm/ecto/search.html?q=changeset" "Find all references to changeset"
   ```
2. Present relevant modules and functions

**Output format**:
```
Found references to "changeset" in Ecto:

**Modules**:
- Ecto.Changeset - Main changeset module
- Ecto.Multi - Uses changesets in multi operations

**Key Functions**:
- Ecto.Changeset.cast/4
- Ecto.Changeset.validate_required/3
- Ecto.Changeset.put_change/3
```

---

## Version-Specific Documentation

**Query**: "Jason.decode!/2 docs for version 1.4.1"

**Expected behavior**:
1. Check project version:
   ```bash
   grep '"jason"' mix.lock
   ```
2. Fetch version-specific docs:
   ```bash
   web "https://hexdocs.pm/jason/1.4.1/Jason.html#decode!/2" "Extract decode!/2 documentation"
   ```

**Note**: HexDocs maintains all versions at `https://hexdocs.pm/<package>/<version>/<Module>.html`

---

## Package Overview

**Query**: "What is the Timex library?"

**Expected behavior**:
1. Fetch package info:
   ```bash
   web "https://hex.pm/packages/timex" "Extract package description and purpose"
   ```
2. Fetch getting started:
   ```bash
   web "https://hexdocs.pm/timex/readme.html" "Extract installation and key features"
   ```
3. Present overview with installation instructions

---

## Implementation Details (Local Source)

**Query**: "Show me how Jason.decode!/2 is implemented"

**Expected behavior**:
1. Check if package is installed locally:
   ```
   Use Glob: pattern="deps/jason/lib/**/*.ex"
   ```
2. Search for implementation:
   ```
   Use Grep: pattern="def decode!", path="deps/jason/lib", output_mode="content", -A=30
   ```
3. Read full source file if needed

**Note**: Use local deps when user needs source code, not just documentation

---

## Project Usage Examples

**Query**: "Show me how Phoenix.PubSub is used in this project"

**Expected behavior**:
1. Search codebase for usage:
   ```
   Use Grep: pattern="Phoenix.PubSub\.(subscribe|broadcast)", path="lib", output_mode="content", -A=3
   ```
2. Search test files for examples:
   ```
   Use Grep: pattern="Phoenix.PubSub", path="test", output_mode="content", -A=5
   ```
3. Present real usage from codebase

---

## Troubleshooting: Page Not Found

**Symptom**: HexDocs returns 404

**Solutions**:
1. Check package name spelling (underscores: `phoenix_live_view` not `phoenix-live-view`)
2. Module might be in different package (e.g., `Ecto.Query` is in `ecto`, not `ecto_sql`)
3. Try package overview first to find correct module names:
   ```bash
   web "https://hexdocs.pm/ecto/overview.html" "List available modules"
   ```

---

## Troubleshooting: Need Offline Access

**Symptom**: Need docs without network access

**Solution**: Use local deps if available:
```
# Find local package
Use Glob: pattern="deps/<package_name>/lib/**/*.ex"

# Search for @doc annotations
Use Grep: pattern="@moduledoc|@doc", path="deps/<package_name>/lib", output_mode="content", -A=10
```

**Note**: This is a fallback - HexDocs is preferred for currency and completeness
