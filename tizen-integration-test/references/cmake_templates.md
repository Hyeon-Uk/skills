# CMake templates for integ_tests

The Tizen AppFW workspace uses three CMake levels for tests. This doc shows what to
add at each level when introducing an `integ_tests/` subtree to a package that
currently only has `unit_tests/`. The reference implementation is `rpc-port`.

## Level 1 — package root `<pkg>/CMakeLists.txt`

Add a target name variable next to the existing test target variables:

```cmake
SET(TARGET_<PKG> "<pkg>")
SET(TARGET_<PKG>_UNITTESTS "<pkg>_unittests")
SET(TARGET_<PKG>_INTEGTESTS "<pkg>_integtests")    # <-- new
```

If the package's top-level file calls `ENABLE_TESTING()` and registers
`ADD_TEST(NAME ${TARGET_<PKG>_UNITTESTS} ...)`, you usually do **not** add the
integ tests there — they require a real device and aren't meant to run as part
of the host-side `make test`.

## Level 2 — `<pkg>/test/CMakeLists.txt`

```cmake
ADD_SUBDIRECTORY(unit_tests)
ADD_SUBDIRECTORY(integ_tests)    # <-- new
```

That's it. Don't introduce conditional inclusion (`IF(BUILD_INTEG_TESTS)`)
unless the package already has the same convention for unit tests; conditionals
that exist in only one place create confusion at review time.

## Level 3 — `<pkg>/test/integ_tests/CMakeLists.txt`

The reference is `rpc-port/test/integ_tests/CMakeLists.txt`. Annotated:

```cmake
# Pull every .cc in this directory into the test binary. Test files are
# self-contained (no shared mock library), so AUX_SOURCE_DIRECTORY is enough.
AUX_SOURCE_DIRECTORY(${CMAKE_CURRENT_SOURCE_DIR} INTEG_TEST_SRCS)

ADD_EXECUTABLE(${TARGET_<PKG>_INTEGTESTS}
  ${INTEG_TEST_SRCS})

# Include both the test dir (for any local headers) and the package's public
# include dir. Reach back via `../../include` rather than the absolute path —
# in-source vs. out-of-source builds depend on this.
TARGET_INCLUDE_DIRECTORIES(${TARGET_<PKG>_INTEGTESTS} PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/../../include)

# APPLY_PKG_CONFIG is the project macro from cmake/Modules/. It expands every
# *_DEPS variable into INCLUDE_DIRECTORIES + LINK_LIBRARIES + COMPILE_OPTIONS,
# matching what PKG_CHECK_MODULES populated at the top level. Add only what
# the integ tests actually use.
APPLY_PKG_CONFIG(${TARGET_<PKG>_INTEGTESTS} PUBLIC
  GLIB_DEPS    # for GMainLoop, g_timeout_add
  GMOCK_DEPS   # gtest comes from the gmock pkgconfig on Tizen
  # Add more as needed: AUL_DEPS, BUNDLE_DEPS, DLOG_DEPS, etc.
)

# Link against the *real* library — that's what makes this an integ test, not
# a unit test that re-compiles src/ into the binary.
TARGET_LINK_LIBRARIES(${TARGET_<PKG>_INTEGTESTS} PUBLIC ${TARGET_<PKG>})

# Tizen requires PIE for executables. These flags are not optional.
SET_TARGET_PROPERTIES(${TARGET_<PKG>_INTEGTESTS} PROPERTIES
  COMPILE_FLAGS "-fPIE")
SET_TARGET_PROPERTIES(${TARGET_<PKG>_INTEGTESTS} PROPERTIES
  LINK_FLAGS "-pie")

# Install into /usr/bin so the *_integtests RPM picks it up. The %files
# section in the .spec must reference the same path.
INSTALL(TARGETS ${TARGET_<PKG>_INTEGTESTS} DESTINATION bin)

# Optional: ship helper scripts the suite needs at runtime (cert generation,
# DB seeders, etc.). PROGRAMS preserves +x.
# INSTALL(PROGRAMS ${CMAKE_CURRENT_SOURCE_DIR}/certs/mk_certs.sh DESTINATION bin)

# Optional: ship a `res/` resource dir if the suite has fixtures.
# INSTALL(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/res DESTINATION share/<pkg>)
```

## Common pitfalls

- **Forgetting `-fPIE` / `-pie`** — RPM will build but `gbs` rpmlint may
  complain, and the binary won't install on hardened images.
- **Using `${CMAKE_BINARY_DIR}/test/...` instead of `${CMAKE_CURRENT_SOURCE_DIR}`**
  — only affects out-of-source builds, but `gbs build` is out-of-source.
- **Linking against a static fake** — if you find yourself adding `-l<pkg>_static`
  or compiling `../../src/*.cc` into the test target, that's a unit-test
  pattern (see `notification/tests/unittests/CMakeLists.txt`). Integ tests
  link against the same shared lib that ships in the device RPM.
- **Adding `GTEST_DEPS`** — there's no separate `gtest` pkg-config on Tizen;
  `GMOCK_DEPS` already pulls gtest in.
