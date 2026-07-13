---
name: nexus-template
description: Nexus Phoenix admin dashboard template. Use when building admin interfaces with Nexus, adding Iconify icons, creating layout pipelines, implementing partials, or adding Alpine.js interactivity. Covers Nexus architecture, routing, component organization, and theme configuration.
allowed-tools: Read
---

<!-- Auto-synced from ~/.claude/includes/nexus-template.md — do not edit manually -->

## Nexus Phoenix Admin Template

Nexus is an admin dashboard template built on Phoenix 1.8 with daisyUI 5, Tailwind CSS v4, and Iconify icons.

### Architecture

```
lib/nexus_phoenix_web/
├── components/
│   ├── core_components.ex    # Phoenix core UI components
│   ├── layouts.ex            # Layout components (embed_templates)
│   ├── partials.ex           # Reusable partial modules
│   └── layouts/              # Layout templates (root, admin, auth, etc.)
├── controllers/
│   ├── page_controller.ex    # Dynamic page dispatching
│   └── page_html/            # HEEx page templates
└── router.ex                 # Routes with layout pipelines

assets/styles/
├── app.css                   # Entry point with imports
├── daisyui.css               # daisyUI plugin and theme config
├── tailwind.css              # Tailwind base imports
├── core/                     # Custom animations and components
└── plugins/                  # Third-party plugin overrides
```

### Routing & Layouts

Router uses layout pipelines:
- `layout_empty` → `empty.html.heex` (landing)
- `layout_auth` → `auth.html.heex`
- `layout_components` → `components.html.heex` (showcase)
- `layout_admin` → `admin.html.heex` (dashboard)

### Iconify Icons

`iconify_ex` with three sets: `lucide`, `heroicons-solid`, `heroicons-outline`.

```heex
<.iconify icon="lucide:sun" class="size-4" />
<.iconify icon="heroicons-solid:check" class="size-5 text-success" />
```

```bash
mix icons.install   # download sets
mix icons.patch     # patch iconify for Phoenix
```

### Partials

Separate modules in `partials.ex`, each `embed_templates("partials/path/*")`:
- `NexusPhoenixWeb.Partials.Layouts.Sidebar` / `Topbar`
- `NexusPhoenixWeb.Partials.Interactions.Carousel`

### Functional Components (preferred)

```elixir
attr :title, :string, required: true
attr :class, :string, default: nil
slot :inner_block, required: true

def my_card(assigns) do
  ~H"""
  <div class={["card bg-base-100 shadow-xl", @class]}>
    <div class="card-body">
      <h2 class="card-title">{@title}</h2>
      {render_slot(@inner_block)}
    </div>
  </div>
  """
end
```

### Interactivity

**Alpine.js first** for client-side:
```heex
<div x-data="{ open: false }">
  <button @click="open = !open">Toggle</button>
  <div x-show="open">Content</div>
</div>
```

Default to Controller/Template for static designs; LiveView only for real-time features.

### Commands

```bash
mix setup          # deps, DB, migrations, assets, icons
mix phx.server     # localhost:4000
mix precommit      # compile (warn-as-error), unlock unused, format, test
```

### Debugging

1. Tailwind/daisyUI class typos
2. Assets watcher running? (`mix phx.server`)
3. No string interpolation in Tailwind classes — needs full class names in source
4. Icon exists in installed sets?
