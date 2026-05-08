# Naming and style — exhaustive rules

These rules exist so a reviewer flipping between `application/`, `widget-service/`,
`tizen-core/`, etc. sees the same shape every time.

## File names

- Newer layout (`tests/<pkg>_unittests/`): `<subject>_test.cc`
  - `app_main_test.cc`, `tizen_core_test.cc`, `tizen_core_channel_test.cc`
- Older layout (`unittest/src/`): `test_<subject>.cc`
  - `test_widget_service.cc`, `test_widget_plugin_parser.cc`
- One **subject** per file. A subject is a feature area, not a single
  function. `app_main_test.cc` covers all `ui_app_*` lifecycle calls;
  `app_resource_test.cc` covers all `app_resource_*` calls.

## Fixture class names

- `<Subject>Test` in PascalCase (no underscores in the class name).
- `AppMainTest`, `TizenCoreTest`, `WidgetServiceTest`, `RpcPortTest`.
- Inherit `TestFixture` if external mocks are required, otherwise
  `::testing::Test`.

## Test names — `_P` / `_N`

```
TEST_F(<Subject>Test, <api_name_or_method>_<P|N>[_<reason>])
```

- `_P` — every documented success shape gets one. If a function has
  multiple meaningfully different success paths (e.g. "with callback"
  vs "without callback"), use `_P_with_cb`, `_P_without_cb` or `_P2`,
  `_P3`. Stick to the convention the package already uses.
- `_N` — every documented failure return code gets one. If multiple
  invalid inputs all return the same code, they may share an `_N` test
  with multiple `ASSERT_EQ`s. If they return different codes, split
  them: `_N_invalid_param`, `_N_permission_denied`, `_N_not_found`,
  `_N_out_of_memory`.
- The api/method portion is the **exact** symbol from the public API,
  including any `_internal` suffix. Lowercase + underscore, never
  paraphrased: `ui_app_main_N`, not `UiAppMainN` or `MainNegative`.

### Canonical mapping (analysis row → test name)

```
Method:  int api_x(in *p1, out *p2)
Returns: API_ERROR_NONE on success
         API_ERROR_INVALID_PARAMETER if p1 == NULL or p2 == NULL
         API_ERROR_OUT_OF_MEMORY    if internal alloc fails
         API_ERROR_PERMISSION_DENIED if cynara denies
         API_ERROR_NOT_SUPPORTED   if feature not enabled

Tests:
  TEST_F(XTest, api_x_P)                       // happy path
  TEST_F(XTest, api_x_N)                       // p1 == NULL  AND  p2 == NULL
  TEST_F(XTest, api_x_N_out_of_memory)         // forced via mocked malloc
  TEST_F(XTest, api_x_N_permission_denied)     // cynara mocked to DENIED
  TEST_F(XTest, api_x_N_not_supported)         // system_info mocked to false
```

## Assertion style

- Use `ASSERT_EQ(ret, <ENUM>)` — not `ASSERT_EQ(ret, 0)` and not
  `ASSERT_TRUE(ret == ENUM)`. The enum name is part of the test's
  documentation.
- Always pin the *exact* error on `_N` paths. `ASSERT_NE(ret, <NONE>)`
  is unacceptable: it lets future regressions slip through.
- `ASSERT_*` for setup steps that must hold before the assertion of
  interest. `EXPECT_*` for the assertion of interest itself, so that a
  single failure in a chain still produces useful output.
- For out-pointers, assert both the return value and the populated
  contents:
  ```cpp
  ASSERT_EQ(ret, X_ERROR_NONE);
  ASSERT_NE(handle, nullptr);
  ASSERT_STREQ(name, "expected");
  ```
- For callback APIs, set a flag in the fixture (`bool touched_`,
  `int call_count_`) inside the callback and assert it after the
  triggering call.

## Comments and exclusions

- Use `// LCOV_EXCL_START` / `// LCOV_EXCL_STOP` around scaffolding that
  cannot or should not be measured for coverage (no-op fakes, throw
  paths in `main()`, defensive branches inside test fixtures).
  ```cpp
  // LCOV_EXCL_START
  void FakeAddEvent(std::shared_ptr<...> e) {}
  // LCOV_EXCL_STOP
  ```
- Use `// LCOV_EXCL_LINE` for single-line exclusions.
- Do not write a comment that just narrates what the code does. Write
  a comment only when the *why* is non-obvious — typically when a
  particular `EXPECT_CALL` or fake exists to drive a specific failure
  path.

## Anonymous-namespace conventions

Top-of-file local helpers go in `namespace { ... }`. The convention is:

- `__fake_<symbol>` — a fake matching the signature of a mocked C
  function, suitable for `Invoke(__fake_<symbol>)`.
- `Fake<MethodName>` — same idea but for a class method on a
  `gmock`'d class.
- Free callbacks supplied to APIs (`AppCreateCb`, `AppEventCb`, ...)
  use PascalCase `Cb` suffix.

## What forbidden patterns look like

```cpp
// FORBIDDEN — testing a static function via include trick
#include "../src/widget_service.c"          // NO
TEST_F(WidgetServiceTest, _internal_helper_P) { ... }

// FORBIDDEN — defeating access control
#define private public                       // NO
#define protected public                     // NO
#include "widget_state.hh"

// FORBIDDEN — friending the test into a class for the same purpose
class WidgetState {
  friend class WidgetStateTest;              // NO
  ...
};

// FORBIDDEN — assertion-free "smoke" test
TEST_F(XTest, api_smoke) {
  api_call();                                // NO — must assert something
}

// FORBIDDEN — vague assertion
ASSERT_NE(ret, 0);                           // NO — pin the exact enum

// FORBIDDEN — multiple unrelated subjects in one TEST_F
TEST_F(XTest, init_and_destroy_and_event_P) { ... }   // split into three
```
