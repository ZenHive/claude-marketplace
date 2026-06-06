---
name: workflow-generator
description: Generate customized workflow commands (research, plan, implement, qa) for an Elixir project. Use when setting up a new project's development workflow or creating project-specific slash commands. Asks questions about project structure and preferences, then outputs tailored commands.
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, AskUserQuestion, TodoWrite
---

# Workflow Generator Skill

Generate a complete set of project-specific workflow commands by asking questions about the project and creating customized `/research`, `/plan`, `/implement`, and `/qa` commands.

## Scope

WHAT THIS SKILL DOES:
  ✓ Generating project-specific workflow slash commands
  ✓ Customizing research/plan/implement/qa commands for a project
  ✓ Interactive questioning to tailor commands to project needs

WHAT THIS SKILL DOES NOT DO:
  ✗ Executing workflows (→ use the generated commands directly)
  ✗ General slash command creation (→ plugin-dev:command-development)
  ✗ Plugin scaffolding (→ plugin-dev:create-plugin)

## Purpose

Create a standardized workflow system adapted to any project's:
- Tech stack and language
- Build/test commands
- Documentation structure
- Quality gates and validation criteria
- Planning methodology

## Template System

### Template Path Resolution

Templates are stored in `plugins/elixir-meta/skills/workflow-generator/templates/`. When this skill uses the Read tool:
- **During marketplace development**: Paths are relative to repository root
- **When plugin is installed**: Claude Code resolves paths relative to plugin installation location

### Template Syntax

Templates use two types of variable substitution:

**1. Simple Variable Substitution** - Replace `{{VARIABLE}}` with actual values:
```
{{PROJECT_TYPE}} -> "Phoenix Application"
{{DOCS_LOCATION}} -> ".thoughts"
{{TEST_COMMAND}} -> "mix test"
```

**2. Handlebars Conditionals** (preserved in generated commands):
```
{{#if PLANNING_STYLE equals "Detailed phases"}}
  Phase-based content
{{/if}}
```

Handlebars conditionals are preserved in generated commands (not substituted). Claude evaluates them when the command is executed.

## Execution Flow

When invoked, this skill will:

1. **Discover Project Context** - Detect project type, existing structure, build tools
2. **Ask Customization Questions** - 6 questions about project configuration
3. **Generate Workflow Commands** - Create 6 slash commands from templates
4. **Create Supporting Documentation** - WORKFLOWS.md and directory structure
5. **Provide Usage Instructions** - Summary with quick start guide

---

## Step 1: Discover Project Context

### 1.1 Detect Project Type

Analyze the current directory for project markers (mix.exs, package.json, Cargo.toml, etc.).

### 1.2 Check Existing Structure

Check for existing `.claude/commands/*.md` and `.claude/agents/*.md`.

### 1.3 Detect Build Tools

Look for Makefile, package.json scripts, mix.exs test tasks, etc.

---

## Step 2: Ask Customization Questions

Use TodoWrite to track progress through all 10 steps.

### Question 1: Elixir Project Type

**Options**: Phoenix Application, Library/Package, CLI/Escript, Umbrella Project

### Question 2: Test Strategy

**Options**: mix test, make test, Custom script

### Question 3: Documentation Location

**Options**: .thoughts/, docs/, .claude/thoughts/, thoughts/

### Question 4: Quality Tools (multi-select)

**Options**: Credo, Dialyzer, Sobelow, ExDoc, mix_audit, Format check

### Question 5: Planning Style

**Options**: Detailed phases, Task checklist, Milestone-based

### Question 6: WORKFLOWS.md Location

**Options**: .claude/WORKFLOWS.md, WORKFLOWS.md, docs/WORKFLOWS.md, README-WORKFLOWS.md

---

## Steps 3-8: Generate Commands

For each command, read the corresponding template from `plugins/elixir-meta/skills/workflow-generator/templates/`, perform variable substitution based on question answers, and write the customized command to `.claude/commands/`.

| Step | Command | Template |
|------|---------|----------|
| 3 | /elixir-research | research-template.md |
| 4 | /elixir-plan | plan-template.md |
| 5 | /elixir-implement | implement-template.md |
| 6 | /elixir-qa | qa-template.md |
| 7 | /elixir-oneshot | oneshot-template.md |
| 8 | /elixir-interview | interview-template.md |

See **`references/command-generation.md`** for detailed variable substitution instructions per command.

---

## Step 9: Create Documentation

### 9.1 Create Workflow README

Create WORKFLOWS.md at the location from Question 6. See **`references/workflows-template.md`** for the full template content.

### 9.2 Create Documentation Directory

```bash
mkdir -p {{DOCS_LOCATION}}/research
mkdir -p {{DOCS_LOCATION}}/plans
mkdir -p {{DOCS_LOCATION}}/interview
```

---

## Step 10: Present Usage Instructions

Present a comprehensive summary to the user. See **`references/usage-instructions.md`** for the full output template.

---

## Important Notes

### Generic Core Components

Generated commands maintain these universal patterns:
- TodoWrite for progress tracking
- Parallel agent spawning (finder, analyzer)
- YAML frontmatter with git metadata
- file:line reference format
- Documentation vs evaluation separation
- Success criteria framework (automated vs manual)

### Elixir-Specific Customizations

Commands are customized based on project type, test commands, documentation location, quality tools, and planning methodology.

### Extensibility

All generated commands are templates that users can edit directly, extend with additional validation, modify to match team conventions, or enhance with custom agent types.

### Agent Types Referenced

Generated commands use these standard agents:
- `finder`: Locate files and patterns
- `analyzer`: Deep technical analysis
- `general-purpose`: Flexible research tasks

### Error Handling

If generation fails at any step: report which step failed, show the error, offer to retry just that step, and provide manual instructions if needed.

### Validation

After generating all commands: check that all files were created, validate markdown structure, verify template variables were replaced, confirm documentation directory exists, and present final status.

## References

For detailed generation instructions and templates:

- **`references/command-generation.md`** - Steps 3-8: Detailed variable substitution for each command template
- **`references/workflows-template.md`** - WORKFLOWS.md template content for Step 9
- **`references/usage-instructions.md`** - Usage instructions and quick start guide for Step 10
