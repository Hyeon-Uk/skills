# Spec-file wiring for smoke tests

The smoke test only ships if the `.spec` file knows about it. Both Pattern A
and Pattern B require coordinated edits to multiple sections. This doc
catalogs every section, what to add, and how to debug the errors that come
from miswiring.

## Pattern A wiring (post-install runner)

### `%install` — generate and install the script

Add the heredoc + install + sed block at the end of `%install`, after
`%make_install` and after any `gcov` copy block:

```spec
cat << EOF > run-unittest.sh
#!/bin/sh
# ...runner body...
EOF

mkdir -p %{buildroot}%{_bindir}/tizen-unittests/%{name}
install -m 0755 run-unittest.sh %{buildroot}%{_bindir}/tizen-unittests/%{name}/
sed -i -e 's/<NAME>/<pkg>/g' %{buildroot}%{_bindir}/tizen-unittests/%{name}/run-unittest.sh
```

For multi-sub-package projects (e.g. `bundle.spec`), repeat the
`mkdir`/`install`/`sed` triple per sub-package — the heredoc itself only
needs to appear once.

### `%files unittests` — list the script

Add:

```spec
%files unittests
%{_bindir}/<pkg>_unittests
%{_bindir}/tizen-unittests/%{name}/run-unittest.sh
```

`aul-1` uses an explicit `%attr` to be precise:

```spec
%attr(0755,root,root) %{_bindir}/tizen-unittests/%{name}/run-unittest.sh
```

Both are accepted; match the package's existing style.

### Optional: ship test data the runner stages

If the runner expects fixtures under `%{_datadir}/<pkg>-unittests/` (e.g.
rpc-port's certs), make sure they're installed by some target's
`INSTALL(...)` and listed under `%files unittests`:

```spec
%files unittests
%{_bindir}/<pkg>_unittests
%{_bindir}/tizen-unittests/%{name}/run-unittest.sh
%{_datadir}/<pkg>-unittests/certs/*       # if applicable
/tmp/<pkg>-certs/*                         # if the runner copies into /tmp
```

## Pattern B wiring (separate smoke binary)

### Sub-package declaration

Add alongside the other `%package` blocks:

```spec
%package -n %{name}-installer-ut
Summary:    Installer smoke tests for <pkg>
Group:      Development/Libraries
Requires:   %{name}

%description -n %{name}-installer-ut
End-to-end install/uninstall smoke tests for <pkg>.
```

`Requires: %{name}` ensures the smoke binaries can dynamically link against
the same library version they'll actually exercise. Don't omit it.

### `%post` — apply file capabilities

```spec
%post -n %{name}-installer-ut
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/<pkg>-installer-ut/smoke-test
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/<pkg>-installer-ut/smoke-test-helper
```

Any binary that calls `Install`/`Uninstall` needs these capabilities. Add
one `setcap` line per binary.

### `%files` — list everything CMake installed

```spec
%files -n %{name}-installer-ut
%{_bindir}/<pkg>-installer-ut/smoke-test
%{_bindir}/<pkg>-installer-ut/smoke-test-helper
%{_libdir}/lib<pkg>-smoke-utils.so*
%{_includedir}/app-installers/smoke_tests/<pkg>_smoke_utils.h
%{_datadir}/<pkg>-installer-ut/test_samples/
```

Every line here must correspond to an `INSTALL(...)` rule in
`<pkg>/test/smoke_tests/CMakeLists.txt`. If you list a path that nothing
installs, RPM errors with "File not found"; if something installs but isn't
listed here, RPM errors with "Installed (but unpackaged) file(s) found".

## Debugging miswiring errors

After editing the spec, run a `gbs build` and watch for these errors:

### `error: Installed (but unpackaged) file(s) found: <path>`

CMake installed it; the spec doesn't know about it. → Add the path to
the relevant `%files` block.

### `error: File not found: <buildroot><path>`

The spec lists it; CMake didn't install it. → Either:

- The `INSTALL(TARGETS ...)` is missing from CMakeLists, or
- The target wasn't built (e.g. `ADD_SUBDIRECTORY(smoke_tests)` is missing
  from `<pkg>/test/CMakeLists.txt`), or
- The binary name in `%files` doesn't match the CMake target name.

Grep both files to find the canonical name:

```bash
grep -rn "smoke[-_]test" <pkg>/test/smoke_tests/CMakeLists.txt <pkg>/packaging/<pkg>.spec
```

### `setcap: not found` at install time

The image doesn't have `libcap-tools` installed. Add to the main package's
`Requires:`:

```spec
Requires:  /usr/sbin/setcap
```

…or, if `%post` should silently skip when setcap is missing:

```spec
%post -n %{name}-installer-ut
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/<pkg>-installer-ut/smoke-test 2>/dev/null || true
```

The first form is safer — if `setcap` is missing the binary won't work
anyway, so failing loudly at install time is better than failing silently
at run time.

### `EPERM` errors when running the smoke binary

Either `setcap` failed in `%post`, or it ran on a binary that wasn't actually
the one being executed (e.g. the spec lists `smoke-test` but the CMake target
is `smoke_test` with an underscore). Check:

```bash
sdb shell getcap /usr/bin/<pkg>-installer-ut/smoke-test
```

…should print the four `cap_*` strings. If empty, the `%post` line is broken.

## Ordering inside the spec

Spec sections must appear in this order. Smoke-related additions go in the
italicized slots:

1. `Name:`, `Version:`, `License:`, etc. (header)
2. `BuildRequires:`, `Requires:`
3. `%description`
4. *`%package -n %{name}-installer-ut` + `%description -n ...`* (Pattern B)
5. `%prep`, `%build`, `%check` (no smoke-specific edits)
6. `%install` — *heredoc + install + sed* (Pattern A)
7. *`%post -n %{name}-installer-ut`* (Pattern B)
8. `%files`, `%files devel`, `%files unittests`, *`%files -n %{name}-installer-ut`*

Putting `%files -n %{name}-installer-ut` before `%files unittests` works but
diverges from convention; keep the smoke entry last so reviewers can scan
top-to-bottom and follow the order from main package → devel → unittests →
smoke.
