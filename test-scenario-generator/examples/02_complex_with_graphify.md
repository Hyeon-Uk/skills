# Example 2 — Complex function, using `graphify` to inform corners

Target: a stateful create-handle API in a Tizen package. Has many
callers, many callees, and the corner cases depend on how callers
sequence calls. `graphify` earns its keep here.

Imagined source (`<pkg>/src/widget_disable.c`):

```c
int widget_service_get_widget_disabled(const char *widget_id, bool *is_disabled)
{
  if (widget_id == NULL || is_disabled == NULL)         // line 14
    return WIDGET_ERROR_INVALID_PARAMETER;

  bool feature = false;
  if (system_info_get_platform_bool(KEY, &feature) != 0 || !feature)  // line 18
    return WIDGET_ERROR_NOT_SUPPORTED;

  if (cynara_initialize(...) != CYNARA_API_SUCCESS)     // line 22
    return WIDGET_ERROR_PERMISSION_DENIED;
  if (cynara_check(...) != CYNARA_API_ACCESS_ALLOWED)   // line 26
    return WIDGET_ERROR_PERMISSION_DENIED;
  cynara_finish(...);                                    // line 28

  sqlite3_stmt *stmt;
  if (sqlite3_prepare_v2(...) != SQLITE_OK)              // line 32
    return WIDGET_ERROR_IO_ERROR;
  int rc = sqlite3_step(stmt);                           // line 34
  if (rc == SQLITE_DONE) {
    sqlite3_finalize(stmt);                              // line 36
    return WIDGET_ERROR_NOT_EXIST;
  }
  if (rc != SQLITE_ROW) {                                // line 39
    sqlite3_finalize(stmt);
    return WIDGET_ERROR_IO_ERROR;
  }
  *is_disabled = sqlite3_column_int(stmt, 0);            // line 43
  sqlite3_finalize(stmt);
  return WIDGET_ERROR_NONE;                              // line 45
}
```

---

## Phase 1 — Map (with graphify)

```
Skill(skill="graphify", args="<pkg>/src/")
  → produced graph.json + audit.html under .graphify/
```

Filtering the graph to nodes within distance ≤ 2 of
`widget_service_get_widget_disabled`:

```
Inbound (callers):
  - widget_service_set_widget_disabled       (writes the same row)
  - widget_disable_event_cb                  (called from app-com callback)
  - test_widget_service.cc::TEST_F(...)      (existing test)

Outbound (callees):
  - system_info_get_platform_bool            (Tizen platform-info)
  - cynara_initialize / check / finish       (privilege)
  - sqlite3_prepare_v2 / step / column_int / finalize
  - widget_db_path() (internal helper) → tzplatform_mkpath

Cluster: "widget-service / disable"  (community of 6 functions)

Notable graph observations:
  - `widget_service_set_widget_disabled` writes the same row this
    function reads → caller-ordering corner case (write-then-read).
  - `widget_disable_event_cb` calls this function from a glib callback
    in the main loop → reentrancy / mainloop corner case.
  - No other module reads the row → no inter-package coupling.
```

The two graph observations directly fuel two corner cases (`[C1]`,
`[C2]`) in Phase 3 that pure source-reading would miss.

---

## Phase 2 — Analyze

### 2.1 Branch enumeration

| #   | Line | Predicate                                       | Action |
|-----|------|-------------------------------------------------|--------|
| B1  | 14   | `widget_id == NULL \|\| is_disabled == NULL`    | return INVALID_PARAMETER |
| B2  | 18   | `system_info_get_platform_bool` failed OR `*value == false` | return NOT_SUPPORTED |
| B3  | 22   | `cynara_initialize` != SUCCESS                  | return PERMISSION_DENIED |
| B4  | 26   | `cynara_check` != ALLOWED                       | return PERMISSION_DENIED |
| B5  | 32   | `sqlite3_prepare_v2` != SQLITE_OK               | return IO_ERROR |
| B6  | 34–37| `sqlite3_step` == SQLITE_DONE (no row)          | return NOT_EXIST |
| B7  | 39   | `sqlite3_step` != ROW && != DONE                | return IO_ERROR |
| B8  | 43–45| success                                          | return NONE |

### 2.2 Errno map

| Return                      | Predicate                              | Branches |
|-----------------------------|----------------------------------------|----------|
| `WIDGET_ERROR_NONE`         | success                                | B8       |
| `WIDGET_ERROR_INVALID_PARAMETER` | widget_id NULL or is_disabled NULL | B1       |
| `WIDGET_ERROR_NOT_SUPPORTED`| platform feature off / sysinfo failed  | B2       |
| `WIDGET_ERROR_PERMISSION_DENIED` | cynara init failed                | B3       |
| `WIDGET_ERROR_PERMISSION_DENIED` | cynara check denied               | B4       |
| `WIDGET_ERROR_NOT_EXIST`    | DB has no row for widget_id            | B6       |
| `WIDGET_ERROR_IO_ERROR`     | sqlite prepare failed                  | B5       |
| `WIDGET_ERROR_IO_ERROR`     | sqlite step returned BUSY/LOCKED/IOERR | B7       |

### 2.3 External dependencies

| Callee | Failure modes | Mapped errno | Status |
|--------|---------------|---------------|--------|
| `system_info_get_platform_bool` | nonzero rc / `*value=false` | NOT_SUPPORTED | propagated |
| `cynara_initialize` | OOM / conn-err / config-err | PERMISSION_DENIED | propagated (collapsed — flag) |
| `cynara_check` | DENIED / OUT_OF_MEM / TIMEOUT | PERMISSION_DENIED | propagated (collapsed — flag) |
| `cynara_finish` | best-effort | (none) | swallowed |
| `sqlite3_prepare_v2` | NOMEM / IOERR / FULL / READONLY / CORRUPT | IO_ERROR | propagated (collapsed — flag) |
| `sqlite3_step` | BUSY / LOCKED / IOERR / FULL / CORRUPT / ROW / DONE | IO_ERROR or NOT_EXIST | propagated (collapsed — flag) |
| `sqlite3_finalize` | non-fatal | (none) | swallowed |
| `widget_db_path()` (internal) | failure → returns sentinel | IO_ERROR upstream | inlined |

