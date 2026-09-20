# Git Workflow

This project follows Conventional Commits with English imperative messages.

## Rules

- Atomic commits: one logical change per commit
- Push immediately after each commit
- Semantic versioning for releases (`vMAJOR.MINOR.PATCH`)
- **No AI attribution** in commits, code comments, pull requests or tags
- Subject line: lower-case, imperative, no trailing period, max 72 characters

## Types

`feat` · `fix` · `refactor` · `chore` · `docs` · `style` · `test` · `perf` · `ci`

## Scopes used in this project

`core` · `engine` · `rules` · `ui` · `ai` · `gamecenter` · `persistence` ·
`ci` · `fastlane` · `brand`

## Examples

```
feat(core): add parametric board graph for 2 to 6 seats
fix(engine): stop a jack from targeting a controlled seat's own pawn
test(core): cover board, card rules, game flow and state invariants
docs: add project memory documents
```

## Branching

`main` is the production branch and stays stable. Solo work may commit directly
to `main` with atomic commits. Longer or riskier work uses `feature/…` or
`fix/…` branches with a short lifetime.
