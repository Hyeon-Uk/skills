---
name: committer
description: Stage and commit completed work for an active package refactor with the Tizen/Gerrit commit format (subject + body + Change-Id + Signed-off-by), one work-unit per commit, and a Release commit per release window listing every commit-title that landed since the previous release. Commit stage of the per-task pipeline. Triggers on /committer.
---

# `/committer` — Commit stage of the per-task pipeline

You stage and commit. Two commit *kinds* exist:

| Kind | When | Subject | Body shape |
|---|---|---|---|
| **Work-unit commit** | Inside a task — every TDD step that goes green; every reviewer-approved diff. One scope per commit. | Short imperative title starting with a **capitalized verb** (e.g. `Add notification's internal test`); ≤ 70 chars; no `type(scope):` prefix; no trailing period. | Concise body explaining **what** changed and **why**. Wrap at 72 chars. |
| **Release commit** | At the end of a release window — AFTER every task's work-unit commits in that window have already landed. ONE per window. Touches **only** `packaging/<package>.spec` `Version:` line. | `Release version X.Y.Z` (no scope, no period). | `Changes:` listing every work-unit-commit *title* that landed since the previous Release, in chronological order (oldest first). |

Both kinds carry `Change-Id` and `Signed-off-by` trailers (Gerrit /
review.tizen.org convention).

## Inputs

- `## Refined prompt`, `## Execution plan`, `## Design`,
  `## Developer log`, `## Tester report`, `## Review report` in
  the active log file.
- `git status`, `git diff`, `git log <prev-release>..HEAD --oneline`
  on the package repo.
- The convention list in
  `refactoring-plans/00_workflow/rules.md` (R-COMMIT-SCOPE,
  R-COMMIT-FORMAT, R-COMMIT-RELEASE).

## Output

Append a `## Commits` section to the active log file:

```
- <sha>  Add failing tests for X
- <sha>  Adopt SqliteStmt RAII guard in <scope>
```

If this commit closes a release window, also append / update
`refactoring-plans/99_release_notes/<X.Y.Z>.md` with the
**verbatim** Release commit message you used.

---

## Work-unit commit format

```
<Capitalized verb> <rest of the subject>

<one to three short paragraphs explaining what changed and why>

Change-Id: I<40-hex>
Signed-off-by: <Author Name> <author@email>
```

Rules:
- **Subject must start with a capital letter and lead with a verb**
  in the imperative mood (e.g. `Add`, `Modify`, `Remove`, `Fix`,
  `Cover`, `Adopt`, `Introduce`, `Refactor`). Matches upstream
  Tizen style — see `a553836` (`Modify the major warning of svace`).
- **No `type(scope):` Conventional-Commits prefix.** The scope, if
  worth naming, belongs *inside* the sentence
  (e.g. `Add notification's internal test`,
  `Adopt SqliteStmt RAII guard in pkgmgr-info`). Even though there
  is no prefix, the **one-scope-per-commit** rule (R-COMMIT-SCOPE)
  still holds — split mixed-scope work into separate commits.
- Subject ≤ 70 chars, no trailing period.
- Body wrapped at 72 cols; explains *why* more than *what*.
- `Change-Id` is a SHA1-style 40-hex string prefixed with `I`. The
  Gerrit `commit-msg` hook generates it automatically; if the hook
  isn't installed, generate it manually (see "Change-Id generation"
  below).
- `Signed-off-by` matches `git config user.name` and
  `git config user.email`. Use the **same** value as the existing
  Tizen commits in this repo (e.g. `KimHyeonuk
  <hyeonuk.kim@samsung.com>`); do NOT add Anthropic / Claude /
  AI-tool trailers — upstream Tizen review will reject them.

### Examples

Good subjects (capitalized, verb-first, scope inside the sentence):

```
Add notification's internal test
Cover notification_status_to_string mappings
Adopt SqliteStmt RAII guard in pkgmgr-info
Modify the major warning of svace
Remove dead pkgmgr_info_internal helpers
```

