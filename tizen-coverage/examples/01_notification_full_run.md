# Example — measuring coverage on `notification`

End-to-end transcript of a real coverage run on the `notification`
package, including the `inconsistent` lcov error and the
`--include-all` recovery path. Numbers in this example are the actual
output from running the skill against this workspace.

---

## Step 1 — Pre-flight

```
$ grep -nE 'gcov|fprofile-arcs' /home/kimhyeonuk/.openclaw/workspace/gerrit/notification/packaging/notification.spec
32:%if 0%{?gcov:1}
47:%if 0%{?gcov:1}
71:%if 0%{?gcov:1}
72:export CFLAGS+=" -fprofile-arcs -ftest-coverage"
73:export CXXFLAGS+=" -fprofile-arcs -ftest-coverage"
74:export FFLAGS+=" -fprofile-arcs -ftest-coverage"
75:export LDFLAGS+=" -lgcov"
92:%if 0%{?gcov:1}
93:lcov -c --ignore-errors mismatch,graph,unused --no-external -q -d . -o notification.info
...
234:%if 0%{?gcov:1}
235:%files gcov
```

All six blocks present. Good to go.

---

## Step 2 — First build attempt (will fail)

```
$ cd /home/kimhyeonuk/.openclaw/workspace/gerrit/notification
$ gbs build -A x86_64 --include-all --define "gcov 1" 2>&1 | tee /tmp/notification-gcov.log
...
[   86s]     inconsistent: 1
[   86s] lcov: ERROR: lcov: ERROR: (inconsistent) mismatched end line for
        _ZN24TimeItemTest_create_Test8TestBodyEv at
        .../tests/unittests/src/test_noti_ex_time_item.cc:51: 51 -> 53
        while capturing from
        ./tests/unittests/CMakeFiles/notification-unittests.dir/src/test_noti_ex_time_item.cc.gcda
        (use "lcov --ignore-errors inconsistent ..." to bypass this error)
[   86s] error: Bad exit status from /var/tmp/rpm-tmp.0d0lry (%check)

RPM build errors:
    Bad exit status from /var/tmp/rpm-tmp.0d0lry (%check)
```

This is the **R1** case from `references/error_recovery.md`. The
build environment's `lcov` flags an `inconsistent` category that the
spec's `--ignore-errors mismatch,graph,unused` does not include.

---

## Step 3 — Recover with `--include-all` (local-only spec patch)

```
$ sed -n '93p' packaging/notification.spec
lcov -c --ignore-errors mismatch,graph,unused --no-external -q -d . -o notification.info

# Edit: add `,inconsistent` to the ignore list — LOCAL ONLY, NEVER COMMIT.
$ sed -i 's/mismatch,graph,unused/mismatch,graph,unused,inconsistent/' packaging/notification.spec

$ git status -s packaging/
 M packaging/notification.spec        # local edit, not committed
```

Re-run the build. `--include-all` makes gbs pick up the uncommitted
edit.

```
$ gbs build -A x86_64 --include-all --define "gcov 1" 2>&1 | tee /tmp/notification-gcov2.log
...
[  127s] Wrote: /home/abuild/rpmbuild/RPMS/x86_64/notification-gcov-0.12.1-1.x86_64.rpm
[  127s] Wrote: /home/abuild/rpmbuild/RPMS/x86_64/notification-debuginfo-0.12.1-1.x86_64.rpm
...
info: finished building notification
=== Total succeeded built packages: (1) ===
```

Build succeeded. **Now revert the spec** before doing anything else:

```
$ git restore packaging/notification.spec
$ git status -s packaging/
                 # clean — the workaround exists nowhere durable
```

---

## Step 4 — Locate and extract the artifacts

```
$ ls ~/GBS-ROOT/local/repos/unified_standard_debug/x86_64/RPMS/notification-gcov-*.rpm
/home/kimhyeonuk/GBS-ROOT/local/repos/unified_standard_debug/x86_64/RPMS/notification-gcov-0.12.1-1.x86_64.rpm

$ mkdir -p /tmp/notification_cov && cd /tmp/notification_cov
$ rpm2cpio ~/GBS-ROOT/local/repos/*/x86_64/RPMS/notification-gcov-*.rpm | cpio -idmv
...
92306 blocks

$ ls usr/share/gcov/obj/
notification          # raw .gcno tree
notification.zip      # the lcov+genhtml report (831 KB)

$ unzip -q usr/share/gcov/obj/notification.zip -d ./html
$ ls html/notification.out/index.html
html/notification.out/index.html
```

