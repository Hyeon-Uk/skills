# Analysis techniques — how to actually enumerate

This is the toolbox for Phase 2 of the skill. The work is mechanical;
the trick is to *be exhaustive*.

---

## 1. Branch enumeration by language

### C / C++

Read the function source top-to-bottom. Every one of these creates a
branch row in your table:

| Construct | Notes |
|-----------|-------|
| `if (cond)` / `else if` / `else` | One row per arm. |
| `switch (x)` | One row per `case`, plus `default`. Falls-through count separately. |
| `cond ? a : b` | One row per side. |
| `&&` / `\|\|` short-circuits | The right-hand side only runs under a specific predicate. List both. |
| Early `return` | Always a branch. |
| `goto` | Treat the target label as a branch — list both the source and what reaching the label implies. |
| `throw` (C++) | An exit. Treat like `return` but record the exception type. |
| `assert(cond)` | If asserts are compiled in, a violation is a separate "outcome" (abort). Usually skip in scenarios; flag in Open Questions. |
| Implicit fallthrough at end of `void` function | One row: "no error, fell through". |
| Destructor/RAII paths | If the function takes RAII objects, list cleanup as a side-effect, and exception-during-construction as a corner case. |

For `static` helper functions called from the target, **inline their
logic** into your branch list — they are part of the target's behavior
even though they're not directly callable. Mark each row with the
helper's name so traceability survives.

### Python

| Construct | Notes |
|-----------|-------|
| `if`/`elif`/`else` | Same as C. |
| `match`/`case` (3.10+) | Same as `switch`. |
| `try`/`except` | One row per `except` clause + the success path + `finally` side-effects. |
| `raise` | An exit; record the exception type. |
| Implicit `return None` at function end | One row. |
| `yield` (generators) | Each `yield` is a checkpoint, not an exit; list as state transitions. |
| `assert` | If `python -O` could be in play, treat the assert as advisory; otherwise list as a guard. |
| `with`-block exits | The context manager's `__exit__` runs on both success and exception — both are scenarios. |

### Go

| Construct | Notes |
|-----------|-------|
| `if err != nil { return ..., err }` | Each one is a separate failure scenario, with the wrapped error as the "errno". |
| `switch` / `select` | One row per `case` + `default`. |
| `defer` | Side-effect that runs on every exit — list once and note all exits trigger it. |
| `panic` | An exit; record the panic value. |
| Channel sends/receives | Blocking is a corner-case dimension. |

### JavaScript / TypeScript

| Construct | Notes |
|-----------|-------|
| `if`/`else`/`switch`/`?:` | Same as C. |
| `try`/`catch`/`finally` | Same as Python. |
| `throw` | Exit; record the thrown value's type. |
| `await rejected promise` | Equivalent to `throw` from the caller's perspective. |
| Implicit `return undefined` | One row. |

---

## 2. Extracting every distinct return value (errno map)

The goal is a complete table with no row missing. Use grep as a check
on the analysis you already did by reading.

### C / C++ with `*_ERROR_*` enums

```bash
# Every error-named return
grep -nE 'return\s+[A-Z][A-Z0-9_]*_ERROR_[A-Z0-9_]+' <file>

# Every numeric return (catches `return -1`, `return 0`)
grep -nE 'return\s+-?[0-9]+\s*;' <file>

# Every return of a variable (could carry any value)
grep -nE 'return\s+[a-z_][a-zA-Z0-9_]*\s*;' <file>

# Function-call returns (need to follow the callee)
grep -nE 'return\s+[a-z_][a-zA-Z0-9_]*\([^)]*\)' <file>
```

For each line, write the predicate that leads to it (look at the
enclosing `if`/`switch`). For `return <var>` lines, trace back to where
`<var>` was last assigned and treat *each possible value* as a separate
errno-map row.

### POSIX `errno`

When the function reports failure via `errno` (returning -1 or NULL):

```bash
grep -nE '\berrno\s*=' <file>     # explicit sets
```

