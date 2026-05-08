---
name: tizen-build-debugger
description: Tizen GBS build log analyzer for the debugger subagent. Use when analyzing GBS build failures, diagnosing RPM dependency errors, compile errors, linker errors, or CMake/make failures in Tizen packages. Triggers on: gbs build log output, "build failed", "error: Failed build dependencies", "undefined reference", "implicit declaration", "Bad exit status", "make[N]: ***", or any GBS build failure analysis request.
---

# Tizen GBS Build Log Debugger

Reference guide for diagnosing Tizen GBS (`gbs build`) failures. Based on real build logs from the `notification` package (platform/core/api/notification, tizen branch).

---

## Log Structure Overview

GBS build logs follow this structure:
```
[  Ns] <message>   ← N = seconds since build start
```

### Build Phases (in order)
```
[gbs] prepare sources...
[gbs] start export source from: <path>          ← git → tarball
[gbs] retrieving repo metadata...               ← fetch remote repodata
[gbs] parsing package data...
[gbs] building repo metadata ...
[gbs] package dependency resolving ...
[gbs] *** [1/N] building <pkg>-<ver>-<rel> <arch> <dist> ***
logging output to <buildroot>/.build.log...

[  0s] Using BUILD_ROOT=...                     ← chroot init
[  0s] hostname started "build *.spec" at <timestamp>
[  Ns] ----- building <pkg>.spec -----
[  Ns] + exec rpmbuild ...                      ← actual rpmbuild begins
[  Ns] Building target platforms: ...
...compilation output...
[  Ns] hostname finished "build *.spec" at <timestamp>   ← SUCCESS
[  Ns] hostname failed "build *.spec" at <timestamp>     ← FAILURE
```

---

## Error Categories & Log Patterns

### Type 1: RPM Build Dependency Missing
**Trigger:** `BuildRequires: pkgconfig(nonexistent-lib)` in `.spec` but package doesn't exist in repos.

**Log pattern:**
```
[    1s] error: Failed build dependencies:
[    1s] 	pkgconfig(nonexistent-fake-lib) is needed by notification-0.12.1-1.armv7l
[    1s] hostname failed "build notification.spec" at <timestamp>.
```

**GBS summary:**
```
=== the following packages failed to build due to rpmbuild issue (1) ===
notification: /root/GBS-ROOT/local/repos/tizen/armv7l/logs/fail/notification-0.12.1-1/log.txt
```

**Key identifiers:**
- `error: Failed build dependencies:` — immediate, before any compilation
- `<pkgname> is needed by <package>-<ver>-<rel>.<arch>`
- Build fails at `[  1s]` — very early, no cmake/make output

**Root causes:**
- `pkgconfig(<name>)` not in Tizen repo
- Typo in package name in `.spec`
- Package only available in different repo (Tizen:Base vs Tizen:Unified)
- Wrong architecture variant

**Fix:** Check `packaging/*.spec` `BuildRequires`. Verify package exists:
```bash
curl -s http://download.tizen.org/snapshots/tizen/unified/latest/repos/standard/packages/armv7l/ | grep <pkgname>
```

---

### Type 2: Compile Error — Implicit Declaration / Undefined Function
**Trigger:** Calling a function not declared (missing prototype / wrong include).

**Log pattern:**
```
[   12s] /home/abuild/rpmbuild/BUILD/<pkg>/src/<file>.c:<line>:<col>: error: implicit declaration of function '<func_name>' [-Wimplicit-function-declaration]
[   12s] make[2]: *** [src/<lib>/CMakeFiles/<lib>.dir/build.make:<N>: .../<file>.c.o] Error 1
[   15s] make[1]: *** [CMakeFiles/Makefile2:<N>: src/<lib>/CMakeFiles/<lib>.dir/all] Error 2
[   18s] error: Bad exit status from /var/tmp/rpm-tmp.<XXXXX> (%build)
[   18s]     Bad exit status from /var/tmp/rpm-tmp.<XXXXX> (%build)
```

