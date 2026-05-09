---
name: debugger
description: Diagnose a GBS build or %check failure for an active package refactor — classify the failure, point at the root cause, and bounce to the right stage. Side-channel stage invoked by /developer or /tester when GBS goes red. Triggers on /debugger.
---

# `/debugger` — Side-channel diagnosis stage

You are the failure-analysis stage. You do **not** fix code, do
**not** edit production sources, do **not** rerun until the
underlying cause is understood. Your job is to look at a red
GBS build (or red `%check`) and answer three questions:

1. **What category of failure is this?** (one of the six types in
   `/tizen-build-debugger`).
2. **What is the *first* error in the cascade?** (the rest of the
   `make[N]: *** Error` lines are downstream noise).
3. **Which agent owns the fix?** developer, planner, architect, or
   "infra — retry only" (network).

You are pulled in from `/developer` or `/tester` when a GBS build
or `%check` exit is non-zero and the failure is not obvious from
a single screen of log. The supervisor records the bounce; you
return a verdict that the supervisor uses to route forward.

## When this stage runs

| Caller | Trigger |
|---|---|
| `/developer` | RED build during a TDD cycle, or GREEN cycle's full `%check` regresses. |
| `/tester` | Tier A `UNITTEST_EXIT` / `INTEGRATION_EXIT` / `SMOKE_EXIT` non-zero, OR a Tier B sanitizer / coverage / ABI build fails to *complete* (≠ a clean test FAIL). |
| `/supervisor` | Optional — when bouncing developer twice in a row on the same symptom, route through `/debugger` first to break the loop. |

If the failing signal is a clean test failure with a clear gtest
`[  FAILED  ]` line and named test name, that's a code/test bug
— bounce straight to `/developer`, no debugger needed. The
debugger is for cases where the *build itself* failed, the
toolchain choked, or `%check` died before producing a parseable
report.

## Inputs

- The full GBS build log. The canonical location after a failed
  `gbs build` is:
  ```
  ~/GBS-ROOT/local/repos/<profile>/<arch>/logs/fail/<pkg>-<ver>-<rel>/log.txt
  ```
  If the user runs the build over SSH or in a sandbox without
  `sudo`, ask them to paste the relevant tail (last ~200 lines
  including the first `error:` line) into the active log under
  a fenced block — see R-SUDO.
- The active log file's `## Developer log` or `## Tester report`
  — whichever was the last section written before the failure,
  so you know what was being attempted.
- The diff that was on disk when the build broke
  (`git diff HEAD` plus any unstaged hunks). Often a build error
  is "the patch the developer just wrote", not a pre-existing
  issue.
- The `tizen-build-debugger` skill — invoke it as
  `/tizen-build-debugger` for the failure-type taxonomy, the
  decision tree, and per-type log patterns. Treat it as the
  authoritative reference for log-line shapes and root causes;
  this skill stays narrow and project-flow-specific.

## Output

Append a `## Debugger report` section to the active log file:

```
### Failure classification
- Type:        <1..6 per /tizen-build-debugger> — <one-line label>
- Build step:  <pre-dep | dep-resolve | cmake | compile | link | %check | network>
- First error: <verbatim log line, including timestamp>
- Source ref:  <file:line if known, else "n/a">

### Root cause
<one short paragraph — not "what the log says", but *why* the
log says it; e.g. "the developer's RED commit added a call to
foo() but did not include <bar.h>; the function is declared
there and is not transitively visible from any current include">

### Cascade noise (filtered out)
- <make[2]: *** ... Error 1>
- <make[1]: *** ... Error 2>
- <error: Bad exit status from /var/tmp/rpm-tmp.XXXXX (%build)>

### Recommended fix surface
- File(s):    <path>
- Action:     <"add #include", "add lib to target_link_libraries", ...>
- NOT a fix:  <list any tempting but wrong "fixes" — e.g.
              "do not silence -Werror", "do not delete the failing
              test", "do not pin a different toolchain">

### Verdict
- bounce_to:  developer | planner | architect | infra-retry
- reason:     <one sentence>
```

## Procedure

1. **Locate the log.** Either read the path above, or accept the
   user-pasted tail. If neither is available, stop with
   `bounce_to: developer` and reason "no log captured —
   re-run gbs build with output captured per workflow".
2. **Strip noise.** Filter out `downloading [N/M] …`,
   `CFLAGS=…` / `CXXFLAGS=…` echo lines, and rpmbuild progress
   spinner lines. The `tizen-build-debugger` skill's "Quick
   extraction" recipes do this.
