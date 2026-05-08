# Scenario document — canonical schema

This is the exact structure to emit at the end of Phase 4. The skill's
downstream consumers (the user, downstream test-authoring tools, code
review) all rely on this format being stable.

---

## File header

```markdown
# Scenarios — <fully-qualified target>

_Generated: YYYY-MM-DD by test-scenario-generator_
_Source: <path>:<line-range>_
```

Date and source are mandatory because the document goes stale as the
code changes; readers need to know when it was generated.

---

## §1 Context

```markdown
## Context

| Field | Value |
|-------|-------|
| Target signature | `int foo_create(const char *id, foo_h *out)` |
| File             | `<pkg>/src/foo.c` (lines 10–58) |
| Public header    | `<pkg>/include/foo.h` |
| Visibility       | `EXPORT_API` / `static` / `private:` / ... |
| Callers          | `bar_setup`, `qux_init` (3 call sites total) |
| Callees          | `g_malloc0`, `sqlite3_*`, `cynara_check`, `system_info_get_platform_bool` |
| Cluster          | _from graphify, or "not run"_ |
```

If the target is `static` or `private:`, **stop and warn** — this skill
is for testable surfaces. Private/static helpers are exercised
transitively, not directly.

---

## §2 Branch enumeration

```markdown
## Branch enumeration

| #  | Line | Predicate                                    | Action                  |
|----|------|----------------------------------------------|-------------------------|
| B1 | 12   | `id == NULL \|\| out == NULL`                | `return INVALID_ARG`    |
| B2 | 16   | (B1 false) — main path                       | continue                |
| B3 | 18   | `g_malloc0(...) == NULL`                     | `return NO_MEMORY`      |
| B4 | 24   | `cynara_check(...) != ALLOWED`               | `goto cleanup; return PERM_DENIED` |
| B5 | 32   | `db_lookup(id) == 0` (no row)                | `return NOT_FOUND`      |
| B6 | 38   | `sqlite3_step != ROW && != DONE`             | `return IO_ERROR`       |
| B7 | 48   | success — populate `*out`                     | `return NONE`           |
```

Rules:
- IDs are `B1`, `B2`, ... — sequential, never reused.
- Every `return` in the source maps to exactly one Bn.
- Compound predicates (`a || b`) stay on one row.

---

## §3 Errno map

```markdown
## Errno map

| Return code      | Predicate (from §2)                          | Branches |
|------------------|----------------------------------------------|----------|
| `FOO_ERROR_NONE` | success path                                  | B7       |
| `INVALID_ARG`    | `id == NULL \|\| out == NULL`                | B1       |
| `NO_MEMORY`      | `g_malloc0` returned NULL                     | B3       |
| `PERM_DENIED`    | cynara denied                                 | B4       |
| `NOT_FOUND`      | no DB row for `id`                            | B5       |
| `IO_ERROR`       | sqlite step returned BUSY / LOCKED / IOERR    | B6       |
```

If the same return code appears under multiple predicates (e.g.
INVALID_ARG for both `id==NULL` and `out==NULL`), keep one row per
predicate so the failure scenarios in §6 can pin each separately.

---

## §4 External dependencies

```markdown
## External dependencies

| Callee                        | Documented failure modes                  | Mapped errno   | Status      |
|-------------------------------|-------------------------------------------|----------------|-------------|
| `g_malloc0`                   | NULL on OOM                               | NO_MEMORY      | propagated  |
| `cynara_initialize`           | nonzero on alloc/conn failure             | PERM_DENIED    | propagated (collapsed) |
| `cynara_check`                | DENIED / OUT_OF_MEM / TIMEOUT             | PERM_DENIED    | propagated (collapsed — flag) |
| `sqlite3_step`                | BUSY / LOCKED / IOERR / FULL / CORRUPT    | IO_ERROR       | propagated (collapsed — flag) |
| `system_info_get_platform_bool` | `*value=false` (feature off)            | NOT_SUPPORTED  | propagated  |
| `tzplatform_mkpath`           | rare; returns sentinel                    | (none)         | swallowed — flag |
| `g_strdup`                    | NULL on OOM                               | NO_MEMORY      | propagated  |
```

"Collapsed" means multiple distinct callee failures map to one target
errno — these become **multiple scenarios** in §6 even though the
target's return is the same, because each callee path has its own
predicate to drive.

"Swallowed" means the callee can fail but the target ignores it.
Always flag in §8 Open Questions.

---

## §5 State catalogue

```markdown
## State catalogue

- **Preconditions**:
  - `<module>_init()` must have been called.
  - `cynara` subsystem reachable (or mocked).
- **Side effects on success**:
  - Allocates a new `foo_h`; ownership transfers to caller.
  - Increments internal handle counter.
- **Invariants**:
  - Callable from any thread; uses internal mutex (line 21).
  - Idempotent w.r.t. `id`: same `id` returns the cached handle.
- **Cleanup obligations**:
  - On error, `*out` is unmodified; no leaks.
```

Each invariant generates a corner case in §6.4.

---

## §6 Scenarios

### §6.1 Success `[P]`

```markdown
### Success [P]

| ID  | Inputs                                | Setup / Mocks                                                   | Expected return | Side-effects to assert |
|-----|---------------------------------------|------------------------------------------------------------------|-----------------|-------------------------|
| P1  | `id="real_id"`, `out=&h`              | DB has row for "real_id"; cynara mocked ALLOWED; sysinfo true   | `NONE`          | `*out != NULL`; handle.id == "real_id"; counter++ |
| P2  | `id="cached_id"` (already created)    | second call with same id                                         | `NONE`          | `*out` points to cached entry; no new alloc |
```

