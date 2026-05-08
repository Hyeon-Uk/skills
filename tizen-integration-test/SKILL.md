---
name: tizen-integration-test
description: Authoring Google Test integration tests for Tizen AppFW C/C++ packages under `~/.openclaw/workspace/gerrit/*` (rpc-port, aul-1, app-control, message-port, notification, data-control, tizen-core, application, pkgmgr-info, widget-service, etc.). Use whenever the user wants to add, design, or scaffold an integration test, an `integ_tests/` subtree, an end-to-end gtest, a proxy↔stub flow test, a cross-process or cross-module test, an RPM `%package integtests`, or anything that exercises real syscalls / sockets / dbus / sqlite / glib mainloop instead of mocks. Trigger phrases include "integration test", "integ test", "integ_tests", "e2e test", "end-to-end test", "통합 테스트", "통합테스트", "인테그", "integration test 추가", "integration test 작성", "integtests RPM", "real binary test", "no-mock test", "cross-process test", "proxy stub round trip", "scaffold integration test for <pkg>". Trigger even if the user does not say "skill". This skill is the sibling of `tizen-gtest-unit-test` — pick this one when the test must run against real dependencies, not mocks.
---

# Tizen Integration Test Authoring Skill

Use this skill to add or scaffold **integration tests** for any package under `~/.openclaw/workspace/gerrit/*`. The packages here share a consistent integration-test layout — `rpc-port/test/integ_tests/` is the gold reference. This skill encodes that layout so new integration tests look like they belong, get built by `gbs`, and ship as a separate `*_integtests` RPM that QA / CI can install on a real device or emulator.

The sibling skill `tizen-gtest-unit-test` covers **unit** tests (mocked, in-process, fast). This skill covers **integration** tests (real deps, real I/O, real callbacks). The two are not interchangeable. If you're not sure which one applies, check section 0 below.

---

## 0. Unit test or integration test? Decide first.

Pick the one that matches the *real failure mode* you're protecting against:

| Concern | Unit test | Integration test |
|---|---|---|
| Wiring of one function's return codes / `NULL` guards | ✅ | — |
| Behaviour of one class with all collaborators mocked | ✅ | — |
| Two processes (proxy + stub, client + daemon) talking | — | ✅ |
| Real socket / TCP / Unix-domain / dbus path | — | ✅ |
| Real `GMainLoop` dispatching real callbacks | — | ✅ |
| Real sqlite DB on disk, real file system, real cert files | — | ✅ |
| Cross-module Tizen flow (aul → amd → component-manager) | — | ✅ |
| `gbs build` should ship a separately-installable test RPM run on device | — | ✅ |

If the test would force you to mock something that's actually under test — e.g. mocking `rpc_port_proxy_connect` while testing rpc-port itself — it's an integration test. Use this skill.

If the test is cheap, hermetic, and would lose its meaning if all syscalls were stubbed — that's also an integration test. Use this skill.

Otherwise prefer a unit test (`tizen-gtest-unit-test`).

---

## Phase 1 — Plan the scenarios (mandatory, before code)

Output the plan into the conversation as a worksheet. Do not write any test code until this is done. The reason: integration tests are slow and flaky-prone — choosing scenarios well up front is what keeps the suite fast, deterministic, and worth reading.

### 1.1 Identify the boundaries the test crosses

For each scenario, name the boundaries. A scenario that doesn't cross a boundary belongs in the unit test suite, not here.

```
Scenario:     <one line — what end-to-end behaviour is being verified>
Boundary 1:   <e.g. proxy process ↔ stub process via Unix socket>
Boundary 2:   <e.g. main thread ↔ worker thread via GMainLoop>
Boundary 3:   <e.g. process ↔ on-disk sqlite db at /opt/usr/dbspace/...>
Real deps:    <list libraries that MUST run for real — glib, libsystemd,
               openssl, sqlite3, dns_sd, cynara, ...>
Test artefacts on FS: <e.g. /tmp/rpc-port-certs/*, /tmp/<pkg>_test_db/...>
Permissions / capabilities: <e.g. needs root? needs cynara policy?
                              runs in user session? needs systemd socket?>
```

### 1.2 Enumerate scenarios

For each boundary-crossing flow:

