---
name: tizen-gtest-unit-test
description: Authoring Google Test / Google Mock unit tests for Tizen AppFW C/C++ packages (application, widget-service, notification, tizen-core, rpc-port, message-port, app-control, pkgmgr-info, etc.). Use whenever the user wants to write, add, or design unit tests for a Tizen package — including phrases like "write a unit test", "add a gtest", "TEST_F", "unit test for <api>", "add a test case", "유닛 테스트 추가", "테스트 작성", "gtest 만들어줘". Enforces an analysis-first workflow: BEFORE any test code is written, the target method's success cases, failure return codes, edge cases, corner cases, and external/private dependencies are enumerated. Forces mocking of 3rd-party / cross-module dependencies via the `TestFixture + ModuleMock + mock_hook` pattern used across this codebase, and forbids testing private/static-internal symbols. Trigger even if the user does not say "skill" or "gtest" — just describing the intent ("write tests for X") is enough.
---

# Tizen gtest Unit Test Authoring Skill

Use this skill when authoring unit tests for any package under `~/.openclaw/workspace/gerrit/*` (or any Tizen AppFW component using the same conventions). The packages here share a remarkably consistent test layout — this skill encodes that layout so new tests look like they belong, and so coverage is built deliberately rather than by hunch.

The skill has two phases. **You must complete Phase 1 in writing before producing any code in Phase 2.** Skipping the analysis is the failure mode that produces shallow tests that only cover the happy path.

---

## Phase 1 — Analyze the target (mandatory, before any code)

Output the analysis directly into the conversation as a worksheet. Do not write a single `TEST_F` until this is filled in and reviewed. The reason this is mandatory: in this codebase the C-API surface is shaped around `int api_func(...)` returning `*_ERROR_NONE` on success and a discrete `*_ERROR_*` enum on failure, and the tests pair every `_P` (positive) with one or more `_N` (negative) cases. If you skip the analysis you reliably miss half of the negative space.

### 1.1 Enumerate the public surface

Read the target source/header. Build two lists:

- **In scope** — non-static functions in the public header (`include/<api>.h`, `<api>_internal.h`) and non-private methods of public classes. C-style APIs declared `EXPORT_API` / `__attribute__((visibility("default")))` are in scope.
- **Out of scope (do NOT test directly)** —
  - `static` functions in `.c`/`.cc` translation units (file-local).
  - Methods declared `private:` or in anonymous namespaces.
  - Lambdas, helpers, and inner classes that are not part of the public/internal API.

  These are exercised *transitively* through the public surface. If they cannot be reached from any public entry point, that is a code-smell to flag, not a justification for testing them directly. Reaching into private state via `friend`, `#define private public`, or pointer-casting is **not allowed** in this skill.

### 1.2 For each in-scope method, fill out this table

```
Method:       <full signature, e.g. int widget_service_get_widget_disabled(const char *widget_id, bool *is_disabled)>
Purpose:      <one line — what does it do for the caller>
Returns:      <success sentinel, e.g. WIDGET_ERROR_NONE>
              <every documented failure code, with the precondition that triggers it>

Success cases (_P):
  [P1] <input shape>  → <expected return + observable side-effect>
  [P2] <input shape>  → <expected return + observable side-effect>
  ...

Failure cases (_N) — one row per distinct return code:
  [N1] <input shape>  → <ERROR code> (reason: <which guard in the code returns this>)
  [N2] <input shape>  → <ERROR code> (reason: ...)
  ...

Edge cases:
  [E1] <boundary value: 0, INT_MAX, empty string, single element, length=buffer_size, ...>
  [E2] <NULL out-param vs. NULL in-param vs. both NULL>
  [E3] <whitespace / unicode / very long string for char* inputs>

Corner cases:
  [C1] <reentrancy / double-call: e.g. init→shutdown→init, destroy(nullptr) after destroy>
  [C2] <ordering: calling getter before setter, calling on uninitialized handle>
  [C3] <state invariants: e.g. operating on an object after its parent was destroyed>
  [C4] <concurrent or callback-driven paths if applicable>

External dependencies (must be mocked — see Phase 2.3):
  - <syscall / library function> (e.g. aul_widget_instance_count, cynara_check, sqlite3_exec)
  - <other Tizen module> (e.g. pkgmgr-info, vconf, system_info, tzplatform_config)

Private/static helpers (NOT tested directly, exercised via the public method):
  - <symbol>  — covered by [P1, N1]
  - <symbol>  — covered by [E2]
```

