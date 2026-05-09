---
name: tizen-refactoring
description: Drive the multi-agent per-task refactoring pipeline end-to-end for any Tizen AppFW C/C++ package — refiner → planner → architect → developer → tester → reviewer → committer with supervisor checkpoints between every stage and a debugger side-channel for GBS build failures. Invoke once and it loops until the active task is committed or escalates. Use whenever the user wants to "execute the next task", "run the per-task pipeline", "refactor <package>", "advance to the next task", "리팩토링 진행해줘", "다음 task 실행", "release 커밋 만들기", or any cross-stage refactor work on a Tizen package under `~/tizen/gerrit/`. Triggers on /tizen-refactoring.
---

# `/tizen-refactoring` — Drive the per-task pipeline end-to-end

This is the **director** for the multi-agent refactoring pipeline.
One invocation runs the loop: refiner → planner → architect →
developer → tester → reviewer → committer, with `/supervisor`
checkpoints between every stage and a `/debugger` side-channel for
GBS build failures. It keeps looping until the active task either
lands a Release-ready commit set or escalates to the user.

The role skills do the work; this skill *sequences* them, infers
where in the pipeline the project currently sits, routes bounces,
and enforces four non-negotiable flows:

1. **GBS build break → `/debugger` first**, then route per its
   `bounce_to:`. Never debug a cascade by guessing.
2. **Pre-release test gate** — no `Release version X.Y.Z`
   commit without a recorded green `gbs build --include-all`
   run on the exact tip the bump will sit on.
3. **Lock-in baseline tests first** (R-LOCK-IN-BASELINE) —
   every public + internal API of the touched module gets a
   test that asserts current behavior *before* any refactor
   commit on that scope.
4. **Scenario coverage check** (R-API-SCENARIO-COVERAGE) —
   every (symbol, scenario) pair in the planner's `### API
   surface` has a corresponding `EXPECT_*` / `ASSERT_*` in the
   diff before the developer hands off to the tester.

Read alongside the project's `rules.md`, `workflow.md`, and the
per-role skills installed at `~/.claude/skills/<role>/`.

---

## How this skill drives the loop

When you invoke `/tizen-refactoring`, follow this algorithm
literally. Each numbered step is one tool action.

### Step 0 — Locate the project and active task

```
1. cwd should be a Tizen package directory under ~/tizen/gerrit/
   (e.g. ~/tizen/gerrit/notification, /data-provider-master, …).
   If you're at the repo root, ask the user which package.

2. PLANS = "<repo-root>/refactoring-plans"
   Read PLANS/06_progress/STATE.md. The cursor line tells you
   the active task slug (e.g. "01-error-coverage").
   If STATE.md is missing or doesn't point to a task, STOP and
   ask the user which task to run.

3. LOG = PLANS/05_logs/<NN>-<slug>.md
   Read LOG (or note that it doesn't exist yet — first time
   running this task).

4. PKG = the package name (e.g. "notification") inferred from
   the package directory name.
```

### Step 1 — Determine which role is up next

Look at the **last `## …` section** in `LOG`. That tells you
which role just produced output. The next role is determined
by the table:

| Last section in LOG | Next role | Why |
|---|---|---|
| (file empty / missing) | `/supervisor` | entry checkpoint |
| `## Supervisor checkpoints` ending in `next_stage: <X>` | `/<X>` | supervisor told you |
| `## Refined prompt` | `/supervisor` | post-refiner check |
| `## Execution plan` | `/supervisor` | post-planner check |
| `## Design` | `/supervisor` | post-architect check |
| `## Developer log` | `/tester` | run verification (supervisor implicit before/after) |
| `## Tester report` ending in PASS | `/reviewer` | diff review |
| `## Tester report` ending in FAIL with parseable `[ FAILED ]` | `/developer` | clean test fail — code bug |
| `## Tester report` ending in FAIL with build-side break | `/debugger` | classify before fixing |
| `## Debugger report` | the `bounce_to:` named there | side-channel resolved |
| `## Review report` ending in APPROVE | `/committer` | commit |
| `## Review report` ending in REQUEST CHANGES | `/developer` | fix and re-cycle |
| `## Review report` ending in ESCALATE | `/architect` | redesign |
| `## Commits` (work-unit) | `/supervisor` | exit checkpoint |
| `## Commits` (Release) | exit — task complete | done |

The supervisor's verdict line `next_stage: <X>` is the
authoritative routing instruction whenever it's the most recent
section. Trust it over the table above.

### Step 2 — Invoke the next role

Use the `Skill` tool with `skill: "<role-name>"` (no leading slash)
and an `args` payload that points at the active log file:

```
Skill(skill="<role>", args="LOG=<absolute path to LOG file>")
```

The role skill reads the log, does its work, appends its
section, and returns. **Do not interleave your own analysis
between roles** — let each role own its section.

### Step 3 — Apply the four critical flows

The flows below override the simple table when they apply.
Check each one *before* invoking the next role:

#### Flow A — GBS build break routes through `/debugger` first

