# Error recovery playbook

Each entry follows the same shape:

> **Symptom** — exact log fragment to grep for.
> **Cause** — what's actually happening.
> **Recovery** — concrete steps.
> **Commit?** — whether the fix should be committed, applied via
>   `--include-all` only, or routed to a separate review.

The single rule that overrides all of these: **if the recovery is a
file edit, default to `--include-all` (local-only) unless the
"Commit?" line explicitly says otherwise.** Coverage is a measurement,
and bundling workarounds into commits poisons the spec for future
non-coverage builds.

---

## R1. `lcov: ERROR: (inconsistent) mismatched end line ...`

**Symptom**
```
lcov: ERROR: lcov: ERROR: (inconsistent) mismatched end line for
  _ZNxxxxx at .../test_foo.cc:51: 51 -> 53 while capturing from
  ./tests/.../test_foo.cc.gcda
        (use "lcov --ignore-errors inconsistent ..." to bypass this error)
error: Bad exit status from /var/tmp/rpm-tmp.XXXX (%check)
```

**Cause**
gcc 14+ records function end-line numbers more strictly than older
gcc; the lcov in the build root flags any line-number mismatch
between `.gcno` and the source as an error. The category is called
`inconsistent`. Most Tizen specs predate this category and only
ignore `mismatch,graph,unused`.

**Recovery**
1. Open `packaging/<pkg>.spec`.
2. Find the line: `lcov -c --ignore-errors mismatch,graph,unused ...`
3. Add `,inconsistent`:
   `lcov -c --ignore-errors mismatch,graph,unused,inconsistent ...`
4. `gbs build -A <arch> --include-all --define "gcov 1" <pkg>`.
5. After the report is collected, `git restore packaging/<pkg>.spec`.

**Commit?** No (workaround). The structural fix — bumping the
`BuildRequires: lcov` to a version that does not flag this, or
fixing the underlying line-number mismatch — is a separate,
reviewed commit.

---

## R2. `Failed build dependencies: lcov is needed by <pkg>-...`

**Symptom**
```
error: Failed build dependencies:
    lcov is needed by <pkg>-...
```

**Cause**
Either (a) the GBS local repo cache hasn't fetched `lcov` yet, or
(b) the spec really doesn't list `lcov` under `BuildRequires`.

**Recovery**
- (a) `gbs build -A <arch> --refresh-repos --define "gcov 1" <pkg>`.
- (b) Add Block 1 from `spec_gcov_blocks.md`. **This is committable**
   on its own merits.

**Commit?** (b) is a real, reviewable commit; (a) requires no edit.

---

## R3. `error: coverage mismatch for function 'foo' [-Werror=coverage-mismatch]`

**Symptom**
```
error: coverage mismatch for function 'foo' while reading counter ...
[-Werror=coverage-mismatch]
```

**Cause**
A previous gcov build's `.gcda` files in the build root no longer
match the (now-edited) source. `.gcda` knows the old function
layout, the recompiled object knows the new layout, gcc refuses to
proceed.

**Recovery**
```
gbs build --clean -A <arch> --include-all --define "gcov 1" <pkg>
```

This wipes `~/GBS-ROOT/local/BUILD-ROOTS/scratch.<arch>.0`.

**Commit?** No edit needed.

---

## R4. `%check` fails: tests pass at -O2 but fail under coverage

**Symptom**
```
The following tests FAILED:
  N - <test-name> (Failed)
error: Bad exit status from /var/tmp/rpm-tmp.XXXX (%check)
```

with `LastTest.log` showing real test failures (not lcov errors).

**Cause**
Coverage flags disable some inlining and shift timing. Tests that
happen to rely on inlining or on timing margins flake.

**Recovery — preferred**: fix the test. Don't paper over real flakes.

**Recovery — measurement-only (when you just need numbers right
now)**: edit `packaging/<pkg>.spec`, change
```
ctest -V
```
to one of:
```
ctest -V || true                                    # accept any failure
ctest -V -E '<failing-test-regex>' || true          # exclude one test
```
Then `gbs build --include-all --define "gcov 1" <pkg>`. After
collecting the report, `git restore packaging/<pkg>.spec`.

**Commit?** Workaround: NEVER. The numbers you produce reflect a
partial test run — note that explicitly when you report them. The
real test fix is a separate, reviewed commit.

---

## R5. `geninfo: WARNING: cannot find an entry for ... in .gcno file`

**Symptom**
```
geninfo: WARNING: cannot find an entry for src/foo.c in .gcno file
geninfo: ERROR: ... while reading <file>.gcno
```

**Cause**
Stale `.gcno` from a previous build. Less common than R3 but happens
when source files are renamed or moved between builds without
`--clean`.

**Recovery**
```
gbs build --clean -A <arch> --include-all --define "gcov 1" <pkg>
```

**Commit?** No edit needed.

---

## R6. Empty `<pkg>-gcov` RPM (or no RPM at all) despite "build success"

**Symptom**
RPM exists at `~/GBS-ROOT/local/repos/*/RPMS/<pkg>-gcov-*.rpm` but
contains no `<pkg>.zip`, OR the gcov RPM is missing entirely.

**Cause**
The `find . -name '*.gcno' -exec cp --parents ...` line in `%install`
didn't find anything. CFLAGS injection (Block 3) isn't actually
reaching the compiler.

**Recovery**
1. Read the build log: `grep -m1 'fprofile-arcs' /tmp/<your-build-log>`.
2. If no match, the spec's `export CFLAGS+=` line is in the wrong
   `%build` position, or the build system overrides CFLAGS late
   (some CMake configs do `set(CMAKE_CXX_FLAGS "...")` which
   discards env vars).

**Commit?** Real fix — moving the `export` earlier or patching the
CMake to honor `CMAKE_CXX_FLAGS_INIT` — is a reviewable commit.

---

## R7. On-device `.gcda` write failure

**Symptom (when running an installed gcov binary on target)**
```
profiling: /usr/lib/.../foo.gcda: Cannot open
```

**Cause**
Installed binaries try to write `.gcda` next to where `.gcno` lived
at build time (`/home/abuild/...`), which doesn't exist on the
device.

**Recovery**
```
sdb shell "GCOV_PREFIX=/tmp/gcov GCOV_PREFIX_STRIP=4 /usr/bin/<test-binary>"
sdb pull /tmp/gcov ./gcov_data
# back on host:
lcov -c --no-external -d ./gcov_data -o on_device.info
```

Pick `GCOV_PREFIX_STRIP` to drop the `/home/abuild/rpmbuild/BUILD/<pkg>-<ver>/`
prefix — usually 4 or 5.

**Commit?** No. Runtime concern, no source change needed.

---

## When in doubt

The rule of thumb: **anything that masks a real problem ≠ committable.**
Ignore-errors widening, `|| true` on tests, wholesale `-Wno-error`
gates — all of these *belong* in your local working tree for the
duration of one coverage session, never in a commit. The commit log
is the spec's source of truth for production builds; muddying it with
"this was for that one coverage run" creates regressions years later
when nobody remembers why a test is silently allowed to fail.