### §6.2 Failure `[N]` — one row per errno predicate

```markdown
### Failure [N] — one per errno predicate

| ID  | Inputs                  | Setup / Mocks                          | Expected return    | Why this row exists (cite §2 / §3) |
|-----|-------------------------|----------------------------------------|--------------------|-------------------------------------|
| N1  | `id=NULL`, `out=&h`     | —                                      | `INVALID_ARG`      | B1 / errno-map: id NULL              |
| N2  | `id="x"`, `out=NULL`    | —                                      | `INVALID_ARG`      | B1 / errno-map: out NULL             |
| N3  | `id="x"`, `out=&h`      | mock `g_malloc0` → NULL                | `NO_MEMORY`        | B3                                   |
| N4  | `id="x"`, `out=&h`      | mock `cynara_check` → DENIED            | `PERM_DENIED`      | B4 / cynara DENIED                   |
| N4b | `id="x"`, `out=&h`      | mock `cynara_check` → TIMEOUT           | `PERM_DENIED`      | B4 / cynara TIMEOUT (collapsed-flag) |
| N5  | `id="missing"`, `out=&h`| DB has no row                          | `NOT_FOUND`        | B5                                   |
| N6  | `id="x"`, `out=&h`      | mock `sqlite3_step` → BUSY              | `IO_ERROR`         | B6                                   |
| N6b | `id="x"`, `out=&h`      | mock `sqlite3_step` → CORRUPT           | `IO_ERROR`         | B6 (collapsed-flag)                  |
| N7  | `id="x"`, `out=&h`      | mock `system_info_*` → `*value=false`   | `NOT_SUPPORTED`    | (per §4)                             |
```

Note `N4b` and `N6b`: when §4 flags collapsed mappings, you produce one
row per *distinct callee failure code*, even if they return the same
target errno. These rows often expose latent bugs ("was supposed to
behave the same but doesn't").

### §6.3 Edge `[E]` — boundary values

```markdown
### Edge [E]

| ID | Input shape                           | Expected | Notes                                  |
|----|---------------------------------------|----------|----------------------------------------|
| E1 | `id=""` (empty)                       | `INVALID_ARG` | Same as N1 if guard treats "" as NULL; otherwise own row |
| E2 | `id` length = `MAX_ID_LEN`            | `NONE`   | boundary, supported                    |
| E3 | `id` length = `MAX_ID_LEN + 1`        | `INVALID_ARG` | rejected at guard                      |
| E4 | `id` contains embedded `\0`           | `INVALID_ARG` | strlen vs raw bytes contract           |
| E5 | `id` contains UTF-8 4-byte sequence   | `NONE`   | (or document encoding contract)        |
```

If an edge is already covered by an `[N]` row, write "covered by N1"
in the row instead of repeating the assertion — but keep the row so
the boundary is documented.

### §6.4 Corner `[C]` — state and ordering

```markdown
### Corner [C]

| ID | Scenario                                              | Expected                | Source (cite §5) |
|----|-------------------------------------------------------|--------------------------|------------------|
| C1 | `init`→`create(x)`→`release(x)`→`create(x)` again      | second create returns NONE; fresh handle | §5 invariant: idempotent on id |
| C2 | `create(x)` without prior `init`                       | `INVALID_ARG`           | §5 precondition |
| C3 | Two threads both call `create("x")` concurrently       | exactly one cache entry; no leak | §5 invariant: thread-safe |
| C4 | `create` registers callback; caller frees handle while callback in flight | callback must not fire | §5 cleanup |
| C5 | `release(handle)`; `create(handle)` — use-after-free   | `INVALID_ARG`           | §5 cleanup |
```

If the API contract does NOT document the expected behavior for a
corner case, do not invent one. Move the row to §8 Open Questions.

---

## §7 Coverage check

```markdown
## Coverage check

- [x] Every distinct return value in §3 has at least one [N] row
- [x] Every NULL-able pointer parameter has at least one [N] row
- [x] Every numeric/length parameter has 0, max, max+1 rows in [E]
- [x] Every external dependency in §4 with status "propagated" has at least one [N] row
- [ ] Every documented invariant in §5 has at least one [C] row  ← TODO: thread-safety claim has no [C]
- [x] Every collapsed mapping in §4 has one [N] per distinct callee code
```

The skill must fill these in honestly. An unchecked box is fine — it
tells the user what is still missing. A checked box that is wrong is
worse than not checking the box at all.

---

## §8 Open questions

```markdown
## Open questions

- The `cynara_check` TIMEOUT case maps to `PERM_DENIED` — is this
  intentional, or should it be a distinct `TIMEOUT` errno? (No
  documentation found; flag for the API owner.)
- `tzplatform_mkpath` failure is swallowed at line 21. Is this safe?
- Thread-safety is claimed in the docstring but no mutex is visible in
  the source — verify whether the surrounding caller holds a lock.
```

Each open question should:
- Be specific (cite a line or §).
- Have an owner the user can route it to (or be left for the user to
  decide).
- Not block the document — flag and continue.

---

## §9 Handoff (optional)

```markdown
## Handoff

Each row in §6 should become one test in whatever framework the team
uses. The row's predicate is the test's setup; the expected return is
its assertion.

Suggested test names (using gtest-style _P/_N suffixes — adapt to your
framework):
  foo_create_P              — from P1
  foo_create_P_cached       — from P2
  foo_create_N              — covers N1+N2 (same errno)
  foo_create_N_no_memory    — from N3
  ...
```

This section is optional; include it when the user has indicated they
want to proceed to test code, and only after asking which framework
they intend to use.