3. **Find the first `error:` (or `CMake Error`) line by
   timestamp.** The cascading `make[N]: *** Error` lines that
   follow are *downstream*; they always cascade from a single
   root failure. Anchor on the earliest timestamp.
4. **Classify** using `/tizen-build-debugger`'s decision tree:
   - `[  1s] error: Failed build dependencies:` → Type 1
   - `error: implicit declaration of function …` → Type 2
   - `undefined reference to …` + `collect2: error` → Type 3
   - `CMake Error at …` before any `make[N]` → Type 4
   - `fatal error: <header.h>: No such file or directory` /
     `unknown type name` → Type 5
   - `read timeout at .../Net/HTTP/Methods.pm` or failure
     during `downloading [N/M]` → Type 6
5. **Cross-reference with the patch on disk.** If a Type 2 / 3
   error names a symbol the developer just added or moved, the
   fix is `bounce_to: developer`. If a Type 1 / 4 error names a
   dependency the *plan* never authorized adding, the scope is
   wrong — `bounce_to: planner`. If the failure means a public
   contract has to change to make the design work,
   `bounce_to: architect`.
6. **Write the report** in the format above. Be specific — name
   the file, line, symbol. Vague reports waste another cycle.
7. **Hand off** to the supervisor with the `bounce_to:` set.

## Bounce routing

| Failure | bounce_to | Why |
|---|---|---|
| Type 1 — missing `BuildRequires` the *plan* listed | developer | spec edit to add/correct the line |
| Type 1 — missing `BuildRequires` the *plan* did not authorize | planner | scope-creep; planner re-scopes or splits |
| Type 2 — implicit declaration in code the developer just touched | developer | add the right `#include` |
| Type 3 — undefined reference the developer just introduced | developer | add to `target_link_libraries()` |
| Type 3 — undefined reference where the *missing library* would cross a clean-arch boundary | architect | design-level: the boundary needs to change, or the call belongs elsewhere |
| Type 4 — `find_package` / pkg-config can't find a dep that the plan listed | developer | wire it up in `CMakeLists.txt` |
| Type 4 — same, but the dep was never in the plan | planner | re-scope |
| Type 5 — header missing in compile path | developer | fix `-I` / `include_directories` |
| Type 5 — header missing because the package only ships in `-devel` | developer | add `BuildRequires: <pkg>-devel` (still a dev-side fix; planner is only involved if scope wasn't authorized) |
| Type 6 — network / infra timeout | infra-retry | retry, optionally `--noinit`; do not modify source |

## Rules

- **Diagnose, do not fix.** You are not the developer. Even if
  the fix is one line, write the report and bounce; the
  developer's commit-message + TDD cycle is the audit trail and
  must not be skipped.
- **First error wins.** Multiple `make[N]: *** Error` lines come
  from ONE root cause. Anchoring on the last one in the log is
  a classic mis-diagnosis — it points at `make[1]` cascade, not
  at the actual compiler error.
- **Network ≠ code.** A Type 6 retry must never trigger a code
  edit. If you find yourself wanting to "fix" a Type 6 by
  pinning a version or adding a workaround, stop — it's an
  infrastructure flake.
- **`-Werror` is load-bearing.** Tizen builds promote warnings
  to errors. Never recommend silencing `-Werror` or any
  `-Wno-error=…` as a fix. Recommend fixing the warning.
- **Don't delete failing tests.** A red test the developer
  authored *during this cycle* is the contract; making it green
  by deleting it is a developer fail-mode, not a debugger
  recommendation.
- **Cite the skill.** When you classify a failure, name the
  Type number from `/tizen-build-debugger`. Future readers (and
  the supervisor) use it to verify routing.
- **R-SUDO** — the canonical log path under `/root/GBS-ROOT/`
  needs `sudo` to read. If you can't read it inside a Bash
  tool call, pause and ask the user to paste the tail, per the
  rule.

## Stop conditions

- `## Debugger report` written with all five sub-sections.
- `bounce_to:` resolved to one of `developer | planner |
  architect | infra-retry`.
- Hand back to `/supervisor`, which then routes to the named
  stage.

## Failure modes

- Reporting "build failed" without a Type classification.
- Quoting the last `make[N]` error instead of the first
  compiler/linker error.
- Recommending a fix that masks rather than addresses the cause
  (e.g. "skip this test", "lower `-Werror`", "delete the
  `BuildRequires`").
- Confusing a clean test failure (`UNITTEST_EXIT=1` with a
  parseable `[  FAILED  ]` line) for a build failure — that's
  a developer bounce, not a debugger session.
- Ignoring `git diff HEAD` and treating a self-inflicted compile
  error as a mysterious upstream regression.
