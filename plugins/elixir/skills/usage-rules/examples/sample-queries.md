# Sample Queries for usage-rules

Quick reference for common usage rules searches and expected outputs.

## Basic Best Practices Query

**Query**: "What are the best practices for Ash actions?"

**Expected behavior**:
1. Find `deps/ash/usage-rules.md`
2. Locate `## Actions` section
3. Extract good/bad code examples

**Output format**:
```
Found usage rules for ash:

**Location**: deps/ash/usage-rules.md
**Version**: 3.5.20

**Relevant Best Practices** (Actions):

## Actions

**PREFER** - Create domain-specific actions:
```elixir
# GOOD - Specific business operations
create :register_user
update :activate_account
```

**AVOID** - Generic CRUD naming:
```elixir
# BAD - Generic naming
create :create
update :update
```
```

---

## Context-Aware Extraction

**Query**: "How should I handle errors in Ash?"

**Context keywords**: "error", "handle"

**Expected behavior**:
1. Search for "## Error" sections
2. Also search for "error", "validation", "exception" keywords
3. Extract multiple relevant sections

**Grep pattern**:
```
pattern="^## (Error|Validation)|error handling|# BAD.*error"
path="deps/ash/usage-rules.md"
output_mode="content"
-A=30
```

---

## Package Without Usage Rules

**Query**: "Phoenix LiveView best practices"

**Expected behavior**:
1. Check `deps/phoenix_live_view/usage-rules.md` (not found)
2. Check `.usage-rules/phoenix_live_view-*/` (not found)
3. Attempt fetch (package doesn't include usage-rules.md)
4. Return fallback suggestions

**Output format**:
```
Package 'phoenix_live_view' does not provide usage-rules.md.

**Alternatives**:
- Use hex-docs-search skill for API documentation
- Check Phoenix LiveView guides: https://hexdocs.pm/phoenix_live_view/
- Search for "phoenix liveview best practices" online

**Current packages with usage rules**:
- ash, ash_postgres, ash_json_api (Ash Framework ecosystem)
- igniter, spark, reactor (Build tools and engines)
```

---

## Fetching and Caching Rules

**Query**: "Spark DSL conventions"

**Expected behavior**:
1. Check local deps (not found)
2. Check cache (not found)
3. Prompt for version
4. Fetch package
5. Extract and cache usage-rules.md
6. Present rules

**Fetch commands**:
```bash
# Fetch package
mix hex.package fetch spark 2.2.24 --unpack --output .usage-rules/.tmp/spark-2.2.24

# Extract usage rules
cp .usage-rules/.tmp/spark-2.2.24/usage-rules.md .usage-rules/spark-2.2.24/

# Clean up
rm -rf .usage-rules/.tmp/spark-2.2.24
```

---

## Finding Code Examples

**Query**: "Show me good and bad examples for Ash queries"

**Expected behavior**:
1. Find usage rules file
2. Search for `# GOOD` and `# BAD` markers
3. Extract code blocks with annotations

**Grep patterns**:
```
# Find all good/bad markers
pattern="# GOOD|# BAD|# PREFERRED|# AVOID"
path="deps/ash/usage-rules.md"
output_mode="content"
-A=10
```

**Output shows comparison**:
```elixir
# GOOD - Use query option
posts = Blog.list_posts!(query: [filter: [status: :published]])

# BAD - Build query manually
query = Post |> Ash.Query.filter(status: :published)
posts = Ash.read!(query)
```

---

## Using Cached Rules (Offline)

**Query**: "Ash relationship conventions"

**Expected behavior** (when cached):
1. Check `.usage-rules/ash-3.5.20/usage-rules.md` (found!)
2. No network request needed
3. Search for "## Relationships" section
4. Present cached rules

**Output note**:
```
**Cache Location**: .usage-rules/ash-3.5.20/usage-rules.md
**Note**: Rules are cached locally for offline access.
```

---

## Multiple Section Extraction

**Query**: "What should I know about Ash code structure and actions?"

**Multiple contexts**: "structure", "actions"

**Expected behavior**:
1. Extract `## Code Structure & Organization`
2. Extract `## Actions`
3. Present both sections clearly labeled

**Output structure**:
```
Found usage rules for ash:

**Relevant Best Practices** (Code Structure & Organization):
[section content]

---

**Relevant Best Practices** (Actions):
[section content]
```
