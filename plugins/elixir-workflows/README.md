# elixir-workflows

Elixir development workflow plugin for generating project-specific workflow commands.

## Overview

The elixir-meta plugin provides a **workflow-generator skill** that generates a complete, customized workflow system for Elixir projects by creating:
- `/elixir-interview` - Interactive context gathering through dynamic questioning
- `/elixir-research` - Research and document codebase
- `/elixir-plan` - Create detailed implementation plans
- `/elixir-implement` - Execute plans with automated verification
- `/elixir-qa` - Validate implementation against quality standards
- `/elixir-oneshot` - Complete workflow in one command

## Purpose

Instead of creating workflow commands manually for each Elixir project, the elixir-meta plugin:
1. **Asks questions** about your project (type, test strategy, quality tools)
2. **Generates customized commands** adapted to your Elixir workflow
3. **Creates documentation** explaining the workflow system
4. **Provides ready-to-use commands** that follow Elixir best practices

## Installation

```bash
/plugin marketplace add ZenHive/claude-marketplace-elixir
/plugin install elixir-workflows@deltahedge
```

## Usage

### Generate Workflow Commands

```bash
/workflow-generator
```

This will:
1. Detect your project type and tech stack
2. Ask customization questions via interactive prompts
3. Generate six workflow commands:
   - `/elixir-interview` - Interactive context gathering before research/planning
   - `/elixir-research` - Research and document codebase
   - `/elixir-plan` - Create implementation plans with success criteria
   - `/elixir-implement` - Execute plans with automated verification
   - `/elixir-qa` - Validate implementation against quality gates
   - `/elixir-oneshot` - Complete workflow automation
4. Create supporting documentation
5. Set up documentation directories

### What Gets Generated

```
.claude/
├── commands/
│   ├── elixir-interview.md  # Context gathering before workflows
│   ├── elixir-research.md   # Customized for your file patterns
│   ├── elixir-plan.md       # Uses your build/test commands
│   ├── elixir-implement.md  # Includes your verification steps
│   ├── elixir-qa.md         # Enforces your quality gates
│   └── elixir-oneshot.md    # Complete workflow in one command

.claude/WORKFLOWS.md         # Complete workflow documentation
                             # (or your chosen location during generation)
```

Plus documentation directories at your chosen location (e.g., `.thoughts/`, `docs/`), including `interview/` for context documents.

## Features

### Skill: workflow-generator

**Purpose**: Generate complete workflow system for Elixir projects

**Invocation**:
- Via command: `/workflow-generator`
- Directly: `Skill(command="workflow-generator")`

**Customization Questions**:
1. **Project Type**: Phoenix Application, Library/Package, CLI/Escript, or Umbrella Project
2. **Test Strategy**: mix test, make test, or custom script
3. **Documentation Location**: Where to save research and plans
4. **Quality Tools**: Credo, Dialyzer, Sobelow, ExDoc, mix_audit, Format check
5. **Planning Style**: Detailed phases, task checklist, or milestone-based
6. **WORKFLOWS.md Location**: Where to save workflow documentation (.claude/, project root, docs/, etc.)

**Generated Commands Are**:
- **Elixir-focused**: Work with Mix, ExUnit, and Elixir tooling
- **Customized**: Adapted to your specific test commands and quality tools
- **Editable**: Full markdown files you can modify
- **Best-practice**: Follow Elixir and Phoenix conventions
- **Context-aware**: Generated `/elixir-interview` command provides dynamic question generation; `/elixir-research` and `/elixir-plan` can invoke it when needed

## Workflow System

The generated workflow follows a proven pattern with optional context gathering:

### 0. Interview (`/elixir-interview`) - Optional
Gather context before research or planning through dynamic questioning. Claude analyzes your query and asks relevant questions to focus subsequent workflow steps.

**Features**:
- Auto-detects workflow phase
- Generates contextual questions (not hardcoded)
- Creates interview documents for persistent context
- Can be invoked by `/elixir-research` and `/elixir-plan` when needed

### 1. Research (`/elixir-research`)
Document existing code without evaluation. Spawns parallel agents to:
- Find relevant files and patterns
- Analyze implementation details
- Extract architectural insights
- Save findings to research documents

### 2. Plan (`/elixir-plan`)
Create detailed implementation plans with:
- Phased execution structure
- Specific file changes with examples
- Success criteria (automated + manual)
- Design options and trade-offs

### 3. Implement (`/elixir-implement`)
Execute plans with built-in verification:
- Read plan and track progress
- Work phase by phase
- Run verification after each phase
- Update checkmarks
- Handle plan vs reality mismatches

### 4. QA (`/elixir-qa`)
Validate implementation quality:
- Run automated checks (tests, types, linting, security)
- Spawn validation agents
- Generate comprehensive report
- Provide actionable feedback

## Example Usage

### First-Time Setup

```bash
# Install elixir-workflows plugin
/plugin install elixir-workflows@deltahedge

# Generate workflow commands
/workflow-generator
```

Answer the questions, and you'll have a complete workflow system!

### Daily Workflow

```bash
# Research existing code
/elixir-research "How does authentication work?"

# Plan new feature
/elixir-plan "Add OAuth integration"

# Execute the plan
/elixir-implement "2025-01-23-oauth-integration"

# Validate implementation
/elixir-qa "oauth-integration"
```

## Customization

### Edit Generated Commands