**Key identifiers:**
- `error: implicit declaration of function '<name>'` — GCC error
- `make[2]: *** [...] Error 1` → `make[1]: *** [...] Error 2` — cascading make failures
- `error: Bad exit status from /var/tmp/rpm-tmp.<ID> (%build)` — rpmbuild %build failed
- Tizen builds with `-Werror`, so warnings become errors

**Root causes:**
- Function used but not declared (missing `#include`)
- Typo in function name
- Wrong header included
- Function declared in `.h` but not defined in any `.c`

**Fix:** Find the declaration, add correct `#include`. Check `-I` paths in compile command log.

---

### Type 3: Linker Error — Undefined Reference
**Trigger:** Function declared/called but not defined in any linked library.

**Log pattern:**
```
[   Ns] /usr/bin/ld: <output>.c.o: in function `<calling_func>':
[   Ns] <source_file>.c:<line>: undefined reference to `<func_name>'
[   Ns] collect2: error: ld returned 1 exit status
[   Ns] make[2]: *** [...] Error 1
[   Ns] make[1]: *** [...] Error 2
[   Ns] error: Bad exit status from /var/tmp/rpm-tmp.<ID> (%build)
```

**Key identifiers:**
- `undefined reference to '<symbol>'` — linker (ld) error
- `collect2: error: ld returned 1 exit status`
- Occurs during linking phase (after all `.c.o` files compiled)

**Root causes:**
- Missing `-l<lib>` in `CMakeLists.txt` `target_link_libraries()`
- `BuildRequires` has the `-devel` package but cmake doesn't link it

**Fix:** Check `CMakeLists.txt` `target_link_libraries()`. Add missing library.

---

### Type 4: CMake Configuration Error
**Trigger:** CMake fails to find a required package.

**Log pattern:**
```
[   Ns] CMake Error at CMakeLists.txt:<line> (find_package):
[   Ns]   By not providing "Find<Pkg>.cmake" in CMAKE_MODULE_PATH ...
[   Ns]
[   Ns] -- Configuring incomplete, errors occurred!
[   Ns] error: Bad exit status from /var/tmp/rpm-tmp.<ID> (%build)
```

**Alternative (pkg-config not found):**
```
[   Ns] CMake Error at /usr/share/cmake/Modules/FindPkgConfig.cmake:<N>:
[   Ns]   A required package was not found
[   Ns] -- <pkgname> not found.
```

**Key identifiers:**
- `CMake Error at CMakeLists.txt` or `FindPkgConfig.cmake`
- `Configuring incomplete, errors occurred!`
- Occurs before make starts (no `make[N]` lines yet)

---

### Type 5: Missing Include File
**Trigger:** `#include <header.h>` but file not found.

**Important:** Removing a direct `#include` may NOT cause errors if the type/function is transitively included via other headers. The failure only occurs when the header is genuinely not reachable.

**Log pattern (when it fails):**
```
[   Ns] <file>.c:<line>:<col>: fatal error: <header.h>: No such file or directory
[   Ns]  #include <header.h>
[   Ns]           ^~~~~~~~~~
[   Ns] compilation terminated.
[   Ns] make[2]: *** [...] Error 1
```

Or type mismatch from wrong/missing include:
```
[   Ns] <file>.c:<line>:<col>: error: unknown type name '<TypeName>'
[   Ns] <file>.c:<line>:<col>: error: incompatible types when assigning ...
```

---

### Type 6: Network / Infra Error
**Trigger:** Network timeout downloading packages during buildroot init.

**Log pattern:**
```
[   Ns] [302/349] downloading http://download.tizen.org/.../qemu-accel-x86_64-armv7l-0.4-6.2.armv7l.rpm ...
[   87s] read timeout at /usr/share/perl5/Net/HTTP/Methods.pm line 243. at /usr/share/perl5/LWP/UserAgent.pm line 1002.
[   87s] hostname failed "build notification.spec" at <timestamp>.
```