Bad subjects (rejected — bounce back and rewrite):

```
test(notification): add internal test          ← no type(scope): prefix
add notification's internal test               ← must capitalize first letter
notification: add internal test                ← must lead with a verb
Added notification's internal test.            ← imperative, no period
```

Full example:

```
Cover notification_status_to_string mappings

Add the first test fixture for notification_status.c. Asserts every
notification_status_e enum value documented in notification.h
round-trips through the converter and the documented fallback for
unknown integers is observed. Locks behavior in before any
production-side touch lands.

Change-Id: I9b3a4f1e2c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f
Signed-off-by: KimHyeonuk <hyeonuk.kim@samsung.com>
```

---

## Release commit format

```
Release version X.Y.Z

Changes:
 - <work-unit commit subject 1>
 - <work-unit commit subject 2>
 - …
 - <work-unit commit subject N>

Change-Id: I<40-hex>
Signed-off-by: <Author Name> <author@email>
```

Rules:
- Subject is exactly `Release version X.Y.Z` — no scope prefix, no
  period.
- Body always starts with `Changes:` (capital C, colon) on its own
  line.
- Each bullet is **the verbatim subject line** of a work-unit commit
  that landed between the previous release and this one. Use
  `git log <prev-release>..HEAD --pretty='%s'` to enumerate; drop
  any prior `Release version …` lines if a chain of releases
  somehow accumulates.
- Bullets use `-` (hyphen-space, NOT `*`). Indented one space:
  ` - <subject>`. Matches upstream style — see `a553836`,
  `496825e`, `b49676f`.
- Order = chronological, oldest first (top of `git log` reversed).
- No `Co-Authored-By` trailer on Release commits (matches upstream
  style — see `a553836` `Release version 0.12.1`).
- **The Release commit's diff is exactly one file, exactly one
  line: the `Version:` sentinel in `packaging/<package>.spec`**
  (e.g. `Version:    0.12.1` → `Version:    0.12.2`). All other
  changes — smoke targets, test source, build wiring, spec edits
  other than the version line — must already be on disk as
  preceding work-unit commits. If the would-be Release diff
  touches more than that one line, bounce back to developer to
  land the extra work as its own work-unit commit first.

### Example (mirroring `a553836` Release version 0.12.1)

```
Release version 0.12.1

Changes:
 - Modify the major warning of svace

Change-Id: I0a262977528b67a8a702947d9caa889e87bb1f90
Signed-off-by: KimHyeonuk <hyeonuk.kim@samsung.com>
```

### Release commit drafting procedure

The Release commit is the **last** commit of a release window
and exists to flip a single switch: the version sentinel in
`packaging/<package>.spec`. All task-level work — code, tests,
build wiring — must already be on disk as preceding **work-unit
commits**. The Release commit itself touches *only* the spec
`Version:` line.

0. **Mandatory test gate (REQUIRED — no exceptions).** Before
   drafting the Release commit, run a full GBS build with tests
   enabled:
   ```bash
   gbs build -A x86_64 --include-all
   ```
   Inspect the `%check` section in the `.build.log`. If any test
   binary reports a non-zero exit code (i.e. `UNITTEST_EXIT=`,
   `SMOKE_EXIT=`, or `INTEGRATION_EXIT=` appears in the log), stop
   immediately and bounce to `developer` with the failing output.
   **Do NOT proceed to the Release commit until all three test
   binaries pass.**

1. Verify ALL tasks intended for this release window are
   `completed` in `06_progress/STATE.md` and ALL their work-unit
   commits are landed on the package's working tree.
   Run `git log <prev-release-sha>..HEAD --pretty='%h %s' --reverse`
   and confirm the list matches the active release window's task
   ledger.
2. **Drafting the body**:
   `git log <prev-release-sha>..HEAD --pretty='%s' --reverse`
   gives every work-unit subject since the previous Release. Drop
   any defensive `Release version …` lines (shouldn't appear inside
   one window). Indent each remaining subject with ` - ` (one space
   + hyphen + space) under a single-line `Changes:` heading.
