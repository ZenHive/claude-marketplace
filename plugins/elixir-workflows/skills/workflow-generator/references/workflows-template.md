# WORKFLOWS.md Template

Generate this file at the location specified by the user (Question 6). Substitute all `{{VARIABLE}}` placeholders with actual values from the customization questions.

```markdown
# Elixir Project Workflows

This project uses a standardized workflow system for research, planning, implementation, and quality assurance.

## Generated for: {{PROJECT_TYPE}} (Elixir)

---

## Available Commands

### /research

Research the codebase to answer questions and document existing implementations.

**Usage**:
/research "How does authentication work?"
/research "What is the API structure?"

**Output**: Research documents saved to `{{DOCS_LOCATION}}/research-YYYY-MM-DD-topic.md`

---

### /plan

Create detailed implementation plans with success criteria.

**Usage**:
/plan "Add user profile page"
/plan "Refactor database layer"

**Output**: Plans saved to `{{DOCS_LOCATION}}/plans/YYYY-MM-DD-description.md`

**Plan Structure**: {{PLANNING_STYLE}}

---

### /implement

Execute implementation plans with automated verification.

**Usage**:
/implement "2025-01-23-user-profile"
/implement   # Will prompt for plan selection

**Verification Commands**:
- Compile: `mix compile --warnings-as-errors`
- Test: `{{TEST_COMMAND}}`
- Format: `mix format --check-formatted`
{{#each QUALITY_TOOLS}}
- {{this}}
{{/each}}

---

### /qa

Validate implementation against success criteria and project quality standards.

**Usage**:
/qa                    # General health check
/qa "plan-name"        # Validate specific plan implementation

**Quality Gates**:
{{#each VALIDATION_CRITERIA}}
- {{this}}
{{/each}}

**Fix Workflow** (automatic): When critical issues are detected, `/qa` offers to automatically generate and execute a fix plan.

---

### Fix Workflow (Automatic)

When `/qa` detects critical issues, it automatically offers to generate a fix plan and execute it.

**Automatic Fix Flow**:
/qa -> Critical issues detected
    -> "Generate fix plan?" -> Yes
    -> /plan "Fix critical issues from QA report: ..."
    -> Fix plan created at {{DOCS_LOCATION}}/plans/plan-YYYY-MM-DD-fix-*.md
    -> "Execute fix plan?" -> Yes
    -> /implement fix-plan-name
    -> /qa -> Re-validation
    -> Pass or iterate

**Oneshot with Auto-Fix**:
/oneshot "Feature" -> Research -> Plan -> Implement -> QA
                                                        -> Fails with critical issues
                                   -> /plan "Fix..." -> /implement fix -> /qa
                                                        -> Pass -> Complete

---

## Workflow Sequence

1. **Research** (`/research`) - Understand current implementation
2. **Plan** (`/plan`) - Create detailed implementation plan
3. **Implement** (`/implement`) - Execute plan with verification
4. **QA** (`/qa`) - Validate against success criteria

---

## Customization

These commands were generated based on your project configuration. Edit them directly:

- `.claude/commands/elixir-research.md`
- `.claude/commands/elixir-plan.md`
- `.claude/commands/elixir-implement.md`
- `.claude/commands/elixir-qa.md`
- `.claude/commands/elixir-oneshot.md`

To regenerate: `/elixir-workflows:workflow-generator`

---

## Project Configuration

**Project Type**: {{PROJECT_TYPE}}
**Tech Stack**: Elixir
**Test Command**: {{TEST_COMMAND}}
**Documentation**: {{DOCS_LOCATION}}
**Planning Style**: {{PLANNING_STYLE}}

**Quality Tools**:
{{#each QUALITY_TOOLS}}
- {{this}}
{{/each}}
```