### 1.3 Sanity checklist before moving on

- Every distinct return code in the implementation has at least one `_N` row.
- Every `NULL` / `nullptr` checkable parameter has at least one row.
- Every numeric / size parameter has 0, max, and one boundary row in edges.
- Every external library call you can see in the implementation appears under "must be mocked".
- No row references a `static` function or `private:` method as the test target.

If any of these fails, expand the analysis. Do not proceed.

---

## Phase 2 — Write the tests

Once Phase 1 passes the checklist, generate the tests using the conventions below. These conventions are not arbitrary — they match what is already in the repo, so reviewers can read the new tests at the same speed they read the old ones.

### 2.1 File and directory layout

For a package `<pkg>`, the test tree is one of:

```
<pkg>/tests/<pkg>_unittests/      # newer style (application, tizen-core, notification)
  ├── CMakeLists.txt
  ├── main.cc                      # InitGoogleTest + RUN_ALL_TESTS
  ├── <subject>_test.cc            # one file per subject under test
  └── mock/
      ├── module_mock.hh           # base class for all mocks
      ├── test_fixture.hh / .cc    # ::testing::Test subclass that owns the unique mock_
      ├── mock_hook.hh             # MOCK_HOOK_PN macros
      ├── <module>_mock.hh         # gmock interface per external module
      └── <module>_mock.cc         # extern "C" trampoline calling MOCK_HOOK_PN

<pkg>/unittest/                    # older style (widget-service, watchface-complication, minicontrol)
  ├── CMakeLists.txt
  ├── src/
  │   ├── test_main.cc
  │   └── test_<subject>.cc
  └── mock/
      └── <same files as above, .h/.cc instead of .hh/.cc>
```

Match whichever style the package already uses. If the package has no tests yet, prefer the newer `tests/<pkg>_unittests/` layout.

### 2.2 Naming conventions (enforced)

- **Test file**: `<subject>_test.cc` (newer) or `test_<subject>.cc` (older). One subject per file.
- **Fixture class**: `<Subject>Test`, derived from `TestFixture` (when mocking) or `::testing::Test` (when no external deps).
- **Test name**: `TEST_F(<Subject>Test, <api_or_method>_<P|N>)`.
  - `_P` — positive / success path. One per distinct success shape from the analysis.
  - `_N` — negative / failure path. One `_N` test may bundle multiple invalid inputs **only if they all return the same error code**; otherwise split.
- **Suffixes for variants**: `_P2`, `_N_invalid_handle`, `_N_permission_denied` are acceptable when one suffix is not enough.

Example pairings (taken from `application/tests/application_unittests/app_main_test.cc`):

```
TEST_F(AppMainTest, ui_app_main_and_ui_app_exit_P)   // happy path
TEST_F(AppMainTest, ui_app_main_N)                   // null callback / argv
TEST_F(AppMainTest, ui_app_add_event_handler_P)
TEST_F(AppMainTest, ui_app_add_event_handler_N)
TEST_F(AppMainTest, ui_app_remove_event_handler_P)
TEST_F(AppMainTest, ui_app_remove_event_handler_N)
TEST_F(AppMainTest, ui_app_get_window_position_P)
TEST_F(AppMainTest, ui_app_get_window_position_N)
```

Note the strict 1:1 of public function ↔ `_P` + `_N`. That is the bar.

### 2.3 Mocking: the `TestFixture + ModuleMock + mock_hook` pattern

This codebase uses a single, consistent mocking strategy. Read `references/mocking.md` for the full pattern with code; the short version:

1. Each external module (`aul`, `cynara`, `glib`, `pkgmgr-info`, `vconf`, `system_info`, `tzplatform_config`, `sqlite`, ...) gets a gmock class deriving virtually from `ModuleMock` and declares the C symbols it intercepts via `MOCK_METHODn`.
2. The `.cc` companion provides `extern "C"` trampolines for those C symbols, which call `MOCK_HOOK_Pn(<MockClass>, <fn>, args...)`. The macro looks up the active mock from `TestFixture::GetMock<MockClass>()`. This is how the *real* code under test calls into the mock at link time without modification.
3. The fixture owns one `Mocks` aggregate that virtually inherits from every `::testing::NiceMock<XxxMock>` it needs, and passes it into `TestFixture` via `std::make_unique<Mocks>()`.
4. In the test, set behavior with `EXPECT_CALL(GetMock<XxxMock>(), fn(_, _)).WillRepeatedly(Invoke(__fake_fn))` or `.WillOnce(Return(...))`.

