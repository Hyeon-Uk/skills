# Example 1 — Simple C function (no graphify)

Target: a small leaf utility. The function is short, callers are few,
and there is no need to invoke `graphify` — direct grep gives us
everything.

Imagined source (`<pkg>/src/buf.c`):

```c
int buf_copy(const char *src, size_t src_len, char *dst, size_t dst_cap)
{
  if (src == NULL || dst == NULL)              // line 12
    return BUF_ERROR_INVALID_ARG;
  if (src_len == 0)                             // line 14
    return BUF_ERROR_NONE;                      // copy nothing
  if (src_len > dst_cap)                        // line 16
    return BUF_ERROR_OVERFLOW;
  if (memchr(src, '\0', src_len) != NULL)       // line 19
    return BUF_ERROR_INVALID_ARG;               // embedded NUL
  memcpy(dst, src, src_len);                    // line 22
  return BUF_ERROR_NONE;                         // line 23
}
```

---

## Phase 1 — Map

```
Target:        <pkg>/src/buf.c :: buf_copy(...)
Public header: <pkg>/include/buf.h
Visibility:    EXPORT_API
Callers:       (grep) buf_serialize(), buf_join() — both in <pkg>/src/buf.c
Callees:       memchr (libc), memcpy (libc)
Cluster:       not run — graphify unavailable / unnecessary for leaf
```

---

## Phase 2 — Analyze

### 2.1 Branch enumeration

| #  | Line | Predicate                                    | Action               |
|----|------|----------------------------------------------|----------------------|
| B1 | 12   | `src == NULL \|\| dst == NULL`               | return INVALID_ARG   |
| B2 | 14   | `src_len == 0`                                | return NONE (no-op)  |
| B3 | 16   | `src_len > dst_cap`                           | return OVERFLOW      |
| B4 | 19   | `memchr(src, '\0', src_len) != NULL`         | return INVALID_ARG   |
| B5 | 22–23| (all guards passed) — `memcpy` then return    | return NONE          |

### 2.2 Errno map

| Return value         | Predicate                                | Branches |
|----------------------|------------------------------------------|----------|
| `BUF_ERROR_NONE`     | success (with copy) or src_len == 0      | B2, B5   |
| `BUF_ERROR_INVALID_ARG` | NULL pointer                          | B1       |
| `BUF_ERROR_INVALID_ARG` | embedded NUL in src                    | B4       |
| `BUF_ERROR_OVERFLOW` | src_len exceeds dst_cap                  | B3       |

### 2.3 External dependencies

| Callee | Failure modes | Mapped errno | Status |
|--------|---------------|---------------|--------|
| `memchr` | none (no failure) | — | n/a |
| `memcpy` | none (no failure for valid args) | — | n/a |

### 2.4 State / preconditions

- No global state. Pure function. No preconditions beyond what the
  guards enforce.

---

## Phase 3 — Scenarios

### Success [P]

| ID | Inputs | Expected | Side-effects |
|----|--------|----------|---------------|
| P1 | src="abc", src_len=3, dst=buf[8], dst_cap=8 | NONE | dst[0..2] == "abc" |
| P2 | src="any", src_len=0, dst=buf[8], dst_cap=8 | NONE | dst untouched |

### Failure [N] — one row per errno predicate

| ID  | Inputs                                      | Expected         | Why (cite §2) |
|-----|---------------------------------------------|------------------|---------------|
| N1  | src=NULL, src_len=3, dst=buf, dst_cap=8     | INVALID_ARG      | B1            |
| N2  | src="x", src_len=1, dst=NULL, dst_cap=8     | INVALID_ARG      | B1            |
| N3  | src="abcdef", src_len=6, dst=buf[3], dst_cap=3 | OVERFLOW       | B3            |
| N4  | src="ab\0c", src_len=4, dst=buf[8], dst_cap=8 | INVALID_ARG    | B4            |

Note: N1 and N2 both return INVALID_ARG but pin *different* guards.
Keeping them separate is the point.

### Edge [E]

| ID | Input shape                                | Expected | Notes                          |
|----|--------------------------------------------|----------|--------------------------------|
| E1 | src_len=0, src=NULL                        | INVALID_ARG | Order matters — guard B1 fires before B2; covered by N1 |
| E2 | src_len = dst_cap (boundary)               | NONE     | extends P1                     |
| E3 | src_len = dst_cap + 1                      | OVERFLOW | extends N3                     |
| E4 | src_len = SIZE_MAX                         | OVERFLOW | unless dst_cap == SIZE_MAX too |
| E5 | src and dst overlap (aliasing)             | UB per memcpy | flag in §8 — undocumented   |

### Corner [C]

| ID | Scenario                                  | Expected     | Source |
|----|-------------------------------------------|--------------|--------|
| C1 | Re-entry: callback inside `buf_copy` calls `buf_copy` again | both succeed independently | pure function — no shared state |

(Pure leaf functions usually have very few corner cases.)

---

## Phase 4 — Document (excerpt of §6 + §7 + §8)

```markdown
## Coverage check

- [x] Every distinct return value in §3 has at least one [N] row
- [x] Every NULL-able pointer parameter has at least one [N] row
- [x] Every numeric/length parameter has 0 / max / boundary rows in [E]
- [x] Every external dependency in §4 has its failures mapped (n/a — no failing callees)
- [x] Every documented invariant in §5 has at least one [C] row (n/a — pure function)
- [x] Every collapsed mapping in §4 has one [N] per distinct callee code (n/a)

## Open questions

- E5: aliasing src and dst is UB per `memcpy`. Should `buf_copy`
  document this constraint explicitly, or detect and reject it?
  Flag for the API owner.
```

---

## What the user does next

If they want test code, each row above (P1, P2, N1...N4, E2, E3, E4,
C1) becomes one test in whatever framework they use — gtest, ctest,
Catch2, etc. The skill does not assume one.

If they only wanted the inventory, they're done. The document above
*is* the deliverable.
