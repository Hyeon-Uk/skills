---
name: tizen-coverage
description: Measure unit-test code coverage of Tizen AppFW C/C++ packages (notification, widget-service, app-control, tizen-core, package-manager, preference, watchface-complication, appcore-watch, data-control, wgt-manifest-handlers, etc.) using `gbs build --define "gcov 1"`. Use whenever the user asks to "measure coverage", "get coverage", "run lcov / gcov", "view per-file coverage", "line/method coverage", "커버리지 측정", "커버리지 산출", "라인 커버리지", "함수 커버리지", "gcov 빌드", "coverage RPM", or otherwise wants to know how well the unit tests exercise the production source. Trigger even when the user does not say "skill". Covers: how to invoke the gcov build via `gbs`, where the produced HTML report and `.gcno`/`.gcda` files land, how to read per-file and line/function coverage, and the most common error modes when `--define "gcov 1"` is set (missing `lcov` BuildRequires, `-Werror=coverage-mismatch`, lcov version skew vs gcc, `%check` test failures bringing down the whole build). Hard rule baked into the skill: any temporary file edits required to make the gcov build succeed are applied LOCALLY ONLY via `gbs build --include-all` and must NEVER be committed — the gcov path is a measurement, not a production change.
---

# Tizen Coverage Measurement

Coverage tells you which lines and which functions of your production code your unit-test suite actually exercised. In Tizen AppFW packages it's wired through the `.spec` file: when you build with `--define "gcov 1"`, the package compiles with `-fprofile-arcs -ftest-coverage`, runs its unit tests during `%check`, collects results with `lcov`, and ships an HTML report (and the raw `.gcno` graph files) inside a `<pkg>-gcov` sub-RPM.

This skill encodes the end-to-end workflow: invocation → artifact locations → how to view per-file and line/function coverage → recovery when the build breaks.

The whole flow is `gbs`-driven. Do not run `cmake`/`make` locally to "see coverage" — coverage measurement only makes sense against the same toolchain and `%check` step that the device build uses.

---

## 1. When this skill applies

Trigger on any of:
- The user wants to know **what percentage of lines/functions** are covered by their tests.
- The user mentions `gcov`, `lcov`, `genhtml`, `--coverage`, `--define "gcov 1"`, `*.gcno`, `*.gcda`, `coverage report`, `<pkg>-gcov` RPM.
- The user asks for **per-file coverage** ("which files are weakest?", "show me coverage for `notification.c`").
- The user asks how to **run / view / interpret** the coverage report on a Tizen package.
- The user is troubleshooting a failing gcov build (`--define "gcov 1"` produces a different error than the regular build).

Skip if the user wants:
- A general bug audit (use `analyze-c-package`).
- To author tests (use a unit-test or scenario-design skill).
- To run coverage on a non-Tizen project (gcov tooling is similar but the gbs / `.spec` plumbing here is Tizen-specific).

---

## 2. Pre-flight: confirm the package supports gcov

Before invoking the build, open the package's `.spec` and confirm the gcov gate exists. Almost every AppFW package follows the same pattern — look for these blocks:

```spec
# 1. BuildRequires
%if 0%{?gcov:1}
BuildRequires:  lcov
%endif

# 2. Sub-package declaration
%if 0%{?gcov:1}
%package gcov
Summary:  <pkg>(gcov)
%description gcov
gcov objects of <pkg>
%endif

# 3. CFLAGS injection
%if 0%{?gcov:1}
export CFLAGS+=" -fprofile-arcs -ftest-coverage"
export CXXFLAGS+=" -fprofile-arcs -ftest-coverage"
export LDFLAGS+=" -lgcov"
%endif

# 4. lcov capture in %check
%check
...
ctest -V
%if 0%{?gcov:1}
lcov -c --ignore-errors mismatch,graph,unused --no-external -q -d . -o <pkg>.info
genhtml <pkg>.info -o <pkg>.out
zip -r <pkg>.zip <pkg>.out
install -m 0644 <pkg>.zip %{buildroot}%{_datadir}/gcov/obj/<pkg>.zip
%endif

# 5. .gcno harvest in %install
%if 0%{?gcov:1}
builddir=$(basename $PWD)
gcno_obj_dir=%{buildroot}%{_datadir}/gcov/obj/%{name}/"$builddir"
mkdir -p "$gcno_obj_dir"
find . -name '*.gcno' -exec cp --parents '{}' "$gcno_obj_dir" ';'
%endif

# 6. %files for the gcov sub-package
%if 0%{?gcov:1}
%files gcov
%{_datadir}/gcov/obj/*
%endif
```

