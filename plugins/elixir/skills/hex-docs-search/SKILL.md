---
name: hex-docs-search
description: Research Hex package API documentation — function signatures, module docs, typespecs, and usage examples. ALWAYS invoke when you need to look up how a package works, find available functions, or check API details for Phoenix, Ecto, Ash, Credo, Sobelow, or any Hex dependency. This skill provides API DOCS, not conventions (use usage-rules for coding patterns).
allowed-tools: Read, Grep, Glob, Bash, WebSearch, AskUserQuestion
---

# Hex Documentation Search

Search for Elixir and Erlang package documentation using HexDocs as the primary source, with local dependencies for version-specific needs.

## Scope

WHAT THIS SKILL DOES:
  ✓ Function signatures, module docs, typespecs, API surface
  ✓ Package investigation, dependency evaluation
  ✓ Usage examples from official HexDocs documentation
  ✓ Cascading search: HexDocs → local deps → codebase usage → web search

WHAT THIS SKILL DOES NOT DO:
  ✗ Coding conventions, best practices, good/bad patterns (→ usage-rules)
  ✗ Runtime exploration of loaded modules (→ tidewave-guide)
  ✗ General Elixir language documentation (→ elixir-lang.org)

## When to use this skill

Use this skill when you need to:
- Look up documentation for a Hex package or dependency
- Find function signatures, module documentation, or type specs
- See usage examples of a library or module
- Understand how a dependency is used in the current project
- Search for Elixir/Erlang standard library documentation

## Search strategy

This skill prioritizes **speed and currency** by searching HexDocs first:

1. **HexDocs** - Search official documentation on hexdocs.pm (primary)
2. **Local dependencies** - Check `deps/` for version-specific docs or source code
3. **Codebase usage** - Find how packages are used in the current project
4. **Web search** - General web search (fallback)

## Instructions

### Step 1: Identify the search target

Extract the package name and optionally the module or function name from the user's question.

Examples:
- "How do I use Phoenix.LiveView?" → Package: `phoenix_live_view`, Module: `Phoenix.LiveView`
- "Show me Ecto query examples" → Package: `ecto`, Module: `Ecto.Query`
- "What does Jason.decode!/1 do?" → Package: `jason`, Module: `Jason`, Function: `decode!`

### Step 2: Search HexDocs (Primary)

Use the **Bash** tool with the `web` command to fetch documentation from hexdocs.pm.

#### 2.1: Direct module/function lookup

For specific modules or functions, fetch the documentation page directly:

```bash
# Fetch module documentation
web "https://hexdocs.pm/<package_name>/Module.Name.html" "Extract the documentation for this module, including function signatures and examples"

# Fetch function documentation (anchor to specific function)
web "https://hexdocs.pm/<package_name>/Module.Name.html#function_name/arity" "Extract the documentation for this specific function"
```

**Examples:**

```bash
# Phoenix.LiveView mount/3
web "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#mount/3" "Extract documentation for mount/3 callback"

# Ecto.Query
web "https://hexdocs.pm/ecto/Ecto.Query.html" "Extract overview and key functions from Ecto.Query module"

# Jason.decode!/2
web "https://hexdocs.pm/jason/Jason.html#decode!/2" "Extract documentation for decode!/2 function"
```

#### 2.2: Search HexDocs for broader queries

For exploratory searches or when the exact module isn't known:

```bash
# Search within a package's documentation
web "https://hexdocs.pm/<package_name>/search.html?q=<search_term>" "Find relevant modules and functions matching the search term"

# Or search the package overview/guides
web "https://hexdocs.pm/<package_name>/readme.html" "Extract package overview, installation, and getting started guide"
```

**Examples:**

```bash
# Search for "changeset" in Ecto docs
web "https://hexdocs.pm/ecto/search.html?q=changeset" "Find all references to changeset in Ecto documentation"

# Phoenix LiveView overview
web "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html" "Extract overview of LiveView lifecycle and key callbacks"
```

#### 2.3: Get package metadata from hex.pm

For version information or package details:

```bash
# Get package info including latest version
web "https://hex.pm/packages/<package_name>" "Extract package description, latest version, and dependencies"
```

### Step 3: Check local dependencies (Version-specific)

If the user needs documentation matching their **exact project version**, or needs source code/implementation details:

#### 3.1: Find local package

```
Use Glob: pattern="deps/<package_name>/**/*.ex"
```

If found, the package is installed locally.

#### 3.2: Search source code

```
# Find module definition
Use Grep: pattern="defmodule <ModuleName>", path="deps/<package_name>/lib"

# Find function definition
Use Grep: pattern="def <function_name>", path="deps/<package_name>/lib", output_mode="content", -A=5

# Find documentation annotations
Use Grep: pattern="@moduledoc|@doc", path="deps/<package_name>/lib", output_mode="content", -A=10
```

#### 3.3: Read source files

Use the **Read** tool to get full context from source files.

### Step 4: Search codebase usage

Find how the package is used in the current project:

