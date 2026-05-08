# Packaging integ_tests in the .spec file

`gbs build` packages the test binary into a separate RPM so QA / CI can install
it on a device without pulling in a `-devel` package or shipping it inside the
main library RPM. The reference is `rpc-port/packaging/rpc-port.spec`.

## What you add

Three sections, in this order in the file:

### 1. Sub-package declaration

Place this right after the unittests `%package`/`%description` block (or, if
there is none, after `%description devel`):

```spec
#################################################
# <pkg>-integtests
#################################################
%package integtests
Summary:    GTest for <pkg>
Group:      Development/Libraries
Requires:   %{name}

%description integtests
Integration GTest for <pkg>
```

`Requires: %{name}` is important — the integ binary is dynamically linked
against the package's `.so`, so installing the integtests RPM should pull in
the same version of the main package.

### 2. (Usually no extra `%build` needed)

The CMake-driven build in `%build` already compiles every `ADD_EXECUTABLE`,
including the integ tests. Don't add a separate `make` invocation unless
you've gated the integ test build behind a CMake option (which most packages
in this workspace do not).

### 3. `%files integtests` list

Place this near the other `%files` blocks, after `%files unittests` if it
exists:

```spec
#################################################
# <pkg>-integtests
#################################################
%files integtests
%{_bindir}/<pkg>_integtests
# Plus any helper scripts/resources installed by the integ_tests CMakeLists:
# %{_bindir}/mk_certs.sh
# /tmp/<pkg>-certs/*
```

The paths must match what `INSTALL(TARGETS ... DESTINATION bin)` and
`INSTALL(PROGRAMS ... DESTINATION bin)` actually emit. In Tizen's CMake
conventions, `DESTINATION bin` lands at `%{_bindir}` (typically `/usr/bin`).

## Common errors and how to read them

After editing the spec, run a `gbs build`. The two errors you'll see if the
spec and CMake disagree are:

- **`error: Installed (but unpackaged) file(s) found: /usr/bin/<pkg>_integtests`**
  CMake installed the binary, but no `%files` section claims it. → Add the
  binary to `%files integtests`.

- **`error: File not found: <buildroot>/usr/bin/<pkg>_integtests`**
  `%files integtests` claims a file that nothing actually installed. →
  Either the CMake target was never built (check `ADD_SUBDIRECTORY(integ_tests)`
  is wired in), or the `INSTALL(TARGETS ...)` line is missing or pointing to
  the wrong target variable.

If you get **both** errors at once, the binary name in CMake doesn't match the
binary name in the spec. Grep the workspace:

```bash
grep -rn "<pkg>_integtests" <pkg>/CMakeLists.txt <pkg>/test <pkg>/packaging
```

…and pick one canonical name.

## Optional: gcov / coverage

If the package has a `%if 0%{?gcov:1}` block for unit tests, you usually do
*not* extend it to integ tests — integ tests run on a device, not in the
build container, so their coverage data isn't collected during `gbs build`.
Leave gcov to the unit tests.

## Optional: extra BuildRequires

The integ tests inherit every BuildRequires from the main package, so usually
no edit is needed. Add a new line only if the integ binary uses a library the
main `.so` doesn't need at link time — for example, a TLS test that pulls in
`pkgconfig(openssl3)` while the library itself doesn't.