---

## Step 5 — Read the headline numbers

From the index page (rendered HTML, but you can grep the raw file):

```
Lines:     31.5 %  (4397 / 13979)
Functions: 55.3 %  ( 776 / 1402)
```

Branch coverage is not enabled in this spec (would require
`--rc lcov_branch_coverage=1` on the `lcov -c` line).

---

## Step 6 — Per-directory pivot

The HTML root index shows four logical areas:

| Path                         | Lines | Functions | What it is             |
|------------------------------|-------|-----------|------------------------|
| `src/notification/src/`      | mid   | mid       | the C library under test |
| `src/notification-ex/`       | low   | low       | the C++ ex library       |
| `tests/unittests/src/`       | high  | high      | the test code itself     |
| `tests/mock/`                | high  | high      | mock trampolines         |

The interesting cells are the first two — that's the production
surface. The last two are the test code; high coverage there is
expected (it's the code that runs).

---

## Step 7 — Per-file detail (`src/notification/src/`)

Pulled from `html/notification.out/src/notification/src/index.html`:

| File                          | Line cov | Notes |
|-------------------------------|----------|-------|
| `notification.c`              | 58.5 %   | the API surface — needs more tests |
| `notification_db.c`           | 21.9 %   | DB layer — heavily underexercised |
| `notification_error.c`        | 55.6 %   | small file, error-string mapping |
| `notification_internal.c`     |  0.0 %   | not invoked at all by the suite |
| `notification_internal_tidl.c`|  0.0 %   | TIDL-generated wrappers |
| `notification_ipc.c`          |  2.6 %   | IPC layer — only init paths run |
| `notification_list.c`         | 11.1 %   | list manipulation barely covered |
| `notification_noti.c`         |  0.0 %   | bulk handler — uncovered |
| `notification_ongoing.c`      |  0.0 %   |
| `notification_setting.c`      |  0.0 %   |
| `notification_tidl.c`         |  0.0 %   |
| `notification_tidl_proxy.c`   |  0.0 %   |
| `notification_viewer.c`       |  0.0 %   |

Triage reading: 7 of 13 production files are at 0 %. The current
unit-test suite essentially exercises only `notification.c` (the
public API) and a fragment of `notification_db.c`. Anything below
that — IPC, TIDL proxies, ongoing-notification helpers, settings —
has no unit test coverage at all. This is the actionable signal.

---

## Step 8 — Per-line and per-function inspection

For the file with mid coverage (`notification.c` at 58.5 %), open

```
html/notification.out/src/notification/src/notification.c.gcov.html
```

Each line is annotated:
- gray = non-executable (declarations, comments)
- green with hit count = executed
- red `#####` = executable but never run

For functions specifically:

```
html/notification.out/src/notification/src/notification.c.func.html
```

— shows every function with its hit count. The `0` rows are the
candidates for new tests.

CLI alternative when you don't want to render HTML (assuming you also
captured the `.info` file from inside the build root, or copy it out
of `~/GBS-ROOT/local/BUILD-ROOTS/scratch.x86_64.0/...`):

```
$ awk -F: '/^FNDA:0,/{ sub(/^FNDA:0,/,""); print }' notification.info | sort -u
notification_get_event_handler
notification_post_with_event_handler
notification_set_extension_data
notification_set_image_internal
...
```

That list is the most direct "what to test next" output of the whole
exercise.

---

## Step 9 — Report to the user

When summarizing back, include:

- Headline %: 31.5 % lines, 55.3 % functions.
- The triage observation: 7 of 13 production files at 0 % (list them).
- The actionable list: top-N uncovered functions by name.
- **The disclosure**: "Run was made with a local `inconsistent`
  ignore-errors workaround in the spec. The workaround was reverted
  immediately after; `git status` is clean. The structural fix would
  be to widen the spec's ignore-errors list permanently — that is a
  separate, reviewable commit and is not part of this measurement."

That last line matters: anyone reading your numbers needs to know
what the test contract actually is, not what your local working tree
looked like for 90 seconds.