If any of these blocks are missing, the package does not yet support `--define "gcov 1"` and you should tell the user. Adding gcov support is a real `.spec` change that should be a separate, committable patch — *not* something to slip in via `--include-all`.

Tip: a fast way to check is `grep -nE 'gcov|fprofile-arcs' packaging/*.spec`.

---

## 3. Build invocation

From the package's source directory:

```bash
gbs build -A <arch> --include-all --define "gcov 1" <pkg>
```

- `-A <arch>` — match the user's profile (`x86_64`, `armv7l`, `aarch64`).
- `--include-all` — include uncommitted/untracked files in the build. Required if you have local fixes for gcov-only build errors (see §6) — those fixes must NOT be committed.
- `--define "gcov 1"` — flips every `%if 0%{?gcov:1}` block in the spec.

You can also chain it with `--clean` if you suspect a dirty build root, or with `--incremental` for fast iteration on a single source change.

The build does three things differently from a normal build:
1. **Compiles with coverage flags.** Every object file gets a paired `.gcno` (control-flow graph at compile time) emitted next to it.
2. **Runs `ctest -V` in `%check`.** This produces `.gcda` files (execution counts) by actually running the unit tests against the just-built libraries.
3. **Collects + packages.** `lcov -c` merges `.gcno + .gcda` into `<pkg>.info`, `genhtml` turns that into a browsable HTML tree, the tree is zipped and installed.

If `%check` fails, the whole build fails — **even if compilation was clean**. This is a deliberate trade-off: a coverage RPM with no execution data isn't useful.

---

## 4. Where the artifacts land

After a successful build:

```
~/GBS-ROOT/local/repos/<profile>/<arch>/RPMS/
  ├── <pkg>-<ver>-<rel>.<arch>.rpm                # normal package
  ├── <pkg>-unittests-<ver>-<rel>.<arch>.rpm      # the test binary itself (if defined)
  └── <pkg>-gcov-<ver>-<rel>.<arch>.rpm           # ← this is the coverage RPM
```

Inside `<pkg>-gcov-*.rpm` (extract with `rpm2cpio <rpm> | cpio -idmv` into a temp dir):

```
usr/share/gcov/obj/
  ├── <pkg>.zip                                   # ← unzip this — HTML report
  └── <pkg>/<builddir>/                           # ← raw .gcno tree
        ├── src/notification/.../*.gcno
        ├── src/notification/.../*.o
        └── ... (mirror of build tree)
```

`<pkg>.zip` is what you actually want for human consumption. Unzip it:

```bash
mkdir -p /tmp/cov && cd /tmp/cov
rpm2cpio ~/GBS-ROOT/local/repos/*/x86_64/RPMS/<pkg>-gcov-*.rpm | cpio -idmv
unzip usr/share/gcov/obj/<pkg>.zip -d ./html
xdg-open ./html/<pkg>.out/index.html       # or: python3 -m http.server -d ./html
```

If the build never reaches `%check` (compile error) the zip is not produced and the gcov RPM is not built — see §6.

---

## 5. Reading the report

The `genhtml` output is a standard lcov HTML tree. Three views matter:

### 5.1 Summary (top-level `index.html`)
- **Lines** % — fraction of executable lines that ran during `%check`.
- **Functions** % — fraction of declared functions that were entered at least once.
- **(optionally) Branches** % — only when lcov is invoked with `--rc lcov_branch_coverage=1` (not the default in most Tizen specs).

### 5.2 Per-file (drill into a directory in the index)
Each source file gets its own row with hit/total for lines and functions, and a coloured bar. Click the file name → per-line annotated view.

To see this from the CLI without unzipping:

```bash
# directly from the .info file (much faster than rendering HTML)
lcov --list <pkg>.info                   # per-source-file table
lcov --list-full <pkg>.info | head -60   # adds branch/function detail
```

### 5.3 Per-line (file detail page)
Each line is annotated with:
- **A hit count** in the left margin (e.g. `12 :`) — how many times the line ran. Blank means not executable; `#####` means executable but never ran.
- **Color** — green (covered), red (not covered), grey (non-executable).

To extract just the uncovered lines of one file from the CLI (no browser):

```bash
# inside the unzipped html tree, grab the per-file coverage page or use lcov:
lcov --extract <pkg>.info '*/notification.c' -o /tmp/just_one.info
genhtml /tmp/just_one.info -o /tmp/one_file_html
# OR: parse .info directly — lines starting with DA: are line execution counts
grep '^DA:' <pkg>.info | awk -F'[:,]' '$3==0 {print $2}'   # uncovered line numbers
```

### 5.4 Per-function coverage

`lcov` records function-entry counts as `FN:`/`FNDA:` records in the `.info` file:

```
FN:<line>,<function-name>          # declared
FNDA:<call-count>,<function-name>  # times entered (0 = uncovered function)
```

Quick CLI extraction of "all functions that were never called":

```bash
awk -F: '/^FNDA:0,/{sub(/^FNDA:0,/,""); print}' <pkg>.info | sort -u
```

The HTML report has a "Function Coverage" toggle on each file page that surfaces the same data with line numbers — useful when you want to know which named function a coverage gap belongs to.

---

## 6. Common errors with `--define "gcov 1"` and how to recover

The single rule that overrides everything else: **if recovery requires a temporary file edit, that edit is local-only and must never be committed.** The gcov path is a measurement, not a production change. Use `gbs build --include-all` so the local edit is picked up by the build, and revert (or `git stash` / `git restore`) the moment you're done collecting numbers. If the issue is real and structural (e.g. the spec is genuinely missing a BuildRequires), that fix is a *separate* commit reviewed on its own merits — not bundled with anything else.

Below are the failure modes you will most often see, and the recovery for each.

### 6.1 `BuildRequires: lcov` not satisfied

Symptom (in the `prebuild` / dep-resolution phase):
```
Failed build dependencies:
    lcov is needed by <pkg>-...
```

Cause: the `BuildRequires: lcov` block is gated behind `%if 0%{?gcov:1}` correctly, but the GBS local repo cache doesn't have `lcov` yet, OR an older spec just didn't add it.

Recovery:
- First refresh the cache: `gbs build -A <arch> --refresh-repos --define "gcov 1" <pkg>` once.
- If the spec really doesn't list `lcov`, that is a structural fix — open a real, reviewable patch. Do not paper over it with `--include-all`.

### 6.2 `-Werror=coverage-mismatch` after a partial recompile

Symptom (during compile):
```
error: coverage mismatch for function 'foo' while reading counter ...
[-Werror=coverage-mismatch]
```

Cause: a previous gcov build left `.gcda` files in the build root that no longer match the (now re-edited) source.

Recovery:
- `gbs build --clean -A <arch> --include-all --define "gcov 1" <pkg>` — clean build root and try again.
- This is a transient state, not a code or spec issue. Nothing to commit, nothing to patch.

### 6.3 `%check` fails (one or more unit tests fail under coverage)

Symptom:
```
The following tests FAILED:
  1 - notification-unittests (Failed)
error: Bad exit status from /var/tmp/rpm-tmp.XXXX (%check)
```

This is the most common gcov-only failure: tests pass at `-O2` but fail under coverage flags due to inlining differences, timing changes, or struct-layout shifts. The package's `lcov` capture step never runs, so no `.info` file and no gcov RPM.

Recovery options, in order of preference:
1. **Read the failure first.** Look at `~/GBS-ROOT/local/BUILD-ROOTS/scratch.<arch>.0/home/abuild/rpmbuild/BUILD/<pkg>-<ver>/Testing/Temporary/LastTest.log` — it has the actual test output.
2. **Fix the test, not the spec.** If the test is genuinely flaky under coverage, the fix is a real test patch reviewed on its own merits — *that* is committable.
3. **If you genuinely just need the partial coverage data right now** (e.g. to triage which files are uncovered), patch the spec *locally* to make `%check` non-fatal:
   ```
   ctest -V || true                    # only locally, never committed
   ```
   or split the failing test off:
   ```
   ctest -V -E '<failing-test-name>' || true
   ```
   Apply the change to your working tree, run `gbs build --include-all --define "gcov 1" <pkg>`, capture the report, then **revert the change** with `git restore packaging/<pkg>.spec`. Do not commit. This is the textbook case for `--include-all`.

### 6.4 `lcov` errors: "geninfo: ERROR: mismatched end line" / "negative counter" / "graph file ... has changed"

Symptom (during `lcov -c`):
```
geninfo: ERROR: ... mismatched end line for ...
```
or
```
geninfo: WARNING: cannot find an entry for ... in .gcno file
```

Cause: gcc and lcov version skew. The Tizen builder's `lcov` may be older/newer than what the gcc that produced the `.gcno` expects. The Tizen spec already passes `--ignore-errors mismatch,graph,unused` to soften this, but new error categories appear with newer gcc.

Recovery:
1. Check the lcov version in the build root: look for `lcov` in BuildRequires resolution log.
2. If a new error category is the blocker, **temporarily** widen the `--ignore-errors` list in the spec, e.g. `--ignore-errors mismatch,graph,unused,inconsistent,corrupt`. Apply via `--include-all`, capture the report, revert.
3. If the failure is consistent across many packages, the right fix is to bump the `lcov` BuildRequires version or report upstream — separate commit.

