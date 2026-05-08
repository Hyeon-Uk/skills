# GLib mainloop patterns for integration tests

Integration tests in this workspace are *event-driven*: the API under test
delivers results through callbacks, and the test verifies that the right
callbacks fire with the right payloads. The standard mechanism is `GMainLoop`.
The reference implementation is `rpc-port/test/integ_tests/rpc_port_tcp_test.cc`.

This document spells out the pattern, the gotchas, and what each piece is
actually for. Read it before writing your first integ test in this codebase —
the gotchas in section 4 are why the existing tests are reliable.

---

## 1. The fixture skeleton (always the same shape)

```cpp
#include <glib.h>
#include <gmock/gmock.h>
#include <gtest/gtest.h>

namespace { constexpr guint WAIT_TIMEOUT_MSEC = 5000; }

class FooIntegBase : public ::testing::Test {
 public:
  void SetUp() override {
    mainloop_ = g_main_loop_new(nullptr, FALSE);
    // create real handles, register callbacks that set flags + Finish()
  }
  void TearDown() override {
    // destroy real handles in reverse order
    g_main_loop_unref(mainloop_); mainloop_ = nullptr;
    timed_out_ = false;
    // reset every touch_*_event_cb_ flag
  }

  void RunMainLoop(const char* phase) {
    timed_out_ = false;
    guint tag = g_timeout_add(WAIT_TIMEOUT_MSEC,
        [](gpointer d) -> gboolean {
          auto* p = static_cast<FooIntegBase*>(d);
          p->timed_out_ = true;
          p->Finish();
          return G_SOURCE_REMOVE;
        }, this);

    g_main_loop_run(mainloop_);

    if (tag > 0) g_source_remove(tag);
    ASSERT_FALSE(timed_out_) << "Timed out while waiting phase: " << phase;
  }

  void Finish() { g_main_loop_quit(mainloop_); }

 protected:
  GMainLoop* mainloop_ = nullptr;
  bool timed_out_ = false;
  bool touch_connected_event_cb_ = false;     // one flag per async event
  // ...
};
```

Why this shape:

- **`g_main_loop_new(nullptr, FALSE)`** uses the default main context. Don't
  create a new `GMainContext` unless you have a specific reason — the APIs
  under test typically attach their sources to the default context, and a
  fresh context will silently never dispatch them.
- **`g_main_loop_unref` in `TearDown`** is paired with `g_main_loop_new`. If
  the loop is still running during teardown (because a previous test asserted
  on a flag and never quit the loop), the next test will hang. Pair `new` with
  `unref` exactly once per test.
- **Reset every flag** — gtest fixture instances *are* recreated per test in
  the standard `::testing::Test` model, but the flags on a `static` member or
  a base class with a singleton instance pattern (the codebase mixes both)
  will leak across tests. Resetting in `TearDown` is the safe default.

---

## 2. The `RunMainLoop("phase")` helper

Two responsibilities:

1. Arm a watchdog (`g_timeout_add`) so the test can never hang forever.
2. Assert at the end that we exited because of `Finish()`, not because of the
   watchdog.

The `phase` string is *only* there to land in the failure message — pick a
descriptive name like `"wait_connect_async"` or `"wait_disconnect_after_destroy"`.
When CI fails six months from now and someone is reading the log, that string
is what tells them which await blew up.

`g_source_remove(tag)` runs only on the success path — if the timeout fired,
its handler already returned `G_SOURCE_REMOVE` and the source is already gone.
Calling `g_source_remove` on a removed source is a glib `CRITICAL` warning;
guarding with `if (tag > 0)` is enough.

---

## 3. Driving synchronous APIs

If the API under test blocks (e.g. `_sync` variants), call it on a thread so
the mainloop on the main thread can dispatch the events the blocking call is
waiting for:

```cpp
int call_ret = ERROR_NONE;
std::thread t([&]() {
  call_ret = blocking_call(...);
  if (call_ret != ERROR_NONE) Finish();   // unblock the mainloop on failure
});
RunMainLoop("wait_blocking_call");
t.join();
ASSERT_EQ(call_ret, ERROR_NONE);
```

Always `t.join()` before the asserts. If you assert first and the assertion
fails, the fixture starts tearing down while the thread is still touching
fixture members — the resulting use-after-free is interpreted by humans as
"a flaky test", which is much harder to debug than a deterministic one.

---

## 4. Gotchas (the real reasons tests flake)

### 4.1 Quitting from the wrong place

`g_main_loop_quit` from the test body, after `g_main_loop_run` already returned,
is a no-op against the next loop iteration. Quit only from inside the callback
that *completes* the phase you're waiting for.

### 4.2 Quitting too early

If two callbacks must both fire to constitute "phase complete", quit from a
counter that decrements in each callback, not from whichever fires first:

```cpp
int pending = 2;
auto on_event = [&](){
  touch_a_ = true;
  if (--pending == 0) Finish();
};
```

Or set both flags and `Finish()` in the second one only.

### 4.3 Forgetting the timeout

Calling `g_main_loop_run` without `g_timeout_add` is the most common cause of
"the CI just hangs". The fixture provides `RunMainLoop` precisely so you don't
have to remember.

### 4.4 Re-entering the loop

Don't call `g_main_loop_run` from inside a callback. Set the flag, call
`Finish()`, return, and let the next `TEST_F` start the loop again.

### 4.5 Not pairing `g_source_remove` with `g_timeout_add`

If your phase succeeds but you never remove the timeout source, it may fire
during a subsequent phase of the same test. The `RunMainLoop` helper handles
this; if you write your own loop driver, do the same.

### 4.6 Returning `G_SOURCE_CONTINUE` from a one-shot

`g_timeout_add` callbacks should return `G_SOURCE_REMOVE` (== `FALSE`) when
they're done — otherwise the timer fires again 5 seconds later and you've
introduced a phantom watchdog the next test inherits.

### 4.7 Ordering assumptions across processes

On a multi-process boundary (proxy + stub), don't assume the order of "stub
saw connect" vs "proxy saw connect". Both flags must be set before you assert,
or you'll get a heisenbug that only fails on slower hardware.

---

## 5. Cleanup checklist before each `TEST_F` ends

- Every handle/socket created in `SetUp` is destroyed in `TearDown`.
- Every `g_source_id` from `g_timeout_add` / `g_idle_add` has been removed.
- Every `std::thread` you launched has been `join()`'d.
- Every flag has been reset to `false`.
- Every file/dir created on disk has been removed (or registered with a
  `static void TearDownTestSuite()` for shared fixtures).
- The mainloop is unref'd exactly once and set back to `nullptr`.

If you can answer yes to all six, the suite will hold up under repeated runs.