```
[S1] <Happy path>                  — assert: <observable outcome>
[S2] <Failure / negative path>     — assert: <error code + side-effect>
[S3] <Async event delivery>        — assert: <callback fired, payload matches, within timeout>
[S4] <Disconnect / cleanup>        — assert: <other side observed disconnect>
[S5] <Reconnect / re-listen>       — assert: <state recovers, no leaked fds/handles>
[S6] <Concurrency / ordering>      — assert: <no race, ordering preserved>
[S7] <Resource boundary>           — assert: <max instances, max payload, etc.>
[S8] <Auth / cert / policy fail>   — assert: <connection rejected with the right error>
```

### 1.3 Pick the timeout budget

Every scenario must finish (success or asserted failure) within a bounded timeout. Pick one budget for the whole fixture, store it as a `constexpr guint WAIT_TIMEOUT_MSEC` near the top of the file (5000 ms is the project default, see `rpc-port/test/integ_tests/rpc_port_tcp_test.cc`). Don't sprinkle ad-hoc `sleep()` calls — they're the #1 cause of flakes. Use `g_timeout_add` and `g_main_loop_quit` instead.

### 1.4 Sanity checklist before moving on

- Every scenario crosses at least one boundary listed in 1.1.
- Every async scenario has both a "callback fired" assertion *and* a "did not time out" assertion.
- Every test artefact on the filesystem has a teardown step that removes it (or a documented reason it must persist).
- Nothing in the plan requires *modifying* host system state (e.g. installing a system package, editing `/etc/`, restarting a system daemon). Tests that need that are SDB-driven device tests, not integration tests in this layout.
- The plan does not mention mocks, gmock, `EXPECT_CALL`, `MOCK_METHOD`, or `MOCK_HOOK_*`. If it does, you're writing a unit test — switch to `tizen-gtest-unit-test`.

If any item fails, expand the plan. Do not proceed to Phase 2.

---

## Phase 2 — Scaffold the directory

For a package `<pkg>`, integration tests live at:

```
<pkg>/test/integ_tests/                     # rpc-port style (preferred)
  ├── CMakeLists.txt
  ├── main.cc                                # InitGoogleTest + RUN_ALL_TESTS
  ├── <subject>_test.cc                      # one file per end-to-end subject
  ├── <subject>_test.cc                      # ...
  └── <optional>/
      ├── certs/mk_certs.sh                  # if the suite needs TLS certs
      └── res/                               # if the suite needs static fixtures
```

Some packages use `<pkg>/test/<subject>_tests/` (see `aul-1/test/app_control_tests/`) — that's an older, package-specific style. Match whichever style the package already uses; if there's nothing, prefer `test/integ_tests/`.

Also update:

```
<pkg>/test/CMakeLists.txt                    # ADD_SUBDIRECTORY(integ_tests)
<pkg>/CMakeLists.txt                         # SET(TARGET_<PKG>_INTEGTESTS ...)
<pkg>/packaging/<pkg>.spec                   # %package integtests + %files integtests
```

Templates for each of these files are in `assets/`. Copy them, then substitute the `<PKG>` / `<pkg>` / `<subject>` placeholders. Don't paraphrase the templates — they encode `-fPIE` / `-pie` flags, the `APPLY_PKG_CONFIG` macro, and the `INSTALL ... DESTINATION bin` rule, all of which CI relies on.

---

## Phase 3 — Write the test code

### 3.1 main.cc

Always the same content. Just google-test bootstrap. Copy `assets/main.cc.tpl` verbatim; do not add custom logging or signal handlers in `main` — fixture `SetUp/TearDown` is the right place.

### 3.2 Test fixture pattern (glib-mainloop driven)

This is the canonical pattern, lifted from `rpc-port/test/integ_tests/rpc_port_tcp_test.cc`. Use it whenever the API under test delivers results through callbacks:

```cpp
class <Subject>IntegTest : public ::testing::Test {
 public:
  void SetUp() override {
    mainloop_ = g_main_loop_new(nullptr, FALSE);
    // create real handles, register real callbacks, listen on real socket
  }

  void TearDown() override {
    // destroy real handles in reverse order, unref the mainloop, reset flags
    g_main_loop_unref(mainloop_);
    mainloop_ = nullptr;
  }

  void RunMainLoop(const char* phase) {
    timed_out_ = false;
    guint timeout_tag = g_timeout_add(
        WAIT_TIMEOUT_MSEC,
        [](gpointer data) -> gboolean {
          auto* p = static_cast<<Subject>IntegTest*>(data);
          p->timed_out_ = true;
          p->Finish();
          return G_SOURCE_REMOVE;
        },
        this);
    g_main_loop_run(mainloop_);
    if (timeout_tag > 0) g_source_remove(timeout_tag);
    ASSERT_FALSE(timed_out_) << "Timed out while waiting phase: " << phase;
  }

  void Finish() { g_main_loop_quit(mainloop_); }

 protected:
  GMainLoop* mainloop_ = nullptr;
  bool timed_out_ = false;
  // touch_*_event_cb_ flags — one per callback you want to assert
};
```

Three rules that are easy to get wrong:

1. **Always pair `g_main_loop_run` with `g_timeout_add`.** Never call `g_main_loop_run` without a timeout — a missed callback otherwise hangs CI forever.
2. **Quit the loop from inside the callback that completes the phase, not from the test body.** The test body assertions run *after* `RunMainLoop` returns. If you quit too early you'll miss the very thing you're trying to observe.
3. **Reset every `touch_*_event_cb_` flag in `TearDown`.** They're members on the fixture — gtest reuses the fixture instance across tests in the same suite if you derive in certain ways, and stale flags hide real failures.

### 3.3 Synchronous-API pattern

For APIs that block (e.g. `rpc_port_proxy_tcp_connect_sync`), drive them on a `std::thread` so the mainloop on the main thread can still dispatch the async events:

```cpp
int connect_ret = SOMETHING_ERROR_NONE;
std::thread t([&]() {
  connect_ret = blocking_call(...);
  if (connect_ret != ERROR_NONE) Finish();   // unblock the mainloop on failure
});
RunMainLoop("wait_blocking_call");
t.join();
ASSERT_EQ(connect_ret, ERROR_NONE);
```

Always `join` the thread before asserting — otherwise an asserted failure tears down the fixture while the thread is still touching its members, and the resulting flake will look like a memory bug.

### 3.4 Resource cleanup

Anything created on disk during `SetUp` (sqlite db, cert dir, socket file, fifo) must be removed in `TearDown` *and* in a `static void TearDownTestSuite()` if it's shared across cases. Don't rely on `/tmp` getting cleared — the same `gbs build` shell can run the suite back-to-back.

If the package needs certs (e.g. rpc-port TLS tests), ship a `certs/mk_certs.sh` and install it next to the binary in CMake (`INSTALL(PROGRAMS .../mk_certs.sh DESTINATION bin)`) so QA can regenerate them on the device.

### 3.5 What NOT to do in integration tests

- **No gmock.** No `EXPECT_CALL`, no `MOCK_METHOD`, no `MOCK_HOOK_*`, no `module_mock.hh`. If you find yourself writing one, you're writing a unit test in the wrong directory.
- **No `sleep()` / `usleep()` / `std::this_thread::sleep_for()` to wait for events.** Use `g_main_loop_run` + `g_timeout_add`. Sleeps are why CI flakes.
- **No hard-coded ports outside the registered range** (rpc-port uses ephemeral ports via `set_domain_inet`; if you must hard-code, pick a port > 50000 and document it).
- **No assumptions about the order of un-ordered async events.** If two callbacks may fire in either order, set two flags and assert on both *after* the second one fires.
- **No tests that only check "did not crash".** Each `TEST_F` must assert a return code, an event flag, or an observable side-effect.
- **No reliance on system services that aren't started by the test itself.** If the test needs amd / pkgmgr-server / data-provider-master, either start a private instance or document the systemd target the test depends on in the spec file's `Requires:`.
- **No live network calls.** Loopback (`127.0.0.1`) is fine. External hosts are not.

---

## Phase 4 — Wire the build

### 4.1 Top-level CMakeLists.txt

Add a target name variable and an `ADD_SUBDIRECTORY(test)` (which most packages already have):

```cmake
SET(TARGET_<PKG>_INTEGTESTS "<pkg>_integtests")
```

If the package's top-level `ENABLE_TESTING()` block lists unit tests with `ADD_TEST`, add the integ tests there too — but mark them as needing the device, not the build host. Most CI doesn't run integ tests at build time; that's expected.

### 4.2 test/CMakeLists.txt

