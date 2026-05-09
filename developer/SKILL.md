---
name: developer
description: Execute TDD-based code changes for one package-refactor task. Implementation stage of the per-task pipeline. Triggers on /developer.
---

# `/developer` — Implementation stage of the per-task pipeline

You implement the code changes for the active task, strictly TDD,
following the architect's design and the planner's order.

## Inputs

- `## Refined prompt`, `## Execution plan`, `## Design` sections in
  the active log.
- The actual files referenced by the design / plan.
- `refactoring-plans/00_workflow/rules.md` — read R-TDD,
  R-NO-EX, R-ABI, R-COMMIT-SCOPE.

## Output

Append a `## Developer log` section to the active log file with one
entry per TDD cycle:

```
### Cycle <N> — <one-line description>
- RED  commit:  <sha or "pending"> — <subject>
- GREEN commit: <sha or "pending"> — <subject>
- (optional) REFACTOR commit: <sha> — <subject>
- Files touched: ...
- Notes: surprises, deferred work, links to findings (F-...)
```

## Cycle ordering — lock-in cycle FIRST

Per R-LOCK-IN-BASELINE, the very first developer cycle on any
task that will touch production code is the **lock-in cycle**:
write tests that assert the *current* observable behavior of
every (symbol, scenario) pair in the planner's `### API
surface`, run them GREEN against the **unchanged** production
tree, and commit them as their own work-unit commits
(`test(<scope>): lock in <module> baseline behavior`).

Refactor cycles only begin after every lock-in test is green.
A refactor commit that breaks a lock-in test = regression; do
**not** edit the lock-in test to make it pass — bounce.

If a lock-in test reveals a real production bug while capturing
current behavior, R-FINDINGS applies: rewrite the test to assert
the *current* (buggy) behavior so it stays green, log the bug
under `### Findings to triage`, and continue the lock-in pass.

## Procedure (per cycle)

1. **Write the failing test.** Place it in the file the design names
   under "Test seams". The test must fail because the *behavior under
   test* isn't yet implemented (or — for tests-only tasks that lock
   in current behavior before a later production-side touch — because
   the test correctly asserts the *current* behavior on a fresh file
   before any setup is in place).

   Pick the right authoring skill for the test you are writing —
   each one enforces the analysis-first / mocking / RPM-wiring
   conventions used across the Tizen AppFW codebase:

   - **Unit tests (gtest / gmock)** — `/tizen-gtest-unit-test`. Use
     for any new `TEST_F` exercising a single C/C++ symbol with
     mocked dependencies (`TestFixture + ModuleMock + mock_hook`
     pattern). Before writing test code, enumerate the target
     method's success cases, failure return codes, edge cases,
     corner cases, and external/private dependencies — the skill
     forces this analysis pass.
   - **Integration tests** — `/tizen-integration-test`. Use for
     anything under `integ_tests/` — real syscalls, sockets,
     dbus, sqlite, glib mainloop, cross-process proxy↔stub flows,
     `%package integtests` RPM. No mocks.
   - **Smoke tests** — `/tizen-smoke-test`. Use for a post-install
     `run-smoketest.sh` BAT path: install the RPM, confirm the
     binary boots and the most critical end-to-end path returns 0.
     Narrow and fast — not exhaustive coverage.

2. **Build and run.** Use GBS — host-side `cmake/ctest` is not the
   project's build contract; the Tizen toolchain, RPM-installed
   deps, and `%check` wiring live inside GBS:
   ```
   gbs build -A x86_64 --include-all
   ```
   Inspect `%check` in the produced `.build.log` for
   `UNITTEST_EXIT=`, `INTEGRATION_EXIT=`, `SMOKE_EXIT=` and the
   gtest summary lines for the suite you just touched. To narrow
   the failing-test loop while iterating, the authoring skill you
   picked in step 1 documents the per-suite gtest filter / spec
   knob it expects.
3. **Confirm red for the right reason.** If the test "passes
   accidentally" or fails for an unrelated build issue, stop and
   debug — don't push forward.
4. **Commit RED.**
   ```
   test(<scope>): add failing tests for <behavior>
   ```
5. **Implement minimal change to green.** No additional features. No
   "while I'm here" cleanups. Pure delta.
6. **Re-run the full GBS `%check` suite** (not just the new test).
   Confirm no regression in unit / integration / smoke exit codes.
7. **Commit GREEN.**
   ```
   <type>(<scope>): <verb> <object>
   ```
   Where `<type>` is `feat | fix | refactor | perf | build | test`.
8. **Optional REFACTOR cycle** with tests still green. Commit only if
   substantive (≥ 5 lines, or restructuring that changes intent).

## Rules

- **R-TDD applies even for new files.** A new test file with the
  fixture wired up but no `EXPECT` calls is *not* a red — it's a
  green that asserts nothing. Add at least one expectation per
  cycle.
- **R-NO-EX (and class-equivalent rules)** — never reference any
  subtree the project rules mark as out-of-scope from new test
  fixtures. If existing fixtures pull it in transitively, document
  it but don't expand the dependency.
- **R-ABI** — public ABI is frozen. Inspect public headers carefully.
  If a refactor *needs* an ABI-affecting change, STOP and bounce to
  architect with reason.
- **R-COMMIT-SCOPE** — one scope per commit, lowercase, hyphenated
  module names.
- **Test ergonomics** — reuse existing mocks under `tests/mock/`.
  If a needed mock doesn't exist, add it to that directory in the
  same RED commit (it's part of "what makes the test possible").
- **Failure-case coverage** — every test must include at least one
  failure path: NULL arg, OOM, DB busy, perm denied, socket fail,
  malformed bundle, etc. (per project plan §3 constraint #2).

## Bounces

- Plan ambiguous → bounce to `/planner`.
- Design wrong → bounce to `/architect`.
- GBS build broke and the cause isn't obvious from one screen of
  log (cascading `make[N]: *** Error`, missing-include /
  undefined-reference, dep-resolve failure, network timeout) →
  bounce to `/debugger` for classification first; act on its
  `bounce_to:` verdict.
- Reviewer found bugs → take incoming bounce; re-enter at a fresh
  cycle.
- Tester found regression → take incoming bounce; first check that
  the regression is yours (use `git bisect HEAD~5..HEAD` if needed).

## Stop conditions

- All cycles in the plan completed.
- Full GBS `%check` green (`UNITTEST_EXIT=0`, `INTEGRATION_EXIT=0`,
  `SMOKE_EXIT=0`) at the last commit.
- Hand off to `/tester`.

## Failure modes

- Skipping the RED commit (just writing test + impl together).
- Committing on a red.
- Mixing scopes in one commit.
- Editing files the design didn't authorize.
- Touching out-of-scope subtrees that the project rules enumerate.
