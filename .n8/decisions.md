# Decisions

A dated, append-only narrative of choices made during planning and execution
-- not a source of current counts or facts. If a sentence here would state a
number or a status that a command could compute, prefer the command; a
narrative entry is a record of *why*, not a live dashboard. (See
CLAUDE.md's note on the same rule.)

Entries are appended by `/n8-exec`, `/n8-replan`, and any session that makes
a decision outside those commands (a project's `CLAUDE.md` should carry the
standing instruction to log here; `/n8-init` writes it).

Format:

```markdown
## /n8-exec M1 -- 2026-08-27

- **Decision:** <what was chosen>
  **Why:** <the reasoning>
  **Issue:** <#N>
```

Ad-hoc entries (decisions made outside a planning/execution command) use:

```markdown
## Ad-hoc -- 2026-08-27

- **Change:** <what changed>
  **Why:** <the reasoning>
  **Affects:** <milestones/issues likely affected>
```
