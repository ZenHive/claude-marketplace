# Usage Instructions (Step 10)

Present this summary to the user after all commands are generated. Substitute all `{{VARIABLE}}` placeholders with actual values.

## Created Commands

```
.claude/
  commands/
    interview.md    # Interactive context gathering
    research.md     # Research and document codebase
    plan.md         # Create implementation plans
    implement.md    # Execute plans with verification
    qa.md           # Validate implementation quality
    oneshot.md      # Complete workflow in one command
{{WORKFLOWS_MD_LOCATION}}  # Complete workflow documentation
```

**Note**: Show the actual file path where WORKFLOWS.md was created based on Question 6 answer.

## Documentation Structure

```
{{DOCS_LOCATION}}/
  interview/          # Interview context documents
  research/           # Research documents
  plans/              # Implementation plans
```

## Configuration Summary

**Project**: {{PROJECT_TYPE}} (Elixir)

**Commands Configured**:
- Compile: `mix compile --warnings-as-errors`
- Test: `{{TEST_COMMAND}}`
- Format: `mix format --check-formatted`

**Quality Tools Enabled**:
{{#each QUALITY_TOOLS}}
- {{this}}
{{/each}}

**Planning Style**: {{PLANNING_STYLE}}

## Quick Start

### 1. Research the Codebase

```bash
/research "How does [feature] work?"
```

This will:
- Spawn parallel research agents
- Document findings with file:line references
- Save to `{{DOCS_LOCATION}}/research-YYYY-MM-DD-topic.md`

### 2. Create an Implementation Plan

```bash
/plan "Add new feature X"
```

This will:
- Gather context via research
- Present design options
- Create phased plan with success criteria
- Save to `{{DOCS_LOCATION}}/plans/YYYY-MM-DD-feature-x.md`

### 3. Execute the Plan

```bash
/implement "2025-01-23-feature-x"
```

This will:
- Read the plan
- Execute phase by phase
- Run verification after each phase (`mix compile`, {{TEST_COMMAND}})
- Update checkmarks
- Pause for confirmation

### 4. Validate Implementation

```bash
/qa "feature-x"
```

This will:
- Run all quality gate checks
- Generate validation report
- Provide actionable feedback

## Workflow Example

**Scenario**: Adding a new Phoenix context

```bash
# 1. Research existing patterns
/research "How are contexts structured in this Phoenix app?"

# 2. Create implementation plan
/plan "Add Accounts context with user management"

# 3. Execute the plan
/implement "2025-01-23-accounts-context"

# 4. Validate implementation
/qa "accounts-context"
```

## Customization

All generated commands are fully editable:

- **Add custom validation**: Edit `.claude/commands/elixir-qa.md`
- **Change plan structure**: Edit `.claude/commands/elixir-plan.md`
- **Add research sources**: Edit `.claude/commands/elixir-research.md`
- **Modify checkpoints**: Edit `.claude/commands/elixir-implement.md`

## Re-generate Commands

To regenerate with different settings:

```bash
/workflow-generator
```

## Next Steps

1. Try your first research: `/research "project structure"`
2. Read workflow docs: `{{WORKFLOWS_MD_LOCATION}}`
3. Customize commands as needed (edit `.claude/commands/*.md`)
4. Start your first planned feature!