Plus any libc/syscall the target calls — each has its own list of
`errno` values it can set (`man 2 <syscall>`). The scenarios that
matter are the ones the function *propagates* (i.e. doesn't translate).

### Python exceptions

```bash
grep -nE '\braise\s+[A-Z][A-Za-z0-9_]+' <file>
```

For each `raise`, the predicate is the enclosing condition. Library
calls inside the function may *also* raise — find them:

```bash
grep -nE '^\s*[a-z_][a-zA-Z0-9_.]*\(' <file>   # rough call sites
```

Then check each library function's documented exceptions.

### Go errors

```bash
grep -nE 'return.*\berr(or)?\b' <file>
grep -nE 'fmt\.Errorf\(' <file>
grep -nE 'errors\.New\(' <file>
```

In Go, every `if err != nil` is a separate scenario — wrapped errors
from different callees count as different errno values.

---

## 3. External dependency cataloguing

For each callee found in Phase 2.3:

1. Read its documented contract (header docstring, `man`, library docs).
2. List its failure modes — both return codes and (where relevant)
   side-effects (NULL out-params, partially-initialized state).
3. Determine which target errno maps to which callee failure. Two
   patterns:
   - **Propagation**: `if (cb() != OK) return TRANSLATED_ERROR;` — one
     scenario per callee failure mode.
   - **Swallowing**: `(void)cb();` — no scenario, but flag in Open
     Questions ("is swallowing intentional?").

Keep a checklist:

```
g_malloc0          | NULL on OOM                  → NO_MEMORY        ✔ propagated
sqlite3_step       | SQLITE_BUSY/LOCKED/IOERR/... → IO_ERROR (all)   ⚠ collapsed — scenario per code or one?
cynara_check       | DENIED, TIMEOUT, OUT_OF_MEM  → PERM_DENIED      ⚠ TIMEOUT collapsed
log_print          | always succeeds (void)       → none
```

Collapsed mappings are scenarios *worth flagging*: one scenario per
distinct callee failure code is more thorough than one scenario per
collapsed bucket.

---

## 4. State / precondition catalogue

For class methods or stateful APIs:

1. Find the constructor / `init` function. Note what state it
   establishes.
2. Find the destructor / `release` function. Note what state it
   tears down.
3. Re-read the target function asking: "what state does this assume?"
   - Is there a `g_assert(this->initialized)` or similar?
   - Does it dereference fields of `this`/`self` without null-checking?
   - Does it read from a global/singleton that `init` populated?
4. Each assumption is a corner case: scenarios where the assumption is
   violated (use-before-init, use-after-release, double-release).

Also look for:
- Reentrancy (function calls back into itself or its callers).
- Thread-safety claims (in docs or via mutex usage in source).
- Callback registration / unregistration order.

---

## 5. When the function has no error enum

Some functions return `bool`, `void`, or a domain-specific value
(`fopen()` returns `FILE*` with NULL on error and `errno` set).
Adapt the errno map accordingly:

- `bool` returns: rows are `true` / `false`, predicate column says when.
- `void`: rows are distinct *side-effect outcomes* (state-A, state-B,
  exception, no-op).
- Pointer-or-NULL: rows are "valid pointer" + one row per `errno` set
  on failure paths.

The structure of the document doesn't change — only the contents of
the "Return value" column.

---

## 6. Sanity checks before declaring Phase 2 done

Run these greps over the target file and verify each result is in
your tables:

```bash
# Every return statement
grep -cE '^\s*return\b' <file>

# Every if and else
grep -cE '\b(if|else)\b' <file>

# Every external symbol called (rough — refine per language)
grep -oE '\b[a-z_][a-zA-Z0-9_]*\(' <file> | sort -u
```

If your branch table has fewer rows than the count of `return`
statements, you missed a branch. If your callee list has fewer entries
than the unique-call list, you missed a callee.

This is dumb-but-effective. Skipping it is what causes the "I thought
I covered everything" failure mode.