**Key identifiers:**
- `read timeout at .../Net/HTTP/Methods.pm`
- Failure during `[N/M] downloading ...` phase
- NOT a code problem

**Fix:** Retry build. Use `--noinit` if buildroot is already initialized.

---

## GBS Build Output Log Locations

```
~/GBS-ROOT/local/repos/<profile>/<arch>/logs/
├── fail/
│   └── <pkg>-<ver>-<rel>/
│       └── log.txt      ← full build log
└── success/
    └── <pkg>-<ver>-<rel>/
        └── log.txt
```

Quick extraction:
```bash
# Show errors only (filter download noise)
sudo grep -E "error:|Bad exit|undefined reference|make\[.*Error" \
  /root/GBS-ROOT/local/repos/tizen/armv7l/logs/fail/*/log.txt \
  | grep -v "CFLAGS\|CXXFLAGS\|downloading"

# Show cmake errors
sudo grep -A3 "CMake Error" /root/GBS-ROOT/local/repos/tizen/armv7l/logs/fail/*/log.txt

# Show GBS build summary
grep -A10 "Build Status Summary" <gbs-output>
```

---

## Debugger Decision Tree

```
Build failed?
├── Fails at [  1s] → "error: Failed build dependencies:"
│   └── Type 1: Missing RPM dep — check .spec BuildRequires
│
├── Fails during "downloading [N/M]"
│   └── Type 6: Network timeout — retry, use --noinit
│
├── "CMake Error" before any make[N] lines
│   └── Type 4: CMake config error
│
├── "implicit declaration of function '<name>'"
│   └── Type 2: Missing header/include — add #include
│
├── "undefined reference to '<symbol>'" + "collect2: error"
│   └── Type 3: Linker error — add to target_link_libraries()
│
├── "fatal error: <header.h>: No such file or directory"
│   └── Type 5: Missing include file — check -I paths, install -devel pkg
│
└── "Bad exit status from /var/tmp/rpm-tmp.*" without above
    └── Look at preceding make[N] errors — find the first failure
```

---

## Build Environment (Tizen armv7l)

| Item | Value |
|------|-------|
| Arch flags | `-march=armv7-a -mtune=cortex-a8 -mfpu=neon -mfloat-abi=softfp -mthumb` |
| Warning policy | `-Wall -Werror` (warnings = errors) |
| Exception | `-Wno-error=deprecated-declarations` |
| Buildroot | `/root/GBS-ROOT/local/BUILD-ROOTS/scratch.armv7l.0/` |
| Build user | `abuild` (inside chroot) |
| Source path | `/home/abuild/rpmbuild/BUILD/<pkg>-<ver>/` |
| RPM tmp scripts | `/var/tmp/rpm-tmp.<XXXXX>` |
| C++ standard | `-std=c++23` |

---

## Behavioral Guidance for Debugger Subagent

1. **Identify failure phase from timestamp:**
   - `[  1s]` → dependency issue (pre-compilation)
   - `[  5-30s]` → cmake/early build
   - `[  30-120s]` → compilation or linking
   - During download lines → network issue

2. **Filter noise first:** Strip `downloading` and `CFLAGS/CXXFLAGS` lines.

3. **Follow the cascade:** Multiple `make[N]: *** Error` lines come from ONE root error. Find the FIRST.

4. **Files to inspect per error type:**
   - Type 1 → `packaging/*.spec` (BuildRequires)
   - Type 2 → source `.c`/`.cc` file at reported line
   - Type 3 → `CMakeLists.txt` (target_link_libraries)
   - Type 4 → `CMakeLists.txt` (find_package / pkg_check_modules)
   - Type 5 → source file include path + cmake include_directories

5. **Network errors ≠ code bugs.** Never modify source for Type 6.

6. **Real log location:** `/root/GBS-ROOT/local/repos/tizen/armv7l/logs/fail/<pkg>-<ver>-<rel>/log.txt`