### 6.5 `*.gcda` files written to a read-only path on the device

Symptom (only when running an installed gcov RPM on a device, not during the build):
```
profiling: /usr/lib/.../foo.gcda: Cannot open
```

Cause: gcc's instrumented binary writes `.gcda` next to `.gcno` by default, but on the device that path is read-only.

Recovery:
- Set `GCOV_PREFIX` and `GCOV_PREFIX_STRIP` environment variables before running the test on-device, redirecting `.gcda` to a writable directory:
  ```bash
  export GCOV_PREFIX=/tmp/gcov_data
  export GCOV_PREFIX_STRIP=4
  ```
- Pull the resulting `/tmp/gcov_data` tree back to the host via `sdb`, then run `lcov -c --no-external -d /path/to/.gcno+gcda -o pkg.info` on the host.
- This is a runtime concern, not a build concern — no spec patch needed.

### 6.6 `find . -name '*.gcno' -exec cp --parents …` fails because there are no `.gcno` files

Symptom (during `%install`):
```
find: cannot copy ... no .gcno files
```
followed by an empty `<pkg>-gcov` RPM (or no RPM at all).

Cause: the CFLAGS injection didn't take effect — usually because the spec installs pre-built artifacts or the build system overrides CFLAGS late.

Recovery:
- Read the compiler invocation lines in the build log: `grep -m1 'fprofile-arcs' /tmp/<your-log>`. If nothing matches, coverage flags never reached the compiler.
- The fix is structural (a spec or CMakeLists issue) — do *not* paper over it. Open a real patch.

---

## 7. The `--include-all` rule (this is the load-bearing one)

Coverage is a measurement workflow. The numbers you produce should reflect what the code *actually does in production builds* — not what it does after a half-baked workaround you smuggled into a commit. So:

- **Any spec or source edit you apply to make `--define "gcov 1"` succeed is local-only.** It exists in your working tree, not in any commit, not on any branch you push.
- **Use `gbs build --include-all`** to make gbs pick up uncommitted/untracked files. The flag exists exactly for this scenario: temporarily flowing local material into a build without altering the source-of-truth tree.
- **Revert before you finish the session.** `git restore <files>` or `git stash` is the last step in any coverage-collection task. If you find yourself wanting to keep the patch around "for next time", that is a sign it should be a real, reviewed change — file a proper commit instead.
- **Document the patch in your message to the user.** When you report coverage numbers, include a one-line note like "ran with a local `ctest -V || true` patch in `packaging/<pkg>.spec` (not committed)" so they know the numbers reflect partial-suite execution, not the full contract.

If the user pushes back ("just commit the workaround, it's fine"), explain the reason: the spec is also the production build's source of truth, and a `ctest -V || true` slipped in during a coverage session will silently let regressions ship in unrelated future builds. The safer pattern is "real fix, separately reviewed" — and then the workaround disappears.

---

## 8. Workflow summary

When the user says "measure coverage on `<pkg>`":

1. **Pre-flight**: `grep -nE 'gcov|fprofile-arcs' <pkg>/packaging/*.spec`. If the gates aren't there, stop and tell the user the package needs gcov support added (a real, separate commit).
2. **Build**: `gbs build -A <arch> --include-all --define "gcov 1" <pkg>`. Stream output; if it fails, jump to §6 to recover.
3. **Locate**: `ls ~/GBS-ROOT/local/repos/*/<arch>/RPMS/<pkg>-gcov-*.rpm`. If missing, the build did not reach lcov — see §6.3 / §6.6.
4. **Extract**: unzip the report to a tmp dir (see §4) and either open `index.html` in a browser or use `lcov --list` for a CLI summary.
5. **Report**: tell the user the overall %, the worst-covered files, and the worst-covered functions. If you applied any local patches in step 2, name them and remind the user they are NOT committed.
6. **Clean up**: `git restore` / `git stash drop` any local patches you applied. Confirm `git status` is clean before declaring done.

Reference files (read on demand):
- `references/lcov_cheatsheet.md` — exhaustive lcov / genhtml / gcov CLI recipes for per-file and per-function inspection.
- `references/spec_gcov_blocks.md` — the canonical six-block spec pattern with annotations, useful when verifying or adding gcov support to a package.
- `references/error_recovery.md` — extended troubleshooting log: each error pattern with full transcript, root cause, recovery, and whether/why a patch should be committed.

Examples:
- `examples/01_notification_full_run.md` — end-to-end run on the `notification` package: spec check → build command → artifact paths → CLI summary → per-file pivot → per-function uncovered list.