```cmake
ADD_SUBDIRECTORY(unit_tests)
ADD_SUBDIRECTORY(integ_tests)
```

### 4.3 test/integ_tests/CMakeLists.txt

Copy `assets/CMakeLists.txt.tpl`, substitute `<TARGET_VAR>` and add the right `*_DEPS` entries to `APPLY_PKG_CONFIG`. The minimum is `GLIB_DEPS` and `GMOCK_DEPS` (gtest comes from the gmock package on Tizen).

Always:

- `INSTALL(TARGETS ... DESTINATION bin)` — the integtests RPM ships the binary in `/usr/bin/`.
- Set `COMPILE_FLAGS "-fPIE"` and `LINK_FLAGS "-pie"`. Tizen requires PIE for executables.
- `TARGET_LINK_LIBRARIES(... ${TARGET_<PKG>})` — link the real package library, not a static copy.

### 4.4 packaging/<pkg>.spec

Add three things — the `%package`, the `%description`, and the `%files`. Templates in `assets/spec_snippets.txt`. The convention (see `rpc-port/packaging/rpc-port.spec`):

```spec
%package integtests
Summary:    GTest for <pkg>
Group:      Development/Libraries
Requires:   %{name}

%description integtests
Integration GTest for <pkg>

# ... at the bottom, near the other %files sections ...

%files integtests
%{_bindir}/<pkg>_integtests
# any helper scripts the suite installs (e.g. mk_certs.sh)
```

The `%files` list must match the binaries the CMake `INSTALL(TARGETS ...)` actually puts under `%{_bindir}` — `gbs build` will fail with "unpackaged files" or "file not found" otherwise. After editing, run `gbs build -A x86_64 --include-all` (or whatever profile the user uses) and watch for those exact errors.

---

## Phase 5 — Run it

Tell the user the commands; do not run them automatically unless they ask:

```bash
# Local build
cd ~/.openclaw/workspace/gerrit/<pkg>
gbs build -A x86_64 --include-all

# After install on device/emulator
sdb root on
sdb shell <pkg>_integtests --gtest_filter='*'
sdb shell <pkg>_integtests --gtest_filter='<Subject>IntegTest.<scenario>_*'
```

For CI, add a `run-integtest.sh` next to `run-unittest.sh` if the package already has one — same pattern.

---

## Workflow summary (what to do when invoked)

When the user says "write integration tests for `<pkg>`" or "scaffold integ_tests for `<pkg>`":

1. **Check** `<pkg>/test/` — does `integ_tests/` already exist? If yes, follow its existing style. If no, create the layout from Phase 2.
2. **Read** the public header(s) and the implementation file(s) of the API under test, plus any existing `<pkg>/test/integ_tests/*_test.cc` so the new file matches.
3. **Output** the Phase 1 worksheet — boundaries, scenarios, timeout budget — for the user to confirm.
4. **Confirm** the worksheet against the section 1.4 checklist; iterate if any item fails.
5. **Generate** the test file(s), `main.cc` if missing, the `CMakeLists.txt` for `integ_tests/`, the parent `test/CMakeLists.txt` edit, the top-level `CMakeLists.txt` edit, and the `<pkg>.spec` edits.
6. **Tell** the user the build command and the on-device run command. Do not run them unless asked.

If the user says "just write the test, skip the planning", explain briefly: integration tests without a scenario plan reliably ship as flaky tests — the plan is what catches the missing timeout / ordering / cleanup issue before the suite is yellow-on-CI for a week. Offer a compressed one-line-per-row plan instead of skipping.

---

## Reference files

Read these as needed:

- `references/cmake_templates.md` — annotated `CMakeLists.txt` for `integ_tests/`, plus the parent-level edits.
- `references/spec_packaging.md` — annotated `%package integtests` / `%files integtests` snippets and how to debug "unpackaged files" errors.
- `references/glib_mainloop_patterns.md` — the `RunMainLoop` / `Finish` / `g_timeout_add` pattern with the gotchas spelled out.
- `references/scenario_catalog.md` — concrete examples of S1–S8 scenario types from rpc-port, aul-1, and message-port for inspiration.

## Asset templates

Copy these directly when scaffolding:

- `assets/main.cc.tpl`
- `assets/CMakeLists.txt.tpl`
- `assets/fixture_skeleton.cc.tpl`
- `assets/spec_snippets.txt`
