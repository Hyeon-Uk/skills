# Canonical gcov spec pattern (annotated)

This is the six-block pattern almost every Tizen AppFW package uses to
add gcov support to its `.spec`. Use this as the reference when you
need to verify, audit, or — through a properly reviewed commit — add
gcov support to a package that doesn't yet have it.

> Reminder: adding these blocks to a spec that lacks them is a real,
> committable change. Editing the contents (e.g., adding categories to
> `--ignore-errors`) **as a temporary workaround** during a coverage
> session is the use case for `gbs build --include-all` — local-only,
> never committed.

---

## Block 1 — BuildRequires

```spec
%if 0%{?gcov:1}
BuildRequires:  lcov
%endif
```

Pure dependency. `lcov` provides both the `lcov` and `genhtml`
binaries used in `%check`.

## Block 2 — Sub-package declaration

```spec
%if 0%{?gcov:1}
%package gcov
Summary:  <pkg>(gcov)
Group:    Development/Libraries
%description gcov
gcov objects of <pkg>
%endif
```

This declares `<pkg>-gcov-<ver>-<rel>.<arch>.rpm`. The contents are
defined by Block 6.

## Block 3 — Compiler/linker flag injection

```spec
%if 0%{?gcov:1}
export CFLAGS+=" -fprofile-arcs -ftest-coverage"
export CXXFLAGS+=" -fprofile-arcs -ftest-coverage"
export FFLAGS+=" -fprofile-arcs -ftest-coverage"
export LDFLAGS+=" -lgcov"
%endif
```

This must run **before** `%cmake` / `%configure` / `make` so the flags
flow into the build system. Position it at the top of `%build` (or
right after `%setup`).

`-fprofile-arcs` instruments edges; `-ftest-coverage` emits the
`.gcno` graph file at compile time. `-lgcov` links the runtime that
emits `.gcda` execution counts.

## Block 4 — Capture in `%check`

```spec
%check
ctest -V
%if 0%{?gcov:1}
lcov -c --ignore-errors mismatch,graph,unused --no-external -q -d . -o <pkg>.info
genhtml <pkg>.info -o <pkg>.out
zip -r <pkg>.zip <pkg>.out
install -m 0644 <pkg>.zip %{buildroot}%{_datadir}/gcov/obj/<pkg>.zip
%endif
```

Sequence:
1. `ctest -V` runs the tests, producing `.gcda` files.
2. `lcov -c` captures `.gcno + .gcda` from the current build dir into
   `<pkg>.info`.
3. `genhtml` renders the `.info` into a navigable HTML tree.
4. `zip` packages the tree; `install` deposits it into the buildroot.

The `--ignore-errors mismatch,graph,unused` tail is the load-bearing
part for keeping the build green across gcc/lcov skew. If a new
category appears (e.g. `inconsistent`, `corrupt`, `negative`), the
fix is to widen this list — temporarily via `--include-all` if you
just need numbers; permanently via a real commit if it's a structural
need that affects every coverage build.

## Block 5 — Harvest `.gcno` in `%install`

```spec
%if 0%{?gcov:1}
builddir=$(basename $PWD)
gcno_obj_dir=%{buildroot}%{_datadir}/gcov/obj/%{name}/"$builddir"
mkdir -p "$gcno_obj_dir"
find . -name '*.gcno' -exec cp --parents '{}' "$gcno_obj_dir" ';'
%endif
```

Why this is separate from Block 4: `.gcno` files are needed if anyone
later wants to combine the package's coverage with on-device
`.gcda` runs (see SKILL §6.5). Shipping them in the gcov RPM keeps the
two artifacts (HTML report + raw graph) in one place.

## Block 6 — `%files gcov`

```spec
%if 0%{?gcov:1}
%files gcov
%{_datadir}/gcov/obj/*
%endif
```

Everything Blocks 4 and 5 installed lands in `/usr/share/gcov/obj/`,
which is what this `%files` section claims for the gcov sub-package.

---

## Verification grep one-liner

```bash
grep -nE 'gcov 1|fprofile-arcs|lcov.*ignore-errors|genhtml|gcov/obj' \
  packaging/*.spec
```

If you don't see all six blocks, the package doesn't fully support
`--define "gcov 1"` and you should report that to the user before
attempting a build.
