# Agent Instructions

General agent configuration, skills and the pre-push checks for this repository are in
[.github/AGENTS.md](.github/AGENTS.md). This file adds how work is tracked.

## Issue tracking with beads

Work is tracked with [beads](https://github.com/steveyegge/beads) (`bd`) in the **shared Morphir tracker**, not
in a database of this repository. The database lives in finos/morphir and syncs over its `refs/dolt/data` ref.
`.beads/config.yaml` points `bd` at it, so you do not need a finos/morphir checkout.

### Set up and sync

```shell
bd bootstrap          # first time on a machine: clones the shared database
bd dolt pull          # before you start work
bd dolt push          # after you change issues
```

The readable JSONL mirror on the `beads-sync` branch is published from finos/morphir, so pushing the database is
all you need to do here. Run `bd prime` for the full command reference.

### Worktrees

All worktrees use one database: `.beads/embeddeddolt` in the main checkout. A worktree finds it through the git
common directory, inside or outside the repository, so it needs no `.beads/redirect` file.

Run `bd bootstrap` in the main checkout before you open a worktree or start an agent session. Any `bd` command,
including the SessionStart `bd prime` hook, makes an empty local database when it finds none. An empty database in
the main checkout stops `bd bootstrap` ("Database already exists"), and a database in a worktree hides the shared
one.

```shell
mise run beads:check   # in any checkout or worktree: fails with the fix if the database is wrong
moonx scripts/beads-check.mbtx   # the same check without mise
```

To repair, move the empty `embeddeddolt` (and `backup`) directory aside and run `bd bootstrap` in the main
checkout again. Use `bd count` to make sure that a database is empty before you move it.

### Find this repository's work

Issues whose work happens here carry the label `repo:morphir-moonbit`:

```shell
bd ready --label repo:morphir-moonbit        # unblocked work
bd list --label repo:morphir-moonbit --all   # everything, including closed
bd show <id> --long                          # description, design, notes and comments
```

The work belongs to the Morphir ecosystem roadmap, epic `morphir-ukvn`, whose design is the approved roadmap spec.
The MoonBit work is Track 5, `morphir-ukvn.5`: its notes are the handoff, and the E0 spike report is the comment on
`morphir-ukvn.5.1`.

### Specs, plans and ledgers live in beads

Superpowers specs, implementation plans and execution ledgers are stored in beads, not committed here. This
overrides the superpowers skill defaults for spec, plan and ledger location.

- **Spec:** draft it locally, then `mise run beads:plan -- spec <epic> <file>` stores it as the epic's design.
  `mise run beads:plan -- spec <epic> --render` writes it back to `.dev/beads-specs/<epic>.md`.
- **Plan:** `mise run beads:plan -- import <plan.md> --parent <bead> --spec morphir-ukvn` turns it into a plan
  epic with one child bead per `### Task N`. `mise run beads:plan -- render <plan-epic>` writes
  `.dev/beads-plans/<plan-epic>.md`; use that path as the plan file for every superpowers script, and never edit it.
- **Ledger:** `mise run beads:plan -- ledger <plan-epic> "<line>" --workspace <sdd-dir>` adds a ledger line to the
  plan epic as a comment and to the local `progress.md`.
- Close each task bead with its commit range and test result as the reason.

`beads:plan` fetches `bd-plan` from finos/morphir at a pinned commit and runs it with Bun.

### Working rules

- Commits use Conventional Commits, in plain English, with no AI attribution and no `Co-Authored-By` lines.
- Merges, releases and anything irreversible wait for the maintainer's approval unless a beads memory records it
  (`bd memories approval`).
