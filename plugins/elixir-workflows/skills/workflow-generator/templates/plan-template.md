---
description: Create detailed implementation plan for Elixir feature or task
argument-hint: [brief-description]
allowed-tools: Read, Grep, Glob, Task, Bash, TodoWrite, Write, AskUserQuestion
---

# Plan

Generate a detailed, phased implementation plan for Elixir projects.

## Purpose

Create executable implementation plans with clear phases, success criteria, and verification steps for Elixir development.

## Steps to Execute:

### Step 1: Context Gathering

**Read referenced files completely:**
- If user references files, code, or tickets, read them FULLY first
- Use Read tool WITHOUT limit/offset parameters
- Gather complete context before any planning

**Spawn parallel research agents:**

Use Task tool to spawn agents that will inform your plan:

1. **codebase-locator** (subagent_type="general-purpose"):
   - Find relevant Elixir modules, contexts, schemas
   - Locate similar implementations for reference
   - Identify files that will need modification

2. **codebase-analyzer** (subagent_type="general-purpose"):
   - Analyze existing patterns and conventions
   - Understand current architecture and design
   - Trace how similar features are implemented

3. **Skill** (elixir:hex-docs-search):
   - Research relevant Hex packages if needed
   - Understand framework patterns (Phoenix, Ecto, etc.)
   - Find official documentation for libraries

**Wait for all agents** before proceeding.

**Present your informed understanding:**
- Summarize what you learned with file:line references
- Show the current implementation state
- Identify what needs to change

**Ask ONLY questions that code cannot answer:**
- Design decisions and trade-offs
- User preferences between valid approaches
- Clarifications on requirements

### Step 2: Research & Discovery

If user provides corrections or additional context:
- Verify through additional research
- Spawn new sub-agents if needed
- Update your understanding

**Present design options:**
- Show 2-3 valid approaches with pros/cons
- Include code examples for each approach
- Reference similar patterns in the codebase
- Explain trade-offs specific to Elixir/Phoenix

**Get user approval** on approach before writing detailed plan.

### Step 3: Plan Structure Proposal

**Propose phased implementation outline** based on {{PLANNING_STYLE}}:

{{#if PLANNING_STYLE equals "Detailed phases"}}
**Phased Structure:**
1. Phase 1: [Name] - [Brief description]
2. Phase 2: [Name] - [Brief description]
3. Phase 3: [Name] - [Brief description]

Each phase will include:
- Specific module/file changes
- Code examples showing changes
- Verification steps
{{/if}}

{{#if PLANNING_STYLE equals "Task checklist"}}
**Task Checklist Structure:**
- [ ] Task 1: [Description]
- [ ] Task 2: [Description]
- [ ] Task 3: [Description]

Each task will include:
- Files to modify
- Expected outcome
- How to verify
{{/if}}

{{#if PLANNING_STYLE equals "Milestone-based"}}
**Milestone Structure:**
- Milestone 1: [Deliverable]
- Milestone 2: [Deliverable]
- Milestone 3: [Deliverable]

Each milestone will include:
- Tasks required
- Acceptance criteria
- Verification approach
{{/if}}

**Get user approval** before writing detailed plan.

### Step 4: Write Detailed Plan

**Gather metadata:**
```bash
date +"%Y-%m-%d" && git log -1 --format="%H" && git branch --show-current && git config user.name
```

**Create plan file:**
- Location: `{{DOCS_LOCATION}}/plans/YYYY-MM-DD-description.md`
- Format: `{{DOCS_LOCATION}}/plans/YYYY-MM-DD-brief-kebab-case-description.md`
- Example: `{{DOCS_LOCATION}}/plans/2025-01-23-add-user-authentication.md`

**Plan Template:**

```markdown
---
date: [ISO timestamp]
author: [Git user name]
commit: [Current commit hash]
branch: [Current branch name]
repository: [Repository name]
title: "[Feature/Task Description]"
status: planned
tags: [plan, elixir, {{PROJECT_TYPE_TAGS}}]
---

# Plan: [Feature/Task Description]

**Date**: [Current date]
**Author**: [Git user name]
**Branch**: [Current branch]
**Project Type**: {{PROJECT_TYPE}}

## Overview

[2-3 sentences describing what this plan accomplishes and why]

## Current State

[Describe the current implementation with file:line references]

**Existing Modules:**
- `lib/my_app/context.ex` - [What it currently does]
- `lib/my_app_web/controllers/controller.ex` - [What it currently does]

**Current Behavior:**
[Describe how the system currently works in this area]

## Desired End State

[Describe the target implementation]

**New/Modified Modules:**
- `lib/my_app/new_context.ex` - [What it will do]
- `lib/my_app/schemas/new_schema.ex` - [What it will contain]

**Target Behavior:**
[Describe how the system should work after implementation]

{{#if PLANNING_STYLE equals "Detailed phases"}}
## Implementation Phases

**CRITICAL**: Each phase description should be a **prompt for Claude Code to implement**, not implementation code. Describe WHAT to accomplish; Claude Code will determine HOW by researching the codebase.

### Phase 1: [Phase Name]

**Goal**: [What this phase accomplishes]

**Prompt**: [Write a natural language description of what to implement. This will be executed by Claude Code.]

Example prompt: "Create an Ecto schema for users with email, hashed_password, and role fields. Add a context module with create_user/1, get_user/1, and authenticate/2 functions. Include changeset validations for email format and password minimum length. Write tests for all context functions."

**Success Criteria:**
- [ ] `mix compile --warnings-as-errors` succeeds
- [ ] {{TEST_COMMAND}} passes
- [ ] [Specific verifiable outcome]
{{/if}}

{{#if PLANNING_STYLE equals "Task checklist"}}
## Implementation Tasks

**CRITICAL**: Each task description should be a **prompt for Claude Code to implement**, not implementation details. Describe WHAT to accomplish; Claude Code will determine HOW.

- [ ] **Task 1**: [Task Name]
  Prompt: "Create an Ecto schema for [entity] with [fields]. Include validations for [requirements]. Write tests covering creation, validation errors, and edge cases."
  Success: Schema and tests exist and pass

- [ ] **Task 2**: [Task Name]
  Prompt: "Add context functions for [entity] CRUD operations. Follow existing context patterns in the codebase. Include tests for success and error cases."
  Success: Context tests pass

- [ ] **Task 3**: [Task Name]
  Prompt: "Create a LiveView for managing [entity]. Support list, create, edit, and delete operations. Follow the existing LiveView patterns in this project."
  Success: LiveView tests pass, UI works as expected
{{/if}}

{{#if PLANNING_STYLE equals "Milestone-based"}}
## Implementation Milestones

**CRITICAL**: Task descriptions under each milestone should be **prompts for Claude Code to implement**, not implementation details.

### Milestone 1: Database Layer Complete

**Deliverables:**
- Ecto schema with validations
- Migration file
- Basic CRUD context functions

**Tasks (as prompts for Claude Code):**
- "Create an Ecto schema for [entity] with appropriate fields and validations"
- "Generate a migration for the [entity] table"
- "Add context module with standard CRUD functions following existing patterns"
- "Write comprehensive tests for schema and context functions"

**Acceptance Criteria:**
- All database operations work
- Tests cover happy and error paths
- Migration runs without errors

### Milestone 2: Web Layer Complete

**Deliverables:**
- Controller or LiveView
- Templates/HEEx
- Routes configured

**Tasks (as prompts for Claude Code):**
- "Create a LiveView for [entity] management with list, create, edit, and delete"
- "Add routes for the new LiveView following existing router patterns"
- "Write integration tests for all LiveView actions"

**Acceptance Criteria:**
- All CRUD operations accessible via web
- UI renders correctly
- Integration tests pass
{{/if}}

## Success Criteria

### Automated Verification

Run these commands to verify implementation:

- [ ] **Compilation**: `mix compile --warnings-as-errors` succeeds
- [ ] **Tests**: {{TEST_COMMAND}} passes
{{QUALITY_TOOLS_CHECKS}}

### Manual Verification

Human verification required:

- [ ] Feature works as expected in browser/IEx
- [ ] Edge cases handled appropriately
- [ ] Error messages are clear and helpful
- [ ] Documentation updated (@moduledoc, @doc)
- [ ] No console errors or warnings
- [ ] Performance is acceptable

## Dependencies

[List any Hex packages that need to be added to mix.exs]

## Configuration Changes

[List any config changes needed in config/]

## Migration Strategy

[If database changes, describe migration approach]

## Rollback Plan

[How to undo these changes if needed]

## Notes

[Any additional context, decisions, or considerations]
```

### Step 5: Present Plan

**Show user the created plan:**
- Location of plan file
- Brief summary of phases/tasks
- Success criteria overview

**Confirm readiness:**
- Ask if plan looks good or needs adjustments
- Offer to clarify any phase/task
- Ready to proceed to implementation

## Important Guidelines

### Complete Alignment Required

**No open questions in final plan:**
- All technical decisions resolved
- All design choices made
- All ambiguities clarified
- Ready for immediate execution

### Success Criteria Format

**Separate automated from manual:**

**Automated** = Can run via command:
- `{{TEST_COMMAND}}`
- `mix compile --warnings-as-errors`
- `mix format --check-formatted`
{{QUALITY_TOOLS_EXAMPLES}}

**Manual** = Requires human verification:
- UI functionality
- UX quality
- Edge case handling
- Documentation quality

### Task Descriptions as Prompts

Every phase/task MUST be written as a prompt for Claude Code:
- Describe WHAT to accomplish, not HOW to implement
- Let Claude Code research the codebase for implementation details
- Avoid code examples in plans (they become outdated)
- Include success criteria for verification

### Elixir-Specific Considerations

**For Phoenix projects:**
- Context boundaries and public APIs
- Controller vs LiveView choice
- Route placement and naming
- Template organization

**For Ecto changes:**
- Schema design and relationships
- Changeset validations
- Migration strategy (reversible)
- Repo operations (transaction needs)

**For Process-based features:**
- Supervision tree placement
- GenServer/Agent design
- Message passing patterns
- Process naming and registration

**For API clients or repetitive patterns:**
- 1-3 endpoints: Plain functions, copy-paste acceptable
- 4-9 endpoints: Shared helper module for common patterns
- 10+ similar endpoints: Consider macro DSL
- Always prove patterns first with manual implementations
- Macros are idiomatic in Elixir for declarative DSLs

## Non-Negotiable Standards

1. **Research first**: Always gather context before planning
2. **Prompts, not code**: Task descriptions are prompts for Claude Code, not implementation details
3. **Success criteria**: Always separate automated vs manual verification
4. **User approval**: Get approval on approach before detailed plan
5. **Complete plan**: No open questions when finished
6. **Describe WHAT**: Let Claude Code determine HOW by researching the codebase

## Example Scenario

**User**: "Add user authentication to the Phoenix app"

**Process**:
1. Research existing auth patterns in codebase
2. Present options: Guardian vs Pow vs custom
3. User chooses Guardian
4. Propose 5 phases: Schema, Context, Plugs, Controllers, Tests
5. User approves
6. Write plan with tasks as prompts:
   - Phase 1 prompt: "Add Guardian dependency and create User schema with email and hashed_password fields. Include password hashing in changeset."
   - Phase 2 prompt: "Create Accounts context with register_user/1, authenticate/2, and get_user!/1 functions. Add tests for each."
   - etc.
7. Include success criteria (auth tests pass, login works)
8. Plan ready for Claude Code to execute phase by phase