### 2.4 State catalogue

- **Preconditions**: package's DB must exist (created during init).
- **Side effects on success**: `*is_disabled` populated; no DB writes;
  cynara session opened and closed within the call.
- **Invariants**: callable from mainloop callbacks (per graph). Not
  documented thread-safe — flag.
- **Cleanup**: `cynara_finish` always runs after init; `sqlite3_finalize`
  always runs after prepare. No leaks.

---

## Phase 3 — Scenarios

### Success [P]

| ID | Inputs | Setup / Mocks | Expected | Asserts |
|----|--------|---------------|----------|---------|
| P1 | widget_id="org.tizen.gallery.widget", out=&v | sysinfo true, cynara ALLOW, DB has row(disabled=true) | NONE | `*v == true` |
| P2 | same id, out=&v | DB has row(disabled=false) | NONE | `*v == false` |

### Failure [N]

| ID  | Inputs / Setup | Expected | Why |
|-----|----------------|----------|-----|
| N1  | widget_id=NULL                                                  | INVALID_PARAMETER     | B1 |
| N2  | widget_id="x", is_disabled=NULL                                 | INVALID_PARAMETER     | B1 |
| N3  | mock sysinfo `*value=false`                                     | NOT_SUPPORTED         | B2 |
| N3b | mock sysinfo rc != 0                                            | NOT_SUPPORTED         | B2 (collapsed) |
| N4  | mock `cynara_initialize` → CYNARA_API_OUT_OF_MEMORY             | PERMISSION_DENIED     | B3 (collapsed-flag) |
| N4b | mock `cynara_initialize` → CYNARA_API_UNKNOWN_ERROR             | PERMISSION_DENIED     | B3 (collapsed-flag) |
| N5  | mock `cynara_check` → CYNARA_API_ACCESS_DENIED                  | PERMISSION_DENIED     | B4 |
| N5b | mock `cynara_check` → CYNARA_API_OUT_OF_MEMORY                  | PERMISSION_DENIED     | B4 (collapsed-flag) |
| N6  | mock `sqlite3_prepare_v2` → SQLITE_IOERR                        | IO_ERROR              | B5 |
| N6b | mock `sqlite3_prepare_v2` → SQLITE_CORRUPT                      | IO_ERROR              | B5 (collapsed-flag) |
| N7  | DB has no row for widget_id                                     | NOT_EXIST             | B6 |
| N8  | mock `sqlite3_step` → SQLITE_BUSY                               | IO_ERROR              | B7 |
| N8b | mock `sqlite3_step` → SQLITE_LOCKED                             | IO_ERROR              | B7 (collapsed-flag) |

### Edge [E]

| ID | Input shape                                  | Expected         |
|----|----------------------------------------------|------------------|
| E1 | widget_id=""                                 | NOT_EXIST (DB lookup miss) — verify, not assume |
| E2 | widget_id length = MAX_WIDGET_ID_LEN         | NONE (boundary)  |
| E3 | widget_id length = MAX + 1                   | NOT_EXIST or INVALID_PARAMETER — depends on guard |
| E4 | widget_id with embedded NUL                  | NOT_EXIST (strlen-based lookup) |
| E5 | widget_id non-ASCII (UTF-8)                  | NONE if registered with same bytes |

### Corner [C] — informed by graphify

| ID | Scenario | Expected | Source |
|----|----------|----------|--------|
| C1 | `set_widget_disabled("x", true)` immediately followed by `get_widget_disabled("x", &v)` | NONE; `v == true` (read-after-write) | graphify: sibling caller writes the same row |
| C2 | Called from a glib mainloop callback (`widget_disable_event_cb`) | works; no deadlock | graphify: mainloop caller |
| C3 | Two threads call `get_widget_disabled` simultaneously | both succeed | sqlite/cynara serialization implicit; flag if not documented |
| C4 | Called before package init (DB not present) | IO_ERROR | precondition violation |

---

## Phase 4 — §7 / §8 (excerpts)

```markdown
## Coverage check
- [x] Every distinct return value in §3 has at least one [N] row
- [x] Every NULL-able pointer parameter has at least one [N] row
- [ ] Every numeric parameter has boundary rows  ← N/A (no numeric params)
- [x] Every external dependency in §4 has its failures mapped — collapsed mappings split into N3b, N4b, N5b, N6b, N8b
- [ ] Every documented invariant has at least one [C] row  ← thread-safety not documented; C3 tentative — flag

## Open questions
- Is `cynara_initialize`'s OUT_OF_MEMORY meant to surface as
  PERMISSION_DENIED or as a separate NO_MEMORY? Currently collapsed.
- Is the API documented as thread-safe? C3 assumes yes; no docs
  found. Route to API owner.
- E1 (empty string) lookup behavior is implicit — lookup misses, but
  is that intentional? Documenting either way would help callers.
```

---

## Why graphify mattered here

Without it, [C1] and [C2] would have been missed — they require
seeing the surrounding *callers*, not just the function's source.
The errno map in Phase 2 is grep-driven and would have been the same
either way; the graph's value is the corner cases.

For functions where the graph would just confirm what a 30-second
grep would tell you (Example 1's `buf_copy`), skip graphify. For
functions embedded in a state machine or callback web (this example),
run it.
