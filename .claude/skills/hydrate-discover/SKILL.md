---
name: hydrate-discover
description: >
  Inventory the source surface for hydrating working memory in this repo.
  Surveys manifests, code structure, README, ADRs (if any), recent git history,
  and code patterns. Run once when populating working memory beyond the
  scaffold prompt's pre-population.
---

# hydrate-discover

When this skill is activated:

1. Scan the repo for typical sources:
   - **Manifests:** `package.json`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `requirements.txt`, etc.
   - **Code structure:** top-level directories under `src/`, `app/`, `lib/`, `pkg/`, etc.
   - **Documentation:** `README.md`, `docs/`, `.github/copilot-instructions.md`
   - **ADRs (if present):** `docs/adrs/`, `docs/decisions/`
   - **Recent git history:** `git log --since="180 days ago" --pretty=format:"%h %s"`
   - **Configuration:** `tsconfig.json`, `.eslintrc.json`, `pyproject.toml`, etc.
2. Note any working memory that already exists at `_working-memory/` so reconcile can use it later.
3. Mark sources outside the repo (Notion, Slack, ADO) as "out of scope for automated extraction". Flag them, don't skip silently.

## Output

A Markdown table: source, location, type, automation level (deterministic / AI-semantic / out-of-scope).

This skill inventories only. Pass the output to `hydrate-extract` for actual findings.

## Common gotchas

- Monorepos may have multiple manifests at different paths. List each.
- A README that points elsewhere ("see our wiki") signals an external source the agent can't reach; note it but don't fabricate content.
- The scaffold prompt already pre-populates basic stack info; this skill goes deeper, so don't skip sources just because the scaffold touched them.
