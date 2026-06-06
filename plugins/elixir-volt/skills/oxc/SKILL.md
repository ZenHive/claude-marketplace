---
name: oxc
description: "OXC Elixir bindings for parsing, transforming, bundling, and minifying JavaScript/TypeScript via Rust NIFs. ALWAYS use this skill when working with JS/TS source analysis, ESTree AST navigation, class hierarchy extraction, code generation from AST, TypeScript-to-JavaScript transformation, or any static analysis of JavaScript/TypeScript files. Covers parse, transform, bundle, minify, imports, walk/postwalk/collect traversal, patch_string, and the recursive value-extraction pattern. Use this even if you think you know OXC — it contains runtime-verified corrections to common misconceptions."
allowed-tools: Read, Bash, Grep, Glob
---

<!-- Auto-synced from ~/.claude/includes/oxc.md — do not edit manually -->

## OXC: Parse, Transform, and Bundle JS/TS on the BEAM

Rust NIF bindings for the [OXC](https://oxc.rs) toolchain. Parses, transforms, minifies, and bundles JS/TS on the BEAM — no Node.js.

**Min version: `{:oxc, "~> 0.15"}`.** The atom-keyed AST contract: `:type`/`:kind` values are snake_case atoms (`:import_declaration`, not `"ImportDeclaration"`); error tuples are `{:error, [%{message: String.t()}]}`; bang functions raise `OXC.Error`. Source-taking APIs accept `iodata()` across parse / transform / minify / collect_imports / lint / format / patch_string / virtual bundle inputs. Surface includes `OXC.codegen/1,!`, `OXC.bind/2`/`splice/3` (placeholder templating), `OXC.transform_many/2` (parallel via rayon), `OXC.Format` (oxfmt as a separate Rust NIF — Prettier-compatible, ~30× faster, ships `:sort_imports` and `:sort_tailwindcss` plugins), `OXC.Lint` (oxlint's 650+ rules, custom Elixir rules via `OXC.Lint.Rule`, and `tsgolint`-backed type-aware mode), and the full Rolldown bundle option surface (`:external`, `:exports`, `:preserve_entry_signatures`, `:conditions`, `:main_fields`, `:modules`, `:module_types`, `:cwd`). `OXC.bundle/2` accepts either a filesystem entry path (string) or a virtual `[{filename, source}]` project. The low-level `OXC.Native` NIF surface is public (rarely needed — use the `OXC` wrapper).

**Does NOT cover:** runtime JS execution (→ QuickBEAM), installing npm packages (→ `mix npm.install`), frontend build + HMR (→ Volt).

### Parsing

```elixir
# Parse JS or TS to ESTree AST (maps with atom keys AND atom :type/:kind values)
# File extension determines language: .ts, .tsx, .js, .jsx
{:ok, ast} = OXC.parse(source, "file.ts")
ast.type  # => :program

{:error, [%{message: msg} | _]} = OXC.parse(bad_source, "file.ts")

# Raising variant — raises OXC.Error
ast = OXC.parse!(source, "file.ts")

# Fast syntax validation (no AST allocation)
true = OXC.valid?(source, "file.ts")
```

AST uses **atom keys** AND **atom values** for `:type`/`:kind` (`:import_declaration`, `:variable_declaration`, …).

### Transform (TS → JS)

```elixir
# Strip type annotations AND interfaces, transform JSX
{:ok, js} = OXC.transform(source, "file.ts")
# "const x: number = 1; interface Foo { bar: string }" → "const x = 1;\n"

# Options
{:ok, js} = OXC.transform(source, "file.tsx",
  jsx: :automatic,           # :automatic | :classic
  jsx_factory: "h",          # custom JSX factory (classic mode)
  jsx_fragment: "Fragment",  # custom fragment
  import_source: "preact",   # JSX import source (automatic mode)
  target: "es2020",          # target ES version
  sourcemap: true            # generate source map
)
```

### Codegen

`OXC.codegen/1` emits JavaScript source from an ESTree AST. Handles precedence, indentation, semicolon insertion. **Roundtripping TS through codegen emits JS** — TypeScript type annotations, interfaces, and `as`/satisfies expressions are stripped.

```elixir
{:ok, ast} = OXC.parse("const x: number = 40 + 2;", "f.ts")
{:ok, "const x = 40 + 2;\n"} = OXC.codegen(ast)   # TS type annotation gone

js = OXC.codegen!(ast)                             # bang variant
```

Works on hand-built ASTs too — manually construct a `:program` with `.body` and codegen will emit it, as long as each node has its required ESTree fields.

### Bind & Splice — Placeholder Templating

AST-level string templating. `$placeholder` identifiers in the source are replaced with Elixir values, structurally (not by string substitution), so you can't build syntactically invalid output.

```elixir
{:ok, ast} = OXC.parse("const x = $v;", "t.js")

# Bindings is a keyword list, NOT a map
OXC.bind(ast, v: {:literal, 42})    |> OXC.codegen!()  # => "const x = 42;\n"
OXC.bind(ast, v: "userId")          |> OXC.codegen!()  # => "const x = userId;\n"   (identifier rename)
OXC.bind(ast, v: {:expr, "40 + 2"}) |> OXC.codegen!()  # => "const x = 40 + 2;\n"   (parsed sub-AST)
OXC.bind(ast, v: other_ast_node)    |> OXC.codegen!()  # raw AST node (must have :type)
```

Binding value forms:
- **string** — replaced as identifier name (rename)
- **`{:literal, v}`** — replaced with a literal node. Maps/lists recursively become JS object/array literals.
- **`{:expr, "code"}`** — parsed as a JS expression, inserted as a sub-AST
- **raw AST node** (map with `:type`) — spliced directly

`splice/3` replaces `$name` *statements*, shorthand object *properties*, or array *elements* with one or more nodes (strings auto-parse as JS):

```elixir
{:ok, ast} = OXC.parse("function f() { $body }", "t.js")
OXC.splice(ast, :body, ["const x = 1;", "return x;"]) |> OXC.codegen!()
# => "function f() {\n\tconst x = 1;\n\treturn x;\n}\n"
```

`bind` = substitute at expression positions. `splice` = substitute at statement/list positions.

### Minify

```elixir
{:ok, minified} = OXC.minify(source, "file.js")                     # DCE, constant folding, whitespace
{:ok, minified} = OXC.minify(source, "file.js", mangle: false)      # keep original names
```

### Format

`OXC.Format` wraps oxfmt (the OXC formatter, separate Rust NIF `oxc_fmt_nif`). Prettier-compatible output, ~30× faster.

```elixir
{:ok, "const x = 1 + 2;\nfunction foo(a, b) {\n  return a + b;\n}\n"} =
  OXC.Format.run("const   x=1 +2 ; function  foo(   a,b) {return a+b ;}", "t.js")

formatted = OXC.Format.run!(source, "t.ts")   # bang variant — raises OXC.Error
```

**Prettier-ish options:** `:print_width` (default 80), `:tab_width` (2), `:use_tabs` (false), `:semi` (true), `:single_quote` (false), `:jsx_single_quote` (false), `:trailing_comma` (`:all`), `:bracket_spacing` (true), `:bracket_same_line` (false), `:arrow_parens` (`:always`), `:end_of_line` (`:lf`), `:quote_props` (`:as_needed`), `:single_attribute_per_line` (false), `:object_wrap` (`:preserve` | `:collapse`), `:experimental_operator_position` (`:start` | `:end`), `:experimental_ternaries` (false), `:embedded_language_formatting` (`:auto` | `:off`).

**`:sort_imports`** — `true` for defaults, or a map of sub-options. Groups, orders, and dedupes import declarations:

```elixir
OXC.Format.run!(source, "t.ts",
  sort_imports: %{
    ignore_case: true,        # case-insensitive sorting (default)
    sort_side_effects: false, # leave `import "x"` alone (default)
    order: :asc,              # :asc | :desc
    newlines_between: true,   # blank lines between groups
    partition_by_newline: false,
    partition_by_comment: false,
    internal_pattern: ["~/", "@/"]  # prefixes treated as internal imports
  })
```

**`:sort_tailwindcss`** — `true` for defaults, or a map. Sorts class names to Tailwind's recommended order:

```elixir
OXC.Format.run!(source, "App.tsx",
  sort_tailwindcss: %{
    config: "tailwind.config.js",  # v3 config path
    stylesheet: "app.css",         # v4 stylesheet path
    functions: ["clsx", "cn"],     # function names containing classes
    attributes: ["className"],     # extra attrs to sort
    preserve_whitespace: false,
    preserve_duplicates: false
  })
```

`oxc_fmt_nif` ships precompiled for aarch64/x86_64 glibc + darwin — **no musl builds**, so on Alpine you'll compile from source (Rust toolchain required).

### Transform Many

Parallel transform via a Rust (rayon) thread pool — significantly faster than `Task.async_stream` for many files since work is distributed across OS threads without BEAM scheduling overhead.

```elixir
# Footgun: {source, filename} — OPPOSITE order from OXC.bundle/2 ({filename, source})
results = OXC.transform_many([
  {"const a: number = 1;", "a.ts"},
  {"const b: string = 'x';", "b.ts"}
])
# => [ok: "const a = 1;\n", ok: "const b = \"x\";\n"]

# Shared opts apply to all files
OXC.transform_many(inputs, jsx: :automatic, target: "es2020")
```

Each result is `{:ok, code}`, `{:ok, %{code:, sourcemap:}}` (with `sourcemap: true`), or `{:error, errors}`. Preserves input order.

### Bundle

```elixir
# Virtual project — list of {filename, source} tuples; :entry REQUIRED
{:ok, js} = OXC.bundle(
  [
    {"event.ts", event_source},
    {"target.ts", target_source}  # can import from './event'
  ],
  entry: "target.ts"
)

# Filesystem entry — first arg is a real path (string), resolves packages
# from :cwd (or the file's directory). :entry is NOT used in this mode.
{:ok, js} = OXC.bundle("priv/js/app.ts", cwd: File.cwd!())

# Full options
{:ok, js} = OXC.bundle(input,
  entry: "main.ts",          # virtual-project entry filename (omit for filesystem path input)
  cwd: File.cwd!(),          # project dir — resolves packages for filesystem entries
  format: :iife,             # :iife (default) | :esm | :cjs
  minify: true,
  treeshake: true,           # remove unused exports
  preamble: "const { ref } = Vue;",  # code injected at top of IIFE body
  external: ["react", "scheduler"],  # preserve as `import` in output (bare ESM
                                     # specifiers auto-detect; this is for cases auto-detect misses)
  exports: :auto,            # :auto | :default | :named | :none
  preserve_entry_signatures: :strict,  # :strict | :allow_extension | :exports_only | false
  conditions: ["browser", "import", "default"],  # package export conditions for the resolver
  main_fields: ["browser", "module", "main"],    # package.json fields for resolution
  modules: ["node_modules"],                     # module directories
  module_types: %{".css" => :empty, ".ttf" => :dataurl},  # per-extension loader
  banner: "/* v1.0 */",
  footer: "/* end */",
  define: %{"process.env.NODE_ENV" => ~s("production")},
  sourcemap: true,           # returns %{code: ..., sourcemap: ...} instead of string
  drop_console: true,
  jsx: :automatic,
  target: "es2020"
)
```

**`:module_types` loaders:** `:js`, `:jsx`, `:ts`, `:tsx`, `:json`, `:text`, `:base64`, `:dataurl`, `:binary`, `:empty`, `:css`, `:asset`. Use `:empty` to stub out CSS/font imports that the bundler doesn't need to process.

**Filesystem vs virtual:** virtual projects (`[{filename, source}]`) are best for tests, generated sources, and the esbuild-style "load this exact string" use case. Filesystem entries (`"path/to/entry.ts"`) resolve packages through `node_modules` via `:cwd` — closes the gap the README pattern in this repo previously fills with `npx esbuild`.

### Imports

```elixir
# Fast path — source strings only (type-only imports excluded)
{:ok, ["vue", "axios"]} = OXC.imports(source, "file.ts")

# collect_imports/2 — with type info + byte offsets
{:ok, imports} = OXC.collect_imports(source, "file.ts")
# => [%{specifier: "vue", type: :static, kind: :import, start: 19, end: 24}, ...]
# Fields: :specifier, :type (:static | :dynamic), :kind (:import | :export | :export_all),
#          :start, :end (byte offsets, including quotes)
```

### Rewrite Specifiers

```elixir
# Callback MUST return {:rewrite, new} | :keep — bare string raises CaseClauseError.
{:ok, rewritten} = OXC.rewrite_specifiers(source, "file.ts", fn
  "vue" -> {:rewrite, "/@vendor/vue.js"}
  _ -> :keep
end)
```

Cleaner than parse → collect → patch for simple rewrites.

### Patch String

```elixir
patched = OXC.patch_string(source, [
  %{start: 10, end: 20, change: "replacement"},
  %{start: 30, end: 35, change: ""}            # deletion
])
```

Use `.start`/`.end` from AST nodes — byte offsets. Patches can be in any order (sorted internally). For specifier rewrites, prefer `rewrite_specifiers/3`.

### AST Navigation

Pattern-match on atoms:

```elixir
{:ok, ast} = OXC.parse(source, "file.ts")

# ast.body is a list of top-level statements
# `export default class` → top is :export_default_declaration with .declaration
export = Enum.find(ast.body, &(&1.type == :export_default_declaration))
class = export.declaration
# Plain class (no export default) → :class_declaration directly:
class = Enum.find(ast.body, &(&1.type == :class_declaration))

class.id.name           # nil if anonymous
class.superClass.name   # nil if no extends
class.body.body         # class members

methods = Enum.filter(class.body.body, &(&1.type == :method_definition))
# method.key.name, method.value.async, .params, .body.body
# FunctionExpression (method.value) keys: :async, :id, :params, :body, :generator,
# :declare, :typeParameters, :expression, :returnType
```

#### Key ESTree Node Types

Atom names follow PascalCase → snake_case (`"FooBar"` in the ESTree spec is `:foo_bar` here).

| Atom | Key Fields |
|------|------------|
| `:program` | `.body` |
| `:export_default_declaration` | `.declaration` |
| `:export_named_declaration` | `.declaration`, `.specifiers`, `.source` |
| `:class_declaration` | `.id.name`, `.superClass`, `.body.body` |
| `:method_definition` | `.key.name`, `.value` (function_expression) |
| `:function_expression` | `.async`, `.params`, `.body.body`, `.returnType` |
| `:function_declaration` | `.id.name`, `.params`, `.body.body` |
| `:arrow_function_expression` | `.async`, `.params`, `.body` |
| `:object_expression` | `.properties` |
| `:array_expression` | `.elements` |
| `:literal` | `.value` (string/number/boolean/null) |
| `:identifier` | `.name` |
| `:call_expression` | `.callee`, `.arguments` |
| `:unary_expression` | `.operator`, `.argument` |
| `:member_expression` | `.object`, `.property` |
| `:return_statement` | `.argument` |
| `:import_declaration` | `.source.value`, `.specifiers` |
| `:variable_declaration` | `.declarations`, `.kind` (`:var`/`:let`/`:const`) |

Unknown atom for a type? Run `OXC.parse(source, "file.ts")` and inspect `ast.body |> hd() |> Map.get(:type)` — runtime is authoritative.

#### Type Annotations (TypeScript)

Nested under `.typeAnnotation.typeAnnotation`:

```elixir
# function(x: string)
type_name = get_in(param, [:typeAnnotation, :typeAnnotation, :typeName, :name])
```

### Traversal

```elixir
# walk — side-effects only, returns :ok
:ok = OXC.walk(ast, fn
  %{type: :call_expression, callee: c} -> IO.inspect(c)
  _ -> :ok
end)

# postwalk — depth-first post-order (children before parents)
transformed = OXC.postwalk(ast, fn
  %{type: :identifier, name: "old"} = node -> %{node | name: "new"}
  node -> node
end)

# postwalk with accumulator
{_ast, patches} = OXC.postwalk(ast, [], fn
  %{type: :import_declaration, source: %{value: "vue"} = src} = node, acc ->
    {node, [%{start: src.start, end: src.end, change: "'/@vendor/vue.js'"} | acc]}
  node, acc -> {node, acc}
end)
# For this specific rewrite, prefer OXC.rewrite_specifiers/3.

# collect — {:keep, value} collects, :skip ignores
method_names = OXC.collect(ast, fn
  %{type: :method_definition, key: %{name: name}} -> {:keep, name}
  _ -> :skip
end)
```

### Lint

`OXC.Lint` wraps oxlint (650+ rules, Rust-speed) and lets you add Elixir-side custom rules that walk the same atom-keyed AST `OXC.parse/2` returns.

```elixir
# Built-ins only — severity is :allow | :warn | :deny
{:ok, diags} = OXC.Lint.run(source, "app.tsx",
  plugins: [:react, :typescript],
  rules: %{"no-debugger" => :deny, "no-console" => :warn}
)

# Bang variant — raises OXC.Error on parse failure, returns diags list directly
diags = OXC.Lint.run!(source, "app.tsx", rules: %{"no-debugger" => :deny})

# Diagnostic shape (rule is namespaced — "eslint(no-debugger)"):
# %{rule: "eslint(no-debugger)", severity: :deny, message: "...",
#   span: {start, end}, labels: [{s, e}], help: String.t() | nil}

# Custom Elixir rules — module implements OXC.Lint.Rule (meta/0 + run/2)
{:ok, diags} = OXC.Lint.run(source, "app.ts",
  custom_rules: [{MyApp.NoConsoleLog, :warn}]
)
```

Plugin atoms: `:react`, `:typescript`, `:unicorn`, `:import`, `:jsdoc`, `:jest`, `:vitest`, `:jsx_a11y`, `:nextjs`, `:react_perf`, `:promise`, `:node`, `:vue`, `:oxc`. Default is oxlint's correctness set (no plugin flag needed for rules like `no-debugger`).

`:fix` option computes suggested fixes; `:settings` passes arbitrary context to custom rules.

**Type-aware linting (`type_aware: true`)** — runs through `tsgolint` headless mode for rules that need TypeScript type information. Accepts a file list plus the project's tsconfig and emits normalized diagnostics with fixes and suggestions in the same shape as parse-only output.

```elixir
{:ok, diags} = OXC.Lint.run(file_list, "tsconfig.json",
  type_aware: true,
  type_check: true,           # run tsgolint's type-check phase
  source_overrides: %{"src/x.ts" => override_source},
  rules: %{"no-floating-promises" => :deny}
)
```

Nonzero `tsgolint` exits — including panics from unsupported input files — surface as `{:error, ...}` with stderr captured. Empty or malformed `tsgolint` output is reported as an error rather than silently treated as a clean run.

Category filters (e.g. `rules: %{"correctness" => :deny}`) honor the configured severity instead of always reporting `:warn`.

### Recipes

**Recursive AST value extraction** (object_expression/array_expression/literal → Elixir):

```elixir
extract = fn
  %{type: :literal, value: v}, _r -> v
  %{type: :object_expression, properties: props}, r ->
    Map.new(props, fn p ->
      key = Map.get(p.key, :name) || to_string(Map.get(p.key, :value, "?"))
      {key, r.(p.value, r)}
    end)
  %{type: :array_expression, elements: els}, r -> Enum.map(els, &r.(&1, r))
  %{type: :identifier, name: "undefined"}, _r -> :undefined
  %{type: :identifier, name: n}, _r -> {:ref, n}
  %{type: :unary_expression, operator: "-", argument: %{value: v}}, _r -> -v
  %{type: :call_expression} = node, _r ->
    callee = get_in(node, [:callee, :property, :name]) || "unknown"
    {:call, callee, Enum.map(node.arguments, &Map.get(&1, :value, "?"))}
  %{type: t}, _r -> {:ast, t}
  nil, _r -> nil
end

value = extract.(config_node, extract)   # Y-combinator: anon fns can't self-recurse
```

**Find method in class:**
```elixir
export = Enum.find(ast.body, &(&1.type == :export_default_declaration))
methods = Enum.filter(export.declaration.body.body, &(&1.type == :method_definition))
target = Enum.find(methods, &(&1.key.name == "describe"))
```

**Find property in ObjectExpression** (keys can be identifier `.name` or literal `.value`):
```elixir
Enum.find(object_node.properties, fn p ->
  (Map.get(p.key, :name) || Map.get(p.key, :value)) == "id"
end)
```

### Error Handling

```elixir
case OXC.parse(source, "file.ts") do
  {:ok, ast} -> process(ast)
  {:error, errors} ->
    for %{message: msg} <- errors, do: Logger.warning("OXC: #{msg}")
end

try do
  OXC.parse!(source, "file.ts")
rescue
  e in OXC.Error -> Logger.error(Exception.message(e))
end
```

### Common Pitfalls

| Problem | Cause | Fix |
|---|---|---|
| `KeyError` on node | Optional fields missing | Match `.type` first, use `Map.get/3` for optionals |
| `.superClass` is nil | No `extends` | Check `is_nil(class.superClass)` |
| Property key access fails | Keys can be identifier or literal | `p.key.name \|\| p.key.value` |
| Wrong file extension | Extension picks parser | `.ts`, `.tsx`, `.js`, `.jsx` |
| Y-combinator forgotten | Anon fns can't self-recurse | Pass `fn` as arg |
| `bundle/2` empty | Missing `:entry` (virtual project) | `:entry` is required when input is `[{filename, source}]`; omit it when input is a filesystem path string |
| `transform_many`/`bundle` arg order reversed | `transform_many` is `{source, filename}`; `bundle` is `{filename, source}` | Remember: bundle files are virtual project *files* (filename first); transform inputs are *sources* being labeled |
| `OXC.bind` `FunctionClauseError` | Passed a map `%{v: ...}` | Bindings must be a keyword list `[v: ...]` |
| TS types vanish after `codegen` roundtrip | `codegen` emits JS, not TS | Expected — codegen is not an identity function on TS |

### DO NOT

1. Don't use string keys — always atom-keyed maps (`node.type`, not `node["type"]`).
2. Don't parse just to validate — use `OXC.valid?/2`.
3. Don't parse just for imports — use `OXC.imports/2` or `OXC.collect_imports/2`.
4. Don't hand-roll import rewrites — `OXC.rewrite_specifiers/3` is a single pass.
5. Don't use OXC to run JS — static analysis only. Use QuickBEAM for runtime.

### Performance

| Operation | ~Time |
|---|---|
| Parse 14.5k-line TS | 43ms |
| Transform TS→JS | 10ms |
| Minify | 5ms |
| `valid?` | 20ms |
| `imports` | 15ms |
| `collect_imports` | 20ms |

Rust NIF, CPU-bound. For batch transform, prefer `OXC.transform_many/2` (rayon thread pool) over `Task.async_stream` — distributes across OS threads without BEAM scheduling overhead.