If the role you're about to invoke is `/developer` because the
tester or developer hit a GBS / `%check` break, **first** invoke
`/debugger`. The signal:

- The most recent `## Tester report` or `## Developer log`
  ends with a non-zero exit that did NOT produce a parseable
  `[ FAILED ]` gtest line, OR
- `gbs build` output captured under the log shows
  `make[N]: *** Error`, `error: Failed build dependencies`,
  `undefined reference`, `CMake Error`, or a Type 1..6 pattern
  from `/tizen-build-debugger`.

Invoke `/debugger`, read its `bounce_to:` line in the resulting
`## Debugger report`, then route to that role on the next
iteration. Do not loop debugger → debugger.

#### Flow B — Pre-release test gate before any Release commit

When the next role is `/committer` AND the task is the last
task of a release window (i.e. the to-be-authored commit will
be `Release version X.Y.Z`), enforce R-RELEASE-TEST-GATE before
the Release commit lands:

```
1. Bash: gbs build -A x86_64 --include-all
   (this needs sudo — see R-SUDO; pause and ask the user to
    run it via `! gbs build …` in the chat prompt if the
    sandbox can't.)

2. Read the .build.log for UNITTEST_EXIT=, INTEGRATION_EXIT=,
   SMOKE_EXIT=. ALL three must be 0.

3. Append `## Pre-release test gate` to LOG with:
     - tip SHA, timestamp,
     - the three exit codes,
     - the gtest summary line for each suite.

4. If any non-zero exit:
     - if it's a clean test fail → bounce to /developer
     - if it's a build break → bounce to /debugger first
     - if it's a known infra failure listed under
       06_progress/STATE.md `known_infra_failures` →
       record + continue.

5. Only after the gate is recorded green may /committer be
   invoked to author the Release commit.
```

#### Flow C — Lock-in cycle FIRST inside `/developer`

When invoking `/developer` for the *first* cycle of a task that
will touch any `.c` / `.cc` / installed header file, pass
`stage=lock-in` so the developer skill knows to write baseline
tests for every (symbol, scenario) pair in the planner's
`### API surface` and commit them as their own work-unit
commits BEFORE any refactor cycle:

```
Skill(skill="developer", args="LOG=<path>; stage=lock-in")
```

After the lock-in cycle is green, subsequent `/developer`
invocations on the same task implicitly run `stage=refactor`
cycles. Refactor commits that break a baseline test = regression
→ bounce to `/developer` (do **not** edit the baseline test).

The developer's role skill enforces R-LOCK-IN-BASELINE; this
skill's job is to make sure the lock-in cycle precedes any
refactor cycle in `git log --oneline` order.

#### Flow D — Scenario coverage check at developer→tester handoff

After `/developer` returns and before invoking `/tester`,
verify R-API-SCENARIO-COVERAGE locally:

```
1. Read § API surface from ## Execution plan.
2. Read the diff: git diff <prev-tip>..HEAD on test files
   touched in this task.
3. For every (symbol, scenario) pair in § API surface, grep
   the diff for an EXPECT_* / ASSERT_* that targets the
   symbol AND exercises the scenario.
4. If any pair is missing AND not marked `n/a — <reason>` in
   § API surface → bounce to /developer with the missing
   pairs listed in the bounce. Do not invoke /tester.
```

The supervisor's after-developer checkpoint also enforces this;
this skill catches it earlier so you don't burn a tester run on
incomplete coverage.

### Step 4 — Loop

After invoking the next role (and applying flow overrides),
re-read `LOG` and go back to Step 1. Keep looping until one of
the stop conditions hits.

---

## Stop conditions

The loop ends when **any** of these is true. Communicate the
condition to the user explicitly.

- **Task complete.** The supervisor's exit checkpoint passed:
  `## Commits` exists, `06_progress/STATE.md` advanced to the
  next task, and (if the commit closed a release window) the
  Release commit is present and the pre-release test gate is
  recorded green.
- **Escalation.** The same role bounced ≥ 3 times on this task
  without progress. Stop and surface the bounce history to the
  user with a one-paragraph summary; do not loop forever.
- **User-input gate.** A role's output requires a user decision
  (e.g. an "Open question" in `## Refined prompt`, a Type 1
  GBS dep failure that needs a `BuildRequires` policy call).
  Stop, surface the question, wait.
- **Sudo gate.** A required action needs interactive sudo
  (typically `gbs build` for the pre-release gate) and the
  Bash sandbox can't get a password (R-SUDO). Stop, ask the
  user to run the captured command via `! …` in the chat
  prompt, then resume on the next invocation.

When stopping, write a short closing note to the user that
explains the condition and (if applicable) what action you need
from them. Do not modify production code as a "shortcut" to
unblock — the role skills own all production edits.

---

## Resuming mid-pipeline

If the user invokes `/tizen-refactoring` again after a stop,
**do not start over** — the loop is designed to resume:

1. Re-run Step 0 to locate the task.
2. Run Step 1 to read the last section of `LOG`. The most
   recent supervisor `next_stage: <X>` line (if any) is the
   resume point.
