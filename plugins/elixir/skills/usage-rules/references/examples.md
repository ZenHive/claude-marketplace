# Usage Rules Search Examples

## Example 1: Finding Ash querying best practices

**User asks**: "What are the best practices for querying data in Ash?"

**Search process**:
1. Extract package: `ash`
2. Identify context: "querying"
3. Check `deps/ash/usage-rules.md` (found)
4. Search for section: `## Querying Data`
5. Extract section with code examples
6. Present best practices

**Output**:
```
Found usage rules for ash:

**Location**: deps/ash/usage-rules.md
**Version**: 3.5.20

**Relevant Best Practices** (Querying Data):

## Querying Data

### Common Query Operations

Prefer using code interface functions with the `query` option for filtering, sorting, and limiting:

# PREFERRED - Use the query option
posts = MyApp.Blog.list_posts!(
  query: [
    filter: [status: :published],
    sort: [published_at: :desc],
    limit: 10
  ],
  load: [author: :profile]
)

# AVOID - Don't build queries manually outside domain
query = MyApp.Blog.Post
|> Ash.Query.filter(status: :published)
|> Ash.Query.sort(published_at: :desc)
posts = Ash.read!(query)

All query-related options go in the `query` parameter, not as separate arguments.

---

**Full Rules**: deps/ash/usage-rules.md

**Integration**: For Ecto.Query API documentation, use hex-docs-search skill.
```

---

## Example 2: Error handling conventions

**User asks**: "How should I handle errors in Phoenix LiveView?"

**Search process**:
1. Extract package: `phoenix_live_view`
2. Identify context: "error handling"
3. Check `deps/phoenix_live_view/usage-rules.md` (not found)
4. Check `.usage-rules/phoenix_live_view-*/usage-rules.md` (not found)
5. Attempt fetch (package doesn't include usage-rules.md)
6. Provide fallback suggestions

**Output**:
```
Package 'phoenix_live_view' does not provide usage-rules.md.

**Alternatives**:
- Use hex-docs-search skill for Phoenix.LiveView API documentation
- Check Phoenix LiveView guides: https://hexdocs.pm/phoenix_live_view/
- Search for "phoenix liveview error handling best practices"
```

---

## Example 3: Unknown package with progressive fetch

**User asks**: "What are the best practices for using Spark DSL?"

**Search process**:
1. Extract package: `spark`
2. Identify context: general (no specific context)
3. Check `deps/spark/usage-rules.md` (not found)
4. Check `.usage-rules/spark-*/usage-rules.md` (not found)
5. Check mix.exs: `{:spark, "~> 2.0"}`
6. Get latest 2.x from hex.pm
7. Fetch package: `mix hex.package fetch spark 2.2.24 --unpack --output .usage-rules/.tmp/spark-2.2.24`
8. Extract usage-rules.md (found!)
9. Copy to cache: `.usage-rules/spark-2.2.24/usage-rules.md`
10. Clean up temp
11. Read and present usage rules

---

## Example 4: Cached rules (offline access)

**User asks**: "Show me Ash relationship best practices again"

**Search process**:
1. Extract package: `ash`
2. Identify context: "relationship"
3. Check `deps/ash/usage-rules.md` (not found - not in project)
4. Check `.usage-rules/ash-*/usage-rules.md` (found version 3.5.20!)
5. **No fetch needed** - use cached rules
6. Search for "## Relationships" section
7. Extract and present

**Result**: Fast, offline search without network requests.

---

## Example 5: Context-aware extraction

**User asks**: "Common mistakes with Ash actions?"

**Search process**:
1. Extract package: `ash`
2. Identify context: "actions" + "mistakes"
3. Find usage rules (local or cached)
4. Search for "## Actions" section
5. Also search for keywords: "mistake", "avoid", "wrong", "bad"
6. Extract relevant parts from multiple sections
7. Present consolidated best practices

**Output**:
```
Found usage rules for ash:

**Relevant Best Practices** (Actions - Common Mistakes):

## Actions

**AVOID** - Don't create generic CRUD actions:
# BAD - Generic naming
create :create
update :update

**PREFER** - Create domain-specific actions:
# GOOD - Specific business operations
create :register_user
update :activate_account
update :suspend_for_violation

**AVOID** - Don't put business logic outside actions:
# BAD - Logic in controller

**PREFER** - Put business logic in action changes:
# GOOD - Logic in action

---

**Full Rules**: deps/ash/usage-rules.md
```
