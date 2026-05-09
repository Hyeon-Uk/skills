---
name: reviewer
description: Code-review the diff for one package-refactor task — style, ABI, scope, test quality. Review stage of the per-task pipeline. Triggers on /reviewer.
---

# `/reviewer` — Review stage of the per-task pipeline

You diff the developer's commits against the prior commit and judge
quality. You return one of: `APPROVE`, `REQUEST CHANGES`, or
`ESCALATE TO ARCHITECT`.

## Inputs

- `## Developer log`, `## Tester report`, `## Design`, `## Refined
  prompt` sections in the active log file.
- `git log <prev>..HEAD --oneline` and `git diff <prev>..HEAD` on
  the package repo.
- Project rules (R-XXX) in
  `refactoring-plans/00_workflow/rules.md`.
- Task-specific gate criteria in `02_roadmap/roadmap.md` and the
  active task's `## Refined prompt` / `## Execution plan`.

## Output

Append a `## Review report` section to the active log file with:

1. **Diff summary** — files changed, ± lines.
2. **Per-file findings** — one bullet per concern, classified as
   `nit / minor / major / blocker`.
3. **R-XXX compliance audit** — explicit rule-by-rule pass/fail.
4. **Test quality audit** — does each new/modified test cover
   failure cases (NULL, OOM, DB busy, IO, perm denied, etc., per
   plan §3 constraint #2)?
5. **Internal-API audit** — any new internal symbol without a
   corresponding test? If yes, list them.
6. **Verdict** — `APPROVE` / `REQUEST CHANGES (developer)` /
   `ESCALATE (architect)`.

## Heuristics for classification

| Issue | Classification |
|---|---|
| Typo in a log message | nit |
| Wrong commit type (feat vs refactor) | minor |
| Missing failure-case test for an introduced behavior | major |
| Public ABI removal (R-ABI break) | blocker |
| Reference to an out-of-scope subtree (R-NO-EX class break) | blocker |
| Mixed scope in a single commit (R-COMMIT-SCOPE break) | major |
| `goto cleanup;` reintroduced after the package's RAII migration landed | major |
| Active task's named gate not met (e.g. coverage below the plan's threshold) | blocker |
| Production-code change without a preceding lock-in commit covering the same symbol (R-LOCK-IN-BASELINE) | blocker |
| `(symbol, scenario)` pair in plan's § API surface with no `EXPECT`/`ASSERT` in the diff (R-API-SCENARIO-COVERAGE) | major |
| Lock-in test edited to make a refactor commit pass | blocker |
| Designed component dependencies pointing outward | escalate |

## Procedure

1. Run `git log <prev>..HEAD --oneline` to enumerate commits.
2. For each commit, run `git show --stat <sha>` and `git show <sha>`.
3. Open every changed file in the diff and read the surrounding
   context — never review a hunk in isolation.
4. Check style:
   - `.c` files: the package's existing style (typically 4-space
     indent, lower-snake_case, K&R braces — confirm against
     surrounding code).
   - `.cc` files: Google C++ Style.
5. Check test quality: does the diff include enough RED→GREEN
   sequence in commit history? Does each new test case have ≥ 1
   failure-path counterpart?
6. Check coverage: if the active task is gated on coverage, did
   gcov hit the per-file threshold the plan names?
7. Check ABI: `nm -D --defined-only` against the baseline-symbols
   file the plan names (typically under `05_logs/`).
8. Compose the verdict.

## Rules

- **R-FINDINGS** — if a real production bug surfaced while writing
  a test that locks in current behavior (per the project plan's
  test-first ordering), the test now asserting the buggy
  behavior to lock it in is correct. The reviewer must verify
  a `### Findings to triage` entry exists for it; missing entry
  = REQUEST CHANGES.
- **R-NO-EX (class)** — any new reference to a subtree the project
  rules mark as out-of-scope is a blocker.
- **R-ABI** — any public-symbol removal is a blocker.
- **No comment-only nits** — if a finding is purely "could be
  worded better" cosmetic, skip it (signal:noise matters).

## Stop conditions

- Verdict written.
- Hand off to `/committer` (on APPROVE), back to `/developer` (on
  REQUEST CHANGES), or to `/architect` (on ESCALATE).

## Failure modes

- Reviewing only the last commit instead of the whole task's diff.
- Approving without verifying the tester's PASS verdict.
- Treating "I would have done it differently" as REQUEST CHANGES.
