---
name: usage-rules
description: Search for package-specific usage rules, coding conventions, and best practices from Elixir/Erlang packages. ALWAYS invoke before writing code that uses Ash, Phoenix, Ecto, LiveView, or any Hex package — provides good/bad examples, common mistakes, and recommended patterns. This skill provides CONVENTIONS, not API docs (use hex-docs-search for API documentation).
allowed-tools: Read, Grep, Glob, Bash, AskUserQuestion
---

# Usage Rules Search

Comprehensive search for Elixir and Erlang package usage rules and best practices, following a cascading strategy to find the most relevant coding conventions and patterns.

## Scope

WHAT THIS SKILL DOES:
  ✓ Coding conventions, good/bad examples, patterns, idioms, style rules
  ✓ Package-specific best practices from `.usage-rules/` cache
  ✓ Context-aware section extraction based on coding context
  ✓ Cascading search: local deps → fetched cache → progressive fetch

WHAT THIS SKILL DOES NOT DO:
  ✗ API documentation, function signatures, typespecs (→ hex-docs-search)
  ✗ General Elixir patterns not tied to a specific package (→ CLAUDE.md)
  ✗ Runtime exploration of loaded modules (→ tidewave-guide)

## When to use this skill

- Look up coding conventions for a Hex package
- Find best practices and recommended patterns
- See good/bad code examples for proper usage
- Understand common mistakes to avoid
- Learn package-specific idioms and conventions
- Get context-aware recommendations for implementation

## Search strategy

This skill implements a **cascading search** that prioritizes local and contextual information:

1. **Local dependencies** - Search installed packages in `deps/` directory for usage-rules.md
2. **Fetched cache** - Check previously fetched usage rules in `.usage-rules/`
3. **Progressive fetch** - Automatically fetch package and extract usage-rules.md if missing
4. **Context-aware extraction** - Extract relevant sections based on coding context
5. **Fallback** - Note when package doesn't provide usage rules, suggest alternatives

## Instructions

### Step 1: Identify the package and context

Extract the package name and identify the coding context from the user's question.

**Package name examples**:
- "Ash best practices" -> Package: `ash`
- "Phoenix LiveView patterns" -> Package: `phoenix_live_view`
- "How to use Ecto properly?" -> Package: `ecto`

**Context keywords**: querying, error handling, actions, relationships, testing, authorization, structure

### Step 2: Search local dependencies

Use **Glob** and **Grep** to search the `deps/` directory:

1. **Find usage-rules.md**: `Glob: pattern="deps/<package_name>/usage-rules.md"`
2. **Check sub-rules**: `Glob: pattern="deps/<package_name>/usage-rules/*.md"`
3. **Search sections**: `Grep: pattern="^## ", path="deps/<package_name>/usage-rules.md"`
4. **Extract relevant section**: `Grep: pattern="^## Error Handling", -A=50`
5. **Read complete file** if broader context needed

If not found locally, proceed to Step 3.

### Step 3: Check fetched cache and fetch if needed

#### 3.1: Check cache
```
Glob: pattern=".usage-rules/<package_name>-*/usage-rules.md"
```

#### 3.2: Determine version to fetch
1. Check mix.lock for locked version
2. Check mix.exs for version constraint
3. Get latest from hex.pm: `curl -s "https://hex.pm/api/packages/<package_name>" | jq -r '.releases[0].version'`
4. If ambiguous, use **AskUserQuestion** to prompt

#### 3.3: Fetch and cache
```bash
mkdir -p .usage-rules/.tmp
mix hex.package fetch <package_name> <version> --unpack --output .usage-rules/.tmp/<package_name>-<version>

# If usage-rules.md exists, copy to cache
mkdir -p ".usage-rules/<package_name>-<version>"
cp ".usage-rules/.tmp/<package_name>-<version>/usage-rules.md" ".usage-rules/<package_name>-<version>/"

# Clean up temp
rm -rf ".usage-rules/.tmp/<package_name>-<version>"
```

#### 3.4: Git ignore recommendation
Suggest adding `/.usage-rules/` to `.gitignore` (once per session, only if fetching occurred).

### Step 4: Extract relevant sections based on context

#### 4.1: Find section headings
```
Grep: pattern="^## ", path=".usage-rules/<package>-<version>/usage-rules.md", -n=true
```

#### 4.2: Match context to sections
- "querying" -> "Querying", "Query", "Filters", "Search"
- "error handling" -> "Error", "Validation", "Exception"
- "actions" -> "Actions", "Create", "Update", "Delete", "CRUD"

#### 4.3: Extract matched sections
Adjust `-A` value based on section length (50 for small, 100 for medium, 150 for large).

#### 4.4: Include code examples
Look for `# GOOD`, `# BAD`, `# PREFERRED`, `# AVOID` markers in code blocks.

### Step 5: Present usage rules

Format output with: location/version, relevant section content, code examples, link to full rules, and note about hex-docs-search for API documentation.

## Output format

### If found (local or cached):
```
Found usage rules for <package_name>:

**Location**: deps/<package_name>/usage-rules.md (or cache location)
**Version**: <version>

**Relevant Best Practices** (<section_name>):
<extracted section content with code examples>

---
**Full Rules**: <path to full file>
**Integration**: For API documentation, use the hex-docs-search skill.
```

### If not available:
```
Package '<package_name>' does not provide usage-rules.md.

**Alternatives**:
- Use hex-docs-search skill for API documentation
- Check package README or official documentation

**Current packages with usage rules**:
- ash, ash_postgres, ash_json_api (Ash Framework ecosystem)
- igniter, spark, reactor (Build tools and engines)
```

## Tool usage summary

1. **Glob** - Find usage-rules.md files in deps/, .usage-rules/
2. **Grep** - Search for section headings, context keywords, code examples
3. **Read** - Read complete usage rules files when broader context needed
4. **Bash** - Fetch packages, version resolution, extract and cache rules
5. **AskUserQuestion** - Prompt for version when ambiguous

## Best practices

1. **Start local**: Always check local dependencies first
2. **Check cache before fetch**: Look in `.usage-rules/` before fetching
3. **Context-aware extraction**: Extract relevant sections, not entire file
4. **Show code examples**: Always include good/bad pattern examples
5. **Link to source**: Provide file path for complete rules
6. **Note integration**: Mention hex-docs-search for complementary API documentation
7. **Offline capability**: Once fetched, rules available without network

## References

For detailed examples and troubleshooting:

- **`references/examples.md`** - 5 detailed search examples (Ash querying, error handling, progressive fetch, cached rules, context-aware extraction)
- **`references/troubleshooting.md`** - Solutions for common issues (package not found, fetch failures, section extraction, version mismatches)