```
# Find imports and aliases
Use Grep: pattern="alias <ModuleName>|import <ModuleName>", path="lib", output_mode="content", -n=true

# Find function calls
Use Grep: pattern="<ModuleName>\.", path="lib", output_mode="content", -A=3

# Search test files for examples
Use Grep: pattern="<ModuleName>", path="test", output_mode="content", -A=5
```

This provides **real-world usage examples** from the current project.

### Step 5: Web search fallback

If HexDocs doesn't have sufficient information:

```
Use WebSearch: query="site:hexdocs.pm <package_name> <module_or_function>"
```

Or for general documentation:

```
Use WebSearch: query="elixir <package_name> <module_or_function> documentation examples"
```

## Output format

### If found on HexDocs:

```
Found <package_name> documentation on HexDocs:

**Package**: <package_name>
**Version**: <version>
**URL**: https://hexdocs.pm/<package_name>/<Module>.html

**Documentation**:
<extracted documentation>

**Key Functions**:
<list of relevant functions with signatures>
```

### If supplemented with local source:

```
Found <package_name> on HexDocs (supplemented with local source):

**HexDocs**: https://hexdocs.pm/<package_name>/<Module>.html
**Local version**: <version from mix.lock>

**Documentation**:
<from hexdocs>

**Implementation** (from local source):
<relevant source code>

**Usage in this project**:
<usage examples from codebase>
```

## Examples

### Example 1: Quick function lookup

**User asks**: "What does Phoenix.LiveView mount/3 do?"

**Search process**:
1. Fetch HexDocs directly:
   ```bash
   web "https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#mount/3" "Extract documentation for mount/3"
   ```
2. Present documentation immediately

### Example 2: Exploring a module

**User asks**: "Show me Ecto.Query examples"

**Search process**:
1. Fetch module overview:
   ```bash
   web "https://hexdocs.pm/ecto/Ecto.Query.html" "Extract overview and example queries"
   ```
2. Search project for local usage:
   ```
   Use Grep: pattern="import Ecto.Query|from.*in", path="lib", output_mode="content", -A=5
   ```
3. Present HexDocs examples + project examples

### Example 3: Version-specific documentation

**User asks**: "How does Jason.decode!/2 work in our project's version?"

**Search process**:
1. Check local version:
   ```bash
   grep '"jason"' mix.lock
   ```
2. Fetch version-specific docs:
   ```bash
   web "https://hexdocs.pm/jason/1.4.1/Jason.html#decode!/2" "Extract decode!/2 documentation"
   ```
3. Or read local source if needed:
   ```
   Use Grep: pattern="def decode!", path="deps/jason/lib", output_mode="content", -A=20
   ```

### Example 4: Implementation details

**User asks**: "Show me how Jason.decode!/2 is implemented"

**Search process**:
1. Check if jason is installed locally:
   ```
   Use Glob: pattern="deps/jason/lib/**/*.ex"
   ```
2. Search for implementation:
   ```
   Use Grep: pattern="def decode!", path="deps/jason/lib", output_mode="content", -A=30
   ```
3. Read full source file if needed

### Example 5: Unknown package exploration

**User asks**: "What is the Timex library?"

**Search process**:
1. Fetch package info:
   ```bash
   web "https://hex.pm/packages/timex" "Extract package description and purpose"
   ```
2. Fetch documentation overview:
   ```bash
   web "https://hexdocs.pm/timex/readme.html" "Extract getting started guide and key features"
   ```
3. Present overview with installation instructions

## Tool usage summary

Use tools in this priority:

1. **Bash** with `web` command - Fetch HexDocs pages directly (primary)
2. **Glob** - Check if package exists locally
3. **Grep** - Search local source code for implementation details
4. **Read** - Read full source files
5. **WebSearch** - Fallback for broader searches

## Best practices

1. **Start with HexDocs**: Always try hexdocs.pm first - it's fast and current
2. **Use direct URLs**: When you know the module, fetch it directly (faster than searching)
3. **Version awareness**: Note which version docs are from vs what's installed locally
4. **Show project usage**: Real examples from the codebase are valuable context
5. **Link to source**: Provide HexDocs URLs so users can explore further
6. **Local for implementation**: Use local deps when users need source code, not just docs
7. **Progressive disclosure**: Start with summary, offer to dive deeper

## Troubleshooting

### HexDocs page not found

- Check package name spelling (use underscores: `phoenix_live_view` not `phoenix-live-view`)
- Module might be in a different package (e.g., `Ecto.Query` is in `ecto`, not `ecto_sql`)
- Try the package overview page first to find correct module names

### Need older version docs

- HexDocs keeps all versions: `https://hexdocs.pm/<package>/<version>/<Module>.html`
- Check mix.lock for project's exact version
- Use local deps for version matching

### Documentation insufficient

- Check if package has guides: `https://hexdocs.pm/<package>/overview.html`
- Read source code directly from local deps
- Search for blog posts or tutorials with WebSearch
