# Scenario catalog — what to actually test

Integration tests are valuable when they verify the *boundary-crossing*
behaviour that unit tests cannot reach. This catalog enumerates the kinds of
scenarios that are worth writing for the Tizen AppFW packages in this workspace,
with concrete examples from packages that already have integ tests.

Use this catalog to populate the Phase 1 worksheet (section 1.2 of SKILL.md).
Pick the scenario types that apply to your package; ignore the rest.

---

## S1 — Happy path round trip

A real client + real server complete a successful end-to-end exchange. This is
the smoke test — if it fails, the package is broken.

**Examples:**
- `rpc_port_event_tcp_connect_async` (rpc-port): proxy connects, stub fires
  `connected_event_cb`, proxy fires `connected_event_cb`, both touch flags
  set, no rejection.
- An aul-1 launch round trip: caller invokes `aul_launch_app`, target receives
  the app-control bundle, callback returns `AUL_R_OK`.

**Assertion shape:**
```cpp
ASSERT_EQ(ret, ERROR_NONE);
RunMainLoop("wait_round_trip");
ASSERT_TRUE(touch_request_received_cb_);
ASSERT_TRUE(touch_response_received_cb_);
```

---

## S2 — Negative path (boundary-rejected)

A real attempt is rejected at the boundary by design — wrong port name, wrong
appid, missing capability, expired cert. Asserts the *exact* error code, not
just "not zero".

**Examples:**
- `rpc_port_proxy_tcp_connect` to a port name the stub didn't register →
  rejected event fires.
- A message-port send to an unregistered remote port → `MESSAGE_PORT_ERROR_PORT_NOT_FOUND`.

**Why it's an integ test, not a unit test:** the rejection path goes through
the real socket / dbus, which is exactly the part that catches mismatches in
real deployments.

---

## S3 — Async event delivery

The API under test promises that a callback will fire when X happens; the test
makes X happen and asserts the callback was invoked. Always paired with a
timeout.

**Examples:**
- `rpc_port_event_tcp_disconnect1` (rpc-port): trigger destroy on the proxy
  side, observe `disconnected_event_cb` on the stub side.
- A notification broadcast → subscriber's `on_notification` callback fires
  with the right payload.

**Assertion shape:**
```cpp
trigger_event();
RunMainLoop("wait_event_delivery");
ASSERT_TRUE(touch_event_cb_);
ASSERT_EQ(received_payload_, expected_payload_);
```

---

## S4 — Cleanup / disconnect propagation

When one side disappears (process exits, socket closes, handle destroyed), the
other side must observe the disconnect and not leak resources.

**Examples:**
- Destroy proxy → stub sees disconnect.
- Destroy stub → proxy sees disconnect.
- Process death (the test forks a child holding the handle, kills it,
  observes the disconnect on the parent).

**Why it's an integ test:** unit tests would mock the disconnect signal and
miss the actual fd/handle cleanup that this verifies.

---

## S5 — Reconnect / re-listen

After a disconnect, can the same handle (or a fresh one) re-establish
the connection? This catches resource-leak bugs that S1 alone would miss.

**Examples:**
- Stub stops listening, restarts, proxy reconnects.
- TCP server rebinds to the same port after the previous client closes.

**Assertion shape:**
```cpp
// Phase 1: connect, disconnect.
RunMainLoop("wait_connect");
trigger_disconnect();
RunMainLoop("wait_disconnect");

// Phase 2: reconnect with fresh handles or after re-listen.
ResetTouchFlags();
trigger_reconnect();
RunMainLoop("wait_reconnect");
ASSERT_TRUE(touch_connected_event_cb_);
```

---

## S6 — Concurrency / ordering

Two operations whose ordering matters (or is allowed to be either order) are
exercised together. The test must not assume an ordering that the API doesn't
guarantee.

**Examples:**
- Two clients connect to the same stub at the same time.
- One side `send`s while the other side is still in `set_options` — must not
  drop the message or panic.

**Assertion shape:**
```cpp
// Don't assert on order — assert that both flags end up true.
trigger_op_a_async();
trigger_op_b_async();
RunMainLoop("wait_both");
ASSERT_TRUE(touch_a_) << "op A never completed";
ASSERT_TRUE(touch_b_) << "op B never completed";
```

---

## S7 — Resource boundary

The API documents a maximum (max payload, max instances, max queue depth);
the test confirms the limit is enforced and the failure mode is the documented
one (truncate vs. reject vs. block).

**Examples:**
- `rpc_port_send` with a payload larger than the documented limit.
- aul-1 queueing more than N pending launches.

**Assertion shape:**
```cpp
auto huge = MakePayload(MAX_SIZE + 1);
int ret = api_send(handle, huge);
ASSERT_EQ(ret, EXPECTED_OVERFLOW_ERROR);   // pin the contract, not just != 0
```

---

## S8 — Auth / cert / policy failure

Real cynara, real TLS, real cert chain — a test that asserts that an
unauthorized or improperly-credentialed call is rejected with the exact error.

**Examples:**
- TLS cert from a wrong CA → connection rejected at handshake.
- Cynara policy denies the operation → API returns `*_PERMISSION_DENIED`.

**Why it's an integ test:** cynara and openssl behaviour cannot be faithfully
unit-tested with mocks — the bug surface is in the real interaction with these
libraries' state machines.

---

## Choosing scenarios

For a new package's first integ test pass, write at least:

- **S1** (happy path, smoke).
- **S3** (async event delivery — the thing that most often regresses).
- **S4** (cleanup — the thing that most often leaks).

S2, S5, S6, S7, S8 are added as the API surface and risk profile grows.
Don't write all 8 just because the catalog has 8 sections — pick what
actually protects against a plausible regression.

## Anti-patterns to drop from the worksheet

- **Re-implementing a unit test in integ_tests/** — if the scenario is "call
  function X with NULL, expect ERROR_INVALID_PARAMETER", that's a unit test.
  The boundary it crosses is just the function-call ABI, which mocks already
  exercise faithfully. Move it to `unit_tests/`.
- **"Smoke test that the binary launches"** — gtest's own `RUN_ALL_TESTS()`
  framework is already that test. Don't write `TEST(Smoke, BinaryStarts) {}`.
- **Tests that depend on a specific QA device's state** — e.g. "an app called
  `org.tizen.foo` is installed". Either install/uninstall it as part of
  `SetUp`, or document the prerequisite in the spec file's comment block.
