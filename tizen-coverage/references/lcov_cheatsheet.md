# lcov / gcov / genhtml CLI cheatsheet

The `<pkg>-gcov` RPM ships an HTML tree built by `genhtml` plus the raw
`.gcno` files. Most coverage questions can be answered without ever
opening a browser — the `lcov` and `gcov` CLIs operate directly on the
`.info` file or the raw graph/data files.

This is the toolbox the SKILL.md §5 references. Read it on demand.

---

## 1. The `.info` file format (key records)

`lcov -c` emits a text file with these records, one block per source
file:

```
SF:<source-path>          # start of a file's block
FN:<line>,<func>          # function declared at <line>
FNDA:<count>,<func>       # function entered <count> times
DA:<line>,<count>         # executable line <line> ran <count> times
LH:<n>                    # lines hit (covered)
LF:<n>                    # lines found (executable)
FNH:<n>                   # functions hit
FNF:<n>                   # functions found
end_of_record             # end of this file's block
```

Most "where do I find X" questions reduce to grepping these tags.

---

## 2. Per-file summary

```bash
# Whole package, sorted by line coverage (worst first)
lcov --list <pkg>.info | sort -k 2 -t '|'
```

Output columns are: file path | line cov% | function cov% (and branch
if enabled).

```bash
# Just one source file
lcov --extract <pkg>.info '*/notification.c' -o /tmp/one.info \
  && lcov --list /tmp/one.info
```

```bash
# Bottom 10 files by line coverage (handy for triage)
lcov --list <pkg>.info | tail -n +3 | sort -t'|' -k2 -n | head -10
```

---

## 3. Uncovered lines in a single file

Three ways, increasing in detail.

### Quick CLI (line numbers only)
```bash
awk -F: '/^SF:.*notification.c/{f=1;next} /^end_of_record/{f=0}
         f && /^DA:/ { split($0,a,":|,"); if(a[3]==0) print a[2] }' <pkg>.info
```

### lcov-driven, then read the source
```bash
lcov --extract <pkg>.info '*/notification.c' -o /tmp/one.info
genhtml /tmp/one.info -o /tmp/one_html
xdg-open /tmp/one_html/index.html
```

### Raw `gcov` per object
```bash
# from the build root where the .gcno + .gcda + .o files sit:
gcov -b -c -o tests/unittests/CMakeFiles/notification-unittests.dir/__/__/src/notification/src \
     src/notification/src/notification.c
# produces notification.c.gcov in cwd, annotated with hit counts
less notification.c.gcov
```

The `.gcov` text file is the most direct view: every line of the source
is prefixed with its execution count.

```
        -:    1:/* license */
        -:    2:#include <foo.h>
       12:    3:int notification_set_image(...) {
       12:    4:    if (noti == NULL)
        2:    5:        return INVALID_PARAMETER;
       10:    6:    ...
    #####:   18:    /* never executed */
```

`-` = non-executable, `#####` = executable but never ran.

---

## 4. Per-function coverage

### Functions never called (the most actionable cut)

```bash
awk -F: '/^FNDA:0,/{ sub(/^FNDA:0,/,""); print }' <pkg>.info | sort -u
```

Each line is the name of a function that was declared but never
entered during `%check`.

### Per-file function summary

```bash
# Lists every function with hit count, grouped by file
awk '
  /^SF:/   { file=$0; sub(/^SF:/,"",file); next }
  /^FNDA:/ { sub(/^FNDA:/,""); split($0,a,","); print a[2]"\t"a[1]"\t"file }
' <pkg>.info | column -t -s$'\t' | sort
```

### From `gcov` directly (function-level detail in `.gcov.json`)

Modern gcov can emit JSON with per-function and per-line counts:

```bash
gcov --json-format -o <build-objdir> <source.c>
# produces <source.c>.gcov.json.gz — gunzip and inspect with jq:
gunzip -c notification.c.gcov.json.gz | jq '.files[].functions[]
  | {name, execution_count}' | head
```

This is the cleanest input for any tooling that wants programmatic
access to coverage numbers.

---

## 5. Combining coverage from multiple test runs

If the test suite is split (e.g., a unit-test RPM AND an integ-test
RPM, both run separately), capture each run's `.info` and merge:

```bash
lcov -c --ignore-errors mismatch,graph,unused -d <build1> -o cov1.info
lcov -c --ignore-errors mismatch,graph,unused -d <build2> -o cov2.info
lcov -a cov1.info -a cov2.info -o combined.info
genhtml combined.info -o combined_html
```

Tizen's package-internal `%check` only collects the unit-test run, so
combining is something you do manually if you also have integ data.

---

## 6. Filtering before reporting

Coverage-by-file is noisy if you don't filter out generated/external
files. The Tizen specs already pass `--no-external` to `lcov -c`, but
you may also want:

```bash
# drop tests/ and mock/ directories from the report
lcov --remove <pkg>.info \
  '*/tests/*' '*/mock/*' '*/CMakeFiles/*' \
  -o <pkg>.filtered.info
```

`--remove` accepts shell-glob patterns. Apply this to the `.info`
before `genhtml` if you want a cleaner report.

---

## 7. Diffing two coverage runs

Useful when you want to confirm a new test actually improved coverage.

```bash
# extract coverage % per file, before and after
lcov --list before.info  | awk -F'|' '{print $1, $2}' | sort > /tmp/before.txt
lcov --list after.info   | awk -F'|' '{print $1, $2}' | sort > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt
```

For HTML comparison, `genhtml --baseline-file before.info after.info -o diff_html`
shows added/removed coverage in the same UI.

---

## 8. Reading raw `.gcno` / `.gcda` outside lcov

When `lcov` itself is broken (version skew, see SKILL §6.4), you can
still get per-line counts straight from gcov:

```bash
cd <build-root>
find . -name '*.gcno' -exec dirname {} \; | sort -u | while read d; do
  (cd "$d" && gcov -b -c *.o 2>/dev/null)
done
# look for *.gcov files alongside the .gcno
find . -name '*.gcov' | xargs grep -l notification.c | head -5
```

This bypasses lcov entirely, at the cost of getting plain text per file
instead of an aggregated report.