**Rules:**
- 3rd-party libs (`glib`, `sqlite3`, `cynara`, `libxml2`, `dlog`, ...) MUST be mocked unless the test is explicitly an integration test in a separate `integ_tests/` directory.
- Cross-module Tizen deps (`aul`, `pkgmgr-info`, `bundle`, `vconf`, `system_info`, `tzplatform_config`, `app-common`, `security-manager`) MUST be mocked — they are not under test here.
- The same package's *internal* helpers are NOT mocked. Mocking them would mean you are not testing the real code.

If a needed mock does not yet exist in the package, create both `<module>_mock.hh` and `<module>_mock.cc` following the templates in `references/mocking.md`.

### 2.4 Fixture template (with mocks)

```cpp
class Mocks : public ::testing::NiceMock<AulMock>,
              public ::testing::NiceMock<CynaraMock>,
              public ::testing::NiceMock<GlibMock> {};

class WidgetServiceTest : public TestFixture {
 public:
  WidgetServiceTest() : TestFixture(std::make_unique<Mocks>()) {}
  void SetUp() override {
    // Wire the mocks that *every* test in this fixture needs.
    EXPECT_CALL(GetMock<TzplatformConfigMock>(), tzplatform_mkpath(_, _))
        .WillRepeatedly(Invoke(__fake_tzplatform_mkpath));
  }
  void TearDown() override { /* cleanup files, db, etc. */ }
};
```

Per-test mocks (those that vary by case) go inside the `TEST_F` body, not in `SetUp()`.

### 2.5 Fixture template (no external deps)

```cpp
class TizenCoreTest : public ::testing::Test {
 public:
  void SetUp() override { tizen_core_init(); /* construct handles */ }
  void TearDown() override { /* destroy handles */; tizen_core_shutdown(); }
};
```

### 2.6 main.cc template

```cpp
#include <gmock/gmock.h>
#include <gtest/gtest.h>

int main(int argc, char** argv) {
  try {
    testing::InitGoogleTest(&argc, argv);
    return RUN_ALL_TESTS();
  } catch (std::exception const& e) {
    std::cout << "test_main caught exception: " << e.what() << std::endl;  // LCOV_EXCL_LINE
    return -1;                                                              // LCOV_EXCL_LINE
  }
}
```

If the package emits `dlog` traces during tests, also stub `__dlog_print` / `__dlog_sec_print` / `dlog_vprint` in this file (see `tizen-core` for an example).

### 2.7 Body conventions

- Use `ASSERT_EQ(ret, <ERROR_NONE>)` for must-succeed steps inside `_P` tests. Use `EXPECT_*` for assertions that can continue after failure.
- Always check the exact error enum on `_N` paths — never just `ASSERT_NE(ret, 0)`. The whole point of an `_N` test is to pin the contract.
- For out-pointers, assert both the return code AND that the pointer was populated/not-modified as documented.
- For callback-driven APIs, assert that the callback was actually invoked (set a flag in the test fixture).
- Mark unreachable branches inside test scaffolding with `// LCOV_EXCL_START` / `// LCOV_EXCL_STOP` (see `application_unittests` for the convention) so coverage reports stay honest.

### 2.8 What NOT to do

- Do not test `static` functions by `#include`-ing the `.c` file.
- Do not test `private:` methods by adding `friend` declarations or `#define private public`. If a private method is genuinely complex, expose its behavior through a public method or move it to a public utility class.
- Do not call the real network / DB / dbus from a unit test. If you need them, the test belongs in `integ_tests/`, not `unit_tests/`.
- Do not write a test whose only assertion is "the call did not crash". Each test must pin a return code, an out-value, or an observable side-effect.
- Do not pile unrelated assertions into one `TEST_F`. One method, one shape, one test.

---

## 3. Build & run — gbs only

