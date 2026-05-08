# Example walkthrough — adding an integ test to rpc-port

This is a fully worked example using `rpc-port` because it's the package whose
existing integ tests are the gold reference. New packages should mimic this
shape.

## Scenario

We want to verify that when a TCP-mode rpc-port proxy is created and the stub
listens, an outbound `rpc_port_proxy_tcp_connect` from a fresh proxy reaches
the stub and both sides observe `connected_event_cb`.

(This is essentially a re-statement of the existing
`RpcPortTcpBase.rpc_port_event_tcp_connect_async` — used here because the
shape is small and complete.)

## Phase 1 — Worksheet

```
Scenario:     TCP-mode proxy connects to listening stub on loopback.
Boundary 1:   proxy process ↔ stub process via TCP socket on 127.0.0.1.
Boundary 2:   amd registration ↔ proc info table (real call to
              rpc_port_register_proc_info).
Boundary 3:   main thread ↔ glib mainloop dispatching async callbacks.
Real deps:    glib, openssl3 (for TLS-unrelated socket ops), aul (for appid
              resolution), libsystemd (socket activation).
Test artefacts on FS: none for this scenario (cert tests live elsewhere).
Permissions:  none beyond loopback bind + appid registration.

Scenarios:
  [S1] happy path — both proxy and stub see connected, no rejected event.
       assert: touch_proxy_connected_event_cb_ && touch_stub_connected_event_cb_
               && !touch_proxy_rejected_event_cb_

Timeout budget: WAIT_TIMEOUT_MSEC = 5000 (project default).
```

Checklist:
- [x] Crosses real boundary (TCP loopback).
- [x] Async — has timeout and "did not time out" assertion.
- [x] No FS artefacts to clean up.
- [x] No host-system mutation.
- [x] No mocks in the plan.

Plan passes. Move on.

## Phase 2 — Files added

```
rpc-port/test/integ_tests/rpc_port_tcp_test.cc       # already exists
rpc-port/test/integ_tests/main.cc                    # already exists
rpc-port/test/integ_tests/CMakeLists.txt             # already exists
rpc-port/test/CMakeLists.txt                         # already has ADD_SUBDIRECTORY
rpc-port/CMakeLists.txt                              # already SETs TARGET_RPC_PORT_INTEGTESTS
rpc-port/packaging/rpc-port.spec                     # already has %package + %files integtests
```

(For a new package starting from scratch, all of these would be created. Use
the templates in `assets/`.)

## Phase 3 — The test (excerpt from the real file)

```cpp
TEST_F(RpcPortTcpBase, rpc_port_event_tcp_connect_async) {
  int ret = rpc_port_stub_add_connected_event_cb(
      stub_handle_,
      [](const char* sender, const char* instance, void* data) {
        RpcPortTcpBase* p = static_cast<RpcPortTcpBase*>(data);
        p->touch_stub_connected_event_cb_ = true;
      },
      this);
  ASSERT_EQ(ret, 0);

  rpc_port_register_proc_info(TEST_APPID, nullptr);
  ret = rpc_port_stub_listen(stub_handle_);
  ASSERT_EQ(ret, 0);

  ret = rpc_port_proxy_add_connected_event_cb(
      proxy_handle_,
      [](const char* ep, const char* port_name, rpc_port_h port, void* data) {
        RpcPortTcpBase* p = static_cast<RpcPortTcpBase*>(data);
        p->touch_proxy_connected_event_cb_ = true;
        p->Finish();                          // <-- quit only when phase done
      },
      this);
  ASSERT_EQ(ret, 0);

  ret = rpc_port_proxy_tcp_connect(proxy_handle_, "127.0.0.1", TEST_APPID,
                                   "tcp_test_port");
  ASSERT_EQ(ret, 0);
  RunMainLoop("wait_connect_async");          // <-- timeout-armed wait

  ASSERT_TRUE(touch_proxy_connected_event_cb_);
  ASSERT_TRUE(touch_stub_connected_event_cb_);
  ASSERT_FALSE(touch_proxy_rejected_event_cb_);
}
```

Things to notice:

- The stub callback sets a flag *but does not call Finish()* — only the proxy
  callback (which fires second) drives the loop quit. That's deliberate: if
  the proxy callback fired first the test would still pass once the stub one
  fires, but the test was written knowing the natural ordering. If you don't
  know the order, count callbacks and Finish() when both have fired (see
  `references/glib_mainloop_patterns.md` §4.2).
- The lambda captures `this` via the user-data param, not via C++ closure
  capture — gtest fixtures are objects, and the C ABI of the rpc-port
  callbacks expects `void*` user data. Passing `this` is the canonical bridge.
- Every step asserts its return code with `ASSERT_EQ(ret, 0)` so a setup
  failure doesn't masquerade as the actual test result.

## Phase 4 — Build + run

```bash
cd ~/.openclaw/workspace/gerrit/rpc-port
gbs build -A x86_64 --include-all

# After install
sdb root on
sdb shell rpc-port_integtests --gtest_filter='RpcPortTcpBase.*'
```

Expected output: 1 test passes, no timeout, fixture teardown clean.