3. Continue the loop from there.

This means the active log file is the durable state. As long as
each role faithfully appends its section, the pipeline can be
interrupted and resumed across sessions.

---

## What this skill does NOT do

- **It does not write code.** Production edits are the
  developer role's job. Test edits are the developer role's
  job. The orchestrator only sequences and gates.
- **It does not author commits.** Committer role does.
- **It does not classify build failures.** Debugger role does.
- **It does not bypass the supervisor.** Every stage transition
  goes through `/supervisor` either explicitly (the rows above)
  or implicitly (the role skill's stop condition itself hands
  back to the orchestrator, which always re-checks Step 1
  before invoking the next role).

---

## Tooling map (delegation references)

| Trigger | Role skill | Owns |
|---|---|---|
| `/refiner` | refining | `## Refined prompt` |
| `/planner` | planning (incl. `### API surface`) | `## Execution plan` |
| `/architect` | OOAD design | `## Design` (or waiver) |
| `/developer` | TDD impl, lock-in cycle FIRST | `## Developer log` |
| `/tester` | independent GBS verification | `## Tester report` |
| `/reviewer` | diff review, scenario coverage audit | `## Review report` |
| `/committer` | stage + commit, pre-release gate | `## Commits` (+ `## Pre-release test gate`) |
| `/supervisor` | cross-stage gate, rewinds | `## Supervisor checkpoints` |
| `/debugger` | GBS / `%check` failure classification | `## Debugger report` (side-channel) |

| Capability | Tizen skill (consult, don't reinvent) |
|---|---|
| Author unit tests | `/tizen-gtest-unit-test` |
| Author integration tests | `/tizen-integration-test` |
| Author smoke tests | `/tizen-smoke-test` |
| Coverage measurement | `/tizen-coverage` |
| GBS log analysis | `/tizen-build-debugger` |
| On-device install + run | `/tizen-sdb` |
| GBS configuration | `/tizen-gbs` |
| Gerrit / review.tizen.org | `/tizen-gerrit` |

The role skills already delegate to these — you don't normally
need to invoke them directly from the orchestrator.

---

## Example one-shot transcript (concise)

```
User:    /tizen-refactoring
Step 0:  STATE.md → active task = 02-error-impl
         LOG = refactoring-plans/05_logs/02-error-impl.md (empty)
Step 1:  LOG empty → next = /supervisor (entry checkpoint)
Step 2:  Skill(supervisor) → "PASS, next_stage: refiner"
Step 1:  next_stage = refiner → /refiner
Step 2:  Skill(refiner) → appends ## Refined prompt
Step 1:  next_stage = supervisor (post-refiner) → /supervisor
Step 2:  Skill(supervisor) → "PASS, next_stage: planner"
Step 2:  Skill(planner) → appends ## Execution plan with § API surface
Step 2:  Skill(supervisor) → "PASS, next_stage: architect"
Step 2:  Skill(architect) → appends ## Design
Step 2:  Skill(supervisor) → "PASS, next_stage: developer"
Flow C:  first developer call on this task → stage=lock-in
Step 2:  Skill(developer, "stage=lock-in") → lock-in cycle, baseline GREEN
Flow D:  scenario coverage check passes
Step 2:  Skill(developer, "stage=refactor") → refactor cycle GREEN
Step 2:  Skill(tester) → ## Tester report PASS
Step 2:  Skill(reviewer) → APPROVE
Step 2:  Skill(committer) → ## Commits
         (not a release window — skip Flow B)
Step 2:  Skill(supervisor) → exit checkpoint PASS, STATE.md advanced
STOP:    Task complete. Next task in STATE.md is 03-db-tests.
```

The whole loop above is one `/tizen-refactoring` invocation. The
user types one slash command; the orchestrator drives until the
task is done or hits a stop condition.

---

## Failure modes

- **Forgetting Flow A.** Routing a build break straight to
  `/developer` wastes a TDD cycle on cascade noise. First
  error wins; classify via `/debugger` first.
- **Forgetting Flow B.** Authoring `Release version X.Y.Z`
  without recording the pre-release gate is the single most
  common workflow violation, and is treated like an ABI break —
  the Release commit must be reverted.
- **Forgetting Flow C.** Starting refactor cycles before the
  lock-in cycle is green leaves the refactor undefended; any
  "no behavior change" claim becomes unfalsifiable.
- **Forgetting Flow D.** Sending the developer's diff to the
  tester with missing scenario coverage means the tester runs
  on an incomplete contract — the supervisor will bounce, but
  earlier is cheaper.
- **Treating supervisor as optional.** Skipping the supervisor
  checkpoint between two stages because "the prior stage's
  output looked fine" is how silent rewinds happen.
- **Looping the same bounce.** If the same role bounces ≥ 3
  times on one task, escalate to the user. Don't loop forever.
- **Editing the log out-of-band.** The active log file is the
  resume anchor. The orchestrator MUST NOT add or remove
  sections; only the role skills append their owned sections.
