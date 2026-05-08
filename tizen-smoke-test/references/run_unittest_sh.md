# `run-unittest.sh` — the post-install runner (Pattern A)

This is the dominant smoke-test convention in this workspace. ~30 packages
already use it. Reference implementations: `rpc-port`, `bundle`, `notification`,
`aul-1`, `app-control`, `data-control`, `message-port`.

## Why it lives in the spec file (and not as a checked-in script)

The runner is written via `cat << EOF > run-unittest.sh` inside `%install`,
not committed as a real file under `<pkg>/test/`. There are two reasons:

1. **`%{_bindir}` is resolved at install time, not build time.** The script
   needs to call e.g. `/usr/bin/<pkg>_unittests`, but on a developer's host
   that path doesn't exist. Embedding in the spec lets the heredoc reference
   `%{name}` which the RPM toolchain expands correctly per build profile.
2. **The same script template is reused across multiple sub-packages.**
   `bundle.spec` ships the same heredoc into six sub-package directories
   (`bundle`, `parcel`, `tizen-database`, `tizen-dlog`, `tizen-libopener`,
   `tizen-shared-queue`), each with a different `<NAME>` substitution.
   A single source-of-truth file under `tests/` would either need duplication
   or a build-time generator — the heredoc is simpler.

If you find yourself wanting the script in a real file (because it's grown to
50+ lines), that's a strong signal you should be using Pattern B instead.

## Anatomy of the runner

```sh
#!/bin/sh

# (1) Optional gcov env. Only present in coverage builds.
# GCOV_PATH="/tmp/home/abuild/rpmbuild/BUILD"
# PACKAGE="<NAME>-%{version}"

# (2) Optional SMACK helper. Required when the test binary writes under
# /tmp/home/ or anywhere with non-default SMACK labels.
# set_perm() {
#     /usr/bin/find /tmp/home/ -print | /usr/bin/xargs -n1 /usr/bin/chsmack -a "System::Run" &> /dev/null
#     /usr/bin/find /tmp/home/ -print | /usr/bin/xargs -n1 /usr/bin/chsmack -a "System::Run" -t &> /dev/null
#     /usr/bin/chmod -R 777 /tmp/home/
# }

setup() {
    # Stage on-device fixtures, set env, mkdir tmp dirs.
}

test_main() {
    # The actual smoke check — usually `/usr/bin/<NAME>-unittests`.
    /usr/bin/<NAME>-unittests
}

teardown() {
    # Mirror everything `setup` did, idempotently.
}

main() {
    setup
    test_main
    teardown
}

main "$*"
```

## The `<NAME>` placeholder + `sed -i` substitution

Inside the heredoc the binary path is templated:

```sh
test_main() {
    /usr/bin/<NAME>-unittests
}
```

…and after the script is installed, the spec file does:

```spec
sed -i -e 's/<NAME>/<pkg>/g' %{buildroot}%{_bindir}/tizen-unittests/%{name}/run-unittest.sh
```

This indirection is what lets `bundle.spec` install the same template six
times, sed in `bundle` / `parcel` / `tizen-database` / `tizen-dlog` /
`tizen-libopener` / `tizen-shared-queue`, and have six independent runners.

For a single-package project you can either:

- **Keep the indirection** (matches existing convention; cheap insurance if
  you split into sub-packages later).
- **Hardcode `%{name}`** directly in the heredoc (slightly less code, but
  diverges from the workspace pattern).

Pick consistency with the package's siblings. If the rest of the package
already uses `<NAME>`/`sed`, keep it.

## Escaping rules inside the heredoc

The heredoc `<< EOF` is **unquoted**, so RPM expands `%{name}`, `%{version}`,
and any `$VAR` it sees during `%install`. To preserve a literal `$` in the
generated script, escape with `\$`:

| You write       | RPM emits            | Why                                |
|-----------------|----------------------|------------------------------------|
| `%{name}`       | (the package name)   | Spec macro expansion is desired.   |
| `%{_bindir}`    | (e.g. `/usr/bin`)    | Spec macro expansion is desired.   |
| `\$*`           | `$*`                 | Pass shell args through to `main`. |
| `\${GCOV_PATH}` | `${GCOV_PATH}`       | Set inside the script, used later. |

If you don't want any spec expansion at all, use `<< 'EOF'` (quoted) — but
that loses the ability to embed `%{name}`/`%{version}`, which is the main
reason the heredoc exists. The unquoted form with selective `\` escaping is
the workspace standard.

## Common gotchas

### Forgetting to add the script to `%files`

The heredoc + `install -m 0755 ...` puts the script under
`%{buildroot}%{_bindir}/tizen-unittests/%{name}/`, but the RPM only ships
files listed in a `%files` block. Add this line under `%files unittests`:

```spec
%{_bindir}/tizen-unittests/%{name}/run-unittest.sh
```

Without it, `gbs build` errors with:

```
error: Installed (but unpackaged) file(s) found:
   /usr/bin/tizen-unittests/<pkg>/run-unittest.sh
```

### Using `bash`-isms in the script

The device shell is `busybox sh` on minimal Tizen images. Stick to POSIX:

- `[` / `[[` — use `[`.
- `set -o pipefail` — not portable; check exit codes individually.
- `<( )` process substitution — not available; use a temp file.
- Arrays (`x=(a b c)`) — not available; iterate over a space-separated string.

### Running tests that need root or a real user session

If the binary can't run from a fresh shell (e.g. it requires being a logged-in
user, needs a dbus session bus, or expects a system service to be live), the
runner is *not* the right place to set that up. Either:

- Move the test to Pattern B and use `setcap` / a `SmokeEnvironment`.
- Make the binary itself robust to running as root in a non-session context.

Trying to fake a session inside the runner script reliably produces flakes
that look like product bugs.

## When to add a `--gtest_filter` smoke gate

By default the runner invokes `*_unittests` with no args, running every
test. That's fine when the unit-test suite is small and all tests are safe
to run on-device. Add a filter when:

- The unit-test suite includes tests that touch real DBs or files the smoke
  runner shouldn't disturb.
- The suite is too slow for a smoke budget (target: under 30 seconds).
- You want to ship a smaller smoke runner alongside the full unittests.

Convention: prefix smoke-relevant tests with `Smoke` or `BasicSanity` in C++,
then filter via:

```sh
test_main() {
    /usr/bin/<NAME>-unittests --gtest_filter='*Smoke*:*BasicSanity*'
}
```

Don't grow the filter past three or four patterns — once it becomes a
denylist, you've duplicated the test selection logic and the runner has
stopped pulling its weight.