All commands are standard markdown files. Customize them:

```bash
# Edit research command
vim .claude/commands/elixir-research.md

# Edit QA checks
vim .claude/commands/elixir-qa.md
```

### Regenerate Commands

To regenerate with different settings:

```bash
/workflow-generator
```

This will ask questions again and overwrite existing commands.

### Add Custom Agents

Create specialized agents for your project:

```bash
# Add custom agent
vim .claude/agents/database-analyzer.md
```

Then reference it in your customized commands.

## Why elixir-meta Plugin?

### Before elixir-meta Plugin

- Manually create workflow commands for each project
- Copy/paste from other projects and adapt
- Inconsistent patterns across projects
- Time-consuming setup

### After elixir-meta Plugin

- One command generates complete workflow system
- Automatically adapted to project specifics
- Consistent best practices
- 5-minute setup

## Technical Details

### Convention-Based Skill Discovery

The workflow-generator skill is discovered automatically by Claude Code:
- Location: `plugins/elixir-meta/skills/workflow-generator/SKILL.md`
- No JSON registration required
- Available as `workflow-generator@deltahedge`

### Generic Core + Project Specifics

**Universal Patterns** (same across all projects):
- TodoWrite progress tracking
- Parallel agent spawning
- YAML frontmatter metadata
- file:line references
- Documentarian mode (no evaluation)
- Success criteria framework

**Customized Per Elixir Project**:
- Elixir project type (Phoenix, Library, CLI, Umbrella)
- Test commands (mix test, make test, custom)
- Documentation location
- Quality tools (Credo, Dialyzer, Sobelow, ExDoc, mix_audit)
- Planning methodology

### Elixir Project Types Supported

The workflow generator adapts to different Elixir project types:
- **Phoenix Application**: Full-stack web apps, APIs, LiveView apps
- **Library/Package**: Reusable Hex packages
- **CLI/Escript**: Command-line applications
- **Umbrella Project**: Multi-app umbrella projects

### Elixir Quality Tools Supported

Integrates with common Elixir quality tools:
- **Credo**: Static code analysis (`mix credo --strict`)
- **Dialyzer**: Type checking (`mix dialyzer`)
- **Sobelow**: Security scanning for Phoenix (`mix sobelow`)
- **ExDoc**: Documentation validation (`mix docs`)
- **mix_audit**: Dependency security audit (`mix deps.audit`)
- **Format check**: Code formatting validation (`mix format --check-formatted`)

## Comparison with Other Plugins

| Plugin | Purpose | Automated | User-Invoked |
|--------|---------|-----------|--------------|
| elixir | Auto-format, compile check, all quality gates | Yes (hooks) | No |
| **elixir-workflows** | **Workflow generation** | **No** | **Yes (command/skill)** |

The elixir-workflows plugin is unique:
- **Not a hook**: Doesn't trigger automatically
- **Elixir-focused**: Designed for Elixir/Phoenix projects
- **Generates other commands**: Creates customized workflow system
- **One-time setup**: Run once (or whenever you want to regenerate)

## Architecture

```
plugins/elixir-workflows/
├── .claude-plugin/
│   └── plugin.json              # Plugin metadata
├── skills/
│   └── workflow-generator/
│       └── SKILL.md             # Workflow generator skill
└── README.md                    # This file

.claude/commands/
└── workflow-generator.md        # Command to invoke skill
```

## Design Decisions

### Workflow Evaluation (2025-12)

**Decision**: Keep the workflow commands and workflow-generator skill.

**Rationale**:
1. **Actual workflow** in this marketplace: Read `roadmap.md` → pick task → work in session → commit
2. **Workflow commands complement this** by providing structured approaches when needed:
   - `/elixir-research` for understanding unfamiliar code before making changes
   - `/elixir-plan` for complex multi-step features that benefit from planning
   - `/elixir-implement` for executing plans with verification
   - `/elixir-qa` for validating changes before committing
   - `/elixir-oneshot` for end-to-end feature development

3. **Not every task needs all commands**:
   - Simple tasks: Just read roadmap → implement → commit
   - Complex features: Use /elixir-plan → /elixir-implement → /elixir-qa
   - Exploratory work: Use /elixir-research to document findings

4. **workflow-generator is useful** for bootstrapping Elixir projects with consistent patterns

### D/B Scoring Integration

Plan and QA outputs now include D/B (Difficulty/Benefit) scoring to prioritize implementation steps and fixes. Format: `[D:X/B:Y → Priority:Z]`

## Limitations

- **Overwrites existing commands**: Regeneration replaces `/elixir-research`, `/elixir-plan`, `/elixir-implement`, `/elixir-qa`
- **Template-based**: Generated commands are starting points, may need customization
- **No hooks**: elixir-meta plugin doesn't use hooks (it generates commands, not automation)

## Contributing

To improve the workflow generator:

1. **Enhance questions**: Add more Elixir-specific customization options in `SKILL.md`
2. **Add quality tools**: Support additional Elixir/BEAM tools
3. **Improve templates**: Better default command structures for Elixir patterns
4. **Add examples**: Show more Elixir/Phoenix patterns in generated docs

## Support

- Report issues: https://github.com/bradleygolden/claude-marketplace-elixir/issues
- Source code: https://github.com/ZenHive/claude-marketplace-elixir/tree/main/plugins/elixir-workflows

## License

MIT