Authoring `CMakeLists.txt` updates is fine (and usually required when adding a new test target or new mock source). **Invoking** the build is not — these packages are Tizen RPMs and the `.spec` is the source of truth for compile flags, sysroot, dependency resolution, and the `%bcond_with unit_tests` (or equivalent) gate that turns the test target on. Running `cmake` or `make` directly outside of gbs uses the host toolchain and host headers, producing binaries that link against the wrong libc/glib/dlog and silently disagree with what the device actually runs.

Rules:

- **Build exclusively via `gbs build`.** No `cmake .`, no `make`, no `ninja`, no out-of-tree build dirs. A typical invocation:
  ```bash
  gbs build -A <arch> --include-all --define "build_type unit_tests" <pkg>
  ```
  Match the gate the package's `.spec` already uses (`%bcond_with unit_tests`, `--define "unit_tests 1"`, `--with unit_tests`, ...) — read the `.spec` first; do not invent a new gate.
- **Run tests on a Tizen target/emulator** via `sdb`, not on the host. The test binary is installed inside the produced RPM (typically `bin/<pkg>_unittests`).
- **If gbs fails, debug gbs.** Do not fall back to local `cmake` to "see if it compiles" — a green host build is meaningless here.
- **Iterate fast inside gbs**: `gbs build --incremental` reuses the existing build root and is the fastest inner loop available.

When unsure of the exact `gbs` flags (profile, repo, arch) for the user's setup, defer to the `tizen-gbs` skill — pair it (build) with this skill (test authoring). For runtime device interaction, defer to `tizen-sdb`.

For the CMakeLists changes themselves, mirror the structure already present in a sibling package's tests directory (e.g. `application/tests/application_unittests/CMakeLists.txt`, `tizen-core/tests/tizen-core_unittests/CMakeLists.txt`, or `widget-service/unittest/CMakeLists.txt` for the older layout). Two practical guardrails when editing them:

- **Drop the real library you are mocking from the link line.** If you mock `aul`, do not also `pkg_check_modules(... aul)` — the trampolines in `aul_mock.cc` provide those symbols. Linking both can silently bind calls to the real library and your `EXPECT_CALL`s never fire.
- **Compile the package's own sources directly into the test target.** Linking against the installed `.so` defeats coverage and prevents your trampolines from intercepting the package's calls into mocked libs.

---

## 4. Examples

The `examples/` directory contains three filled-in examples extracted and slightly trimmed from the codebase:

- `examples/01_simple_capi.md` — a C-API with no external deps (`tizen_core_*`). Shows the analysis worksheet → `_P/_N` test code mapping.
- `examples/02_mock_heavy.md` — a C-API with many external deps (`widget_service_*`). Shows the full `Mocks` aggregate, `__fake_*` helpers, and per-test `EXPECT_CALL`s.
- `examples/03_analysis_worksheet.md` — a fully filled-in Phase-1 worksheet for a real method, demonstrating the level of detail expected.

Read whichever example is closest to the package the user is working on before drafting tests.

---

## 5. Reference files

- `references/mocking.md` — full templates for `module_mock`, `test_fixture`, `mock_hook`, and a per-module mock pair.
- `references/naming_and_style.md` — the exhaustive `_P` / `_N` / `_N_<reason>` rules and assertion style.

---

## 6. Workflow summary

When the user says "write unit tests for `<api>`":

1. **Read** the public header(s) and the implementation file(s) for `<api>`.
2. **Output** the Phase 1 worksheet (§1.2) for every public function in scope. Mark which existing tests (if any) already cover which rows.
3. **Confirm** the worksheet is complete against the §1.3 checklist.
4. **Inventory** which mocks already exist in `<pkg>/{tests,unittest}/mock/`. List which new mocks are needed.
5. **Generate** the test file(s), the new mock files (if any), and the CMakeLists update — mirroring the structure of an existing test directory in the same or a sibling package. See §3 for the two guardrails when editing CMakeLists.
6. **Build & run instruction**: tell the user the test target name and the `gbs build` command for their package (see §3). Never suggest `cmake` / `make` / `ninja` as a fallback — those produce host-toolchain binaries that lie about whether the test actually works on Tizen. Tests run on a Tizen device/emulator via `sdb`, not on the host. Do NOT run the build automatically unless asked.

If at any point the user pushes back ("just write the test, skip the analysis"), explain briefly that the analysis is what produces the negative cases, and offer to do the analysis in a compressed form (one line per row) rather than skipping it. The analysis is the value of this skill.
