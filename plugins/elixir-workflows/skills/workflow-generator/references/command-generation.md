# Command Generation Steps (Steps 3-8)

Detailed variable substitution instructions for each generated command.

## Step 3: Generate /elixir-research Command

**Read the template:**
- Use Read tool to read `plugins/elixir-meta/skills/workflow-generator/templates/research-template.md`

**Perform variable substitution:**

Replace these variables in the template:
- `{{PROJECT_TYPE}}` -> Answer from Question 1 (e.g., "Phoenix Application")
- `{{DOCS_LOCATION}}` -> Answer from Question 3 (e.g., ".thoughts")
- `{{PROJECT_TYPE_TAGS}}` -> Tags based on project type:
  - Phoenix Application -> "phoenix, web, elixir"
  - Library/Package -> "library, hex, elixir"
  - CLI/Escript -> "cli, escript, elixir"
  - Umbrella Project -> "umbrella, multi-app, elixir"
- `{{PROJECT_TYPE_SPECIFIC}}` -> Project-specific component types for agent prompts:
  - Phoenix Application -> "Phoenix contexts, controllers, LiveViews, and schemas"
  - Library/Package -> "public API modules and functions"
  - CLI/Escript -> "CLI commands, Mix tasks, and escript entry points"
  - Umbrella Project -> "umbrella apps and shared modules"

**Write customized command:**
- Use Write tool to create `.claude/commands/elixir-research.md`

---

## Step 4: Generate /elixir-plan Command

**Read the template:**
- Use Read tool to read `plugins/elixir-meta/skills/workflow-generator/templates/plan-template.md`

**Perform variable substitution:**

- `{{PLANNING_STYLE}}` -> Answer from Question 5 (e.g., "Detailed phases")
- `{{DOCS_LOCATION}}` -> Answer from Question 3
- `{{TEST_COMMAND}}` -> Answer from Question 2, map to actual command:
  - "mix test" -> "mix test"
  - "make test" -> "make test"
  - "Custom script" -> Ask user what command to use
- `{{PROJECT_TYPE}}` -> Answer from Question 1
- `{{PROJECT_TYPE_TAGS}}` -> Same tags as research command
- `{{QUALITY_TOOLS_CHECKS}}` -> Expand based on Question 4 answers:
  - If "Credo" selected: Add "- [ ] `mix credo --strict` passes"
  - If "Dialyzer" selected: Add "- [ ] `mix dialyzer` passes"
  - If "Sobelow" selected: Add "- [ ] `mix sobelow --exit Low` passes"
  - If "Format check" selected: Add "- [ ] `mix format --check-formatted` passes"
  - If "ExDoc" selected: Add "- [ ] `mix docs` succeeds (no warnings)"
  - If "mix_audit" selected: Add "- [ ] `mix deps.audit` passes"
- `{{QUALITY_TOOLS_EXAMPLES}}` -> Same expansion as checks but as examples

**Write customized command:**
- Use Write tool to create `.claude/commands/elixir-plan.md`

---

## Step 5: Generate /elixir-implement Command

**Read the template:**
- Use Read tool to read `plugins/elixir-meta/skills/workflow-generator/templates/implement-template.md`

**Perform variable substitution:**

- `{{DOCS_LOCATION}}` -> Answer from Question 3
- `{{TEST_COMMAND}}` -> Actual test command from Question 2
- `{{VERIFICATION_COMMANDS}}` -> Per-phase verification commands:
  ```bash
  # Always include:
  mix compile --warnings-as-errors
  {{TEST_COMMAND}}
  mix format --check-formatted

  # Add if selected in Question 4:
  mix credo --strict  # if Credo
  mix dialyzer  # if Dialyzer
  ```
- `{{FULL_VERIFICATION_SUITE}}` -> All quality checks expanded:
  - Always: compile, test, format
  - Conditionally: Credo, Dialyzer, Sobelow, ExDoc, mix_audit (if selected)
- `{{QUALITY_TOOLS_SUMMARY}}` -> Summary line for each enabled tool
- `{{OPTIONAL_QUALITY_CHECKS}}` -> Per-phase optional checks if tools enabled

**Write customized command:**
- Use Write tool to create `.claude/commands/elixir-implement.md`

---

## Step 6: Generate /elixir-qa Command

**Read the template:**
- Use Read tool to read `plugins/elixir-meta/skills/workflow-generator/templates/qa-template.md`

**Perform variable substitution:**

- `{{PROJECT_TYPE}}` -> Answer from Question 1
- `{{TEST_COMMAND}}` -> Actual test command from Question 2
- `{{DOCS_LOCATION}}` -> Answer from Question 3
- `{{PROJECT_TYPE_TAGS}}` -> Same tags as research command
- `{{QUALITY_TOOL_COMMANDS}}` -> Expand quality tool commands based on Question 4
- `{{QUALITY_TOOLS_RESULTS_SUMMARY}}` -> Summary lines for report template
- `{{QUALITY_TOOLS_DETAILED_RESULTS}}` -> Detailed result sections for enabled tools
- `{{SUCCESS_CRITERIA_CHECKLIST}}` -> Checklist items for each enabled tool
- `{{PROJECT_TYPE_SPECIFIC_OBSERVATIONS}}` -> Phoenix/Ecto/OTP observations based on project type
- `{{QUALITY_TOOL_INTEGRATION_GUIDE}}` -> Integration guidance for enabled tools
- `{{QUALITY_TOOLS_SUMMARY_DISPLAY}}` -> Display format for enabled tools in final output

**Write customized command:**
- Use Write tool to create `.claude/commands/elixir-qa.md`

---

## Step 7: Generate /elixir-oneshot Command

**Read the template:**
- Use Read tool to read `plugins/elixir-meta/skills/workflow-generator/templates/oneshot-template.md`

**Perform variable substitution:**

- `{{FEATURE_DESCRIPTION}}` -> User's feature description (from $ARGUMENTS)
- `{{DOCS_LOCATION}}` -> Answer from Question 3
- `{{TEST_COMMAND}}` -> Actual test command from Question 2
- `{{PROJECT_TYPE}}` -> Answer from Question 1
- `{{QUALITY_TOOLS}}` -> Boolean check if any quality tools selected
- `{{QUALITY_TOOLS_SUMMARY}}` -> Comma-separated list of enabled tools
- `{{QUALITY_TOOLS_STATUS}}` -> Status summary for each tool
- `{{QUALITY_TOOLS_LIST}}` -> List format of enabled tools
- `{{QA_PASSED}}` -> Conditional variable for success/failure branching

**Write customized command:**
- Use Write tool to create `.claude/commands/elixir-oneshot.md`

---

## Step 8: Generate /elixir-interview Command

**Read the template:**
- Use Read tool to read `plugins/elixir-meta/skills/workflow-generator/templates/interview-template.md`

**Perform variable substitution:**

- `{{PROJECT_TYPE}}` -> Answer from Question 1 (e.g., "Phoenix Application")
- `{{DOCS_LOCATION}}` -> Answer from Question 3 (e.g., ".thoughts")

The interview command needs minimal customization compared to other commands as it uses dynamic question generation.

**Write customized command:**
- Use Write tool to create `.claude/commands/elixir-interview.md`