3. Compose the subject: `Release version X.Y.Z` per
   `02_roadmap/roadmap.md`.
4. Add `Change-Id` (generate per "Change-Id generation"); add
   `Signed-off-by`.
5. **Stage exactly one file**: `packaging/<package>.spec` —
   AND the only change in it is the `Version:` bump line.
   - If you find yourself wanting to stage anything else, that work
     belongs in a preceding work-unit commit. Bounce back to
     developer to land it as its own commit; then redo step 1.
6. `git commit` with the message composed in 2-4. The resulting
   `git show --stat` should show one file changed, `+1 / -1` line
   (just the version sentinel).
7. Capture the new SHA into the active task log's `## Commits`
   section and into `99_release_notes/<X.Y.Z>.md`.

---

## Procedure (per task)

1. **Verify reviewer APPROVE.** No commit if the verdict was
   REQUEST CHANGES or ESCALATE.
2. **Stage by file.** Never `git add -A` / `git add .`. Stage only
   the files the reviewer's diff covered.
3. **Compose the commit message** in the matching kind's format.
4. **Generate `Change-Id`** (see below).
5. **Commit** with `git commit -m "$(cat <<'EOF' … EOF)"`.
6. **Pre-commit hook check.** If a pre-commit hook fails: do NOT
   `--amend`. Fix the issue, re-stage, create a NEW commit. (The
   Change-Id stays the same so Gerrit treats it as a patchset of
   the same Change.)
7. **Capture sha** into the log's `## Commits` section.

## Change-Id generation

The Gerrit `commit-msg` hook auto-generates `Change-Id`. To install
it once locally:

```bash
mkdir -p .git/hooks
curl -fsSL https://review.tizen.org/r/tools/hooks/commit-msg \
     -o .git/hooks/commit-msg
chmod +x .git/hooks/commit-msg
```

If installing is not possible (offline / no network), generate
manually:

```bash
printf 'I%s\n' \
  "$(git diff --cached | sha1sum | awk '{print $1}')"
```

Either way, the resulting `Change-Id: I<40-hex>` line goes into
the message body, just before `Signed-off-by`.

## Rules

- **R-COMMIT-FORMAT** — every commit (work-unit and Release)
  carries `Change-Id` and `Signed-off-by`. Work-unit subjects start
  with a capitalized verb and carry no `type(scope):` prefix;
  Release subjects are exactly `Release version X.Y.Z`.
- **R-COMMIT-SCOPE** — one scope per work-unit commit. Multi-scope
  bounces back to developer for splitting.
- **R-COMMIT-RELEASE** — Release commit body lists every work-unit
  commit subject since the previous Release, in chronological
  order, under a `Changes:` heading.
- **R-NO-PUSH** — never push to origin. Local commits only.
- **No `--amend` for fixing a pre-commit hook failure** (create a
  NEW commit so Gerrit sees the patchset progression).
  Amending the immediately preceding *unpushed* commit purely to
  fix its message metadata (e.g., add a missing Change-Id) is
  acceptable; it is the only valid amend case.
- **No `git rebase -i`, no force-push, no destructive history
  rewrites of pushed commits.**
- **No Anthropic / Claude / AI-tool trailers** in commits that will
  upstream to review.tizen.org. The Tizen upstream history for
  these packages has none; we match.

## Stop conditions

- Commit list written under `## Commits` in the log.
- Hand off to `/supervisor` for exit checkpoint.

## Failure modes

- Staging files the reviewer didn't review.
- Mixed-scope commits.
- Lower-case or non-verb-leading work-unit subjects
  (e.g. `add internal test`, `notification: add internal test`,
  `test(notification): …`). Rewrite as `Add notification's
  internal test`.
- Release commit missing the `Changes:` body.
- Forgetting `Change-Id` (Gerrit will reject on push).
- Forgetting `Signed-off-by` (Gerrit will reject; project policy).
- Adding `Co-Authored-By: Claude …` trailer (foreign to upstream
  history; rejected on review).
