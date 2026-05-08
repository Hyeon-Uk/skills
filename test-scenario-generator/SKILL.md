---
name: test-scenario-generator
description: Build a complete, structured test-scenario inventory for one or more target methods/functions BEFORE any test code is written. Use whenever the user asks to "generate test scenarios", "design test cases", "what should we test for X", "list every error path", "find all errno paths", "enumerate failure cases", "테스트 시나리오 만들어", "테스트 케이스 도출", "이 함수의 케이스 분석", "어떤 errno이 나올 수 있는지". Trigger even when the user does not say "skill" or "scenario" — describing the intent ("audit the failure paths of X", "what edge cases does Y have", "I need every if-branch covered") is enough. The skill enforces a four-phase workflow: (1) map the project (using the `graphify` skill if available), (2) analyze the target by enumerating every if/switch branch and every distinct return value (especially errno / *_ERROR_* enums), (3) generate Success / Failure / Edge / Corner scenarios with full errno coverage, (4) emit a structured scenario document. Output is the scenario inventory itself — not test code.
---

# Test Scenario Generator

This skill produces the **scenario inventory** that a good test suite is built from. It does not write tests. Its job is to make sure that, before anyone writes a single `TEST_F` or `it("should ...")`, the team has a complete map of what the target function *can do* and what it *can return*, so that no failure path is forgotten.

The skill composes optionally with `graphify` — if available, it is used in Phase 1 to get a project-wide knowledge graph (call sites, callers, communities) so corner-case discovery is informed by real callers.

The deliverable is the scenario document. If the user wants test code afterwards, that is a separate step using whatever test framework / authoring tool they prefer; this skill stops at Phase 4 and does not assume any particular framework.

---

## Why this skill exists

The single most common failure mode in unit-test work is **invisible scenarios**: failure paths that the test author never thought of, so the suite "passes" without proving the contract. In C/C++ codebases this manifests as missing coverage on `*_ERROR_*` enums; in higher-level code as forgotten edge cases like empty input, exhausted iterators, or partially-initialized state.

The fix is to enumerate scenarios from the *source* — every `if (cond) return ERR_X;`, every `switch` arm, every external call's failure mode — before any test code is written. That enumeration is mechanical, but it has to actually happen. This skill makes it happen, and produces an artifact (the scenario document) that the team can review independently of the eventual test code.

---

## Workflow — four phases

You must complete each phase before moving to the next. Skipping ahead is the failure mode the skill exists to prevent.

### Phase 1 — Map the project

Goal: understand where the target lives, what calls it, what it calls. This context shapes which corner cases matter (e.g. if the target is only ever called from a single state machine, certain orderings are impossible and shouldn't pollute the scenario list).

1. **Identify the target precisely.** Get from the user (or infer from context) the exact function/method and file. Resolve overloaded names — module path + signature, not just "the get function".

2. **Try `graphify` first.** If the `graphify` skill is registered (check the available-skills list), invoke it on the directory containing the target. It produces a clustered knowledge graph that surfaces:
   - Direct callers of the target (corner cases often live in caller assumptions).
   - Direct callees / external symbols (every callee's failure modes are potential failure scenarios).
   - The community/cluster the target belongs to (helps decide if the target is a leaf utility or a cross-cutting orchestrator — this affects whether ordering and reentrancy scenarios are realistic).

   Invoke it via the Skill tool: `Skill(skill="graphify", args="<path-to-relevant-source-dir>")`. Read the resulting JSON/HTML and extract the call edges into and out of the target.

3. **Fall back to manual mapping** if `graphify` is not available or the project is too small to benefit:
   - `grep -rn "<target>(" <pkg>/` — call sites.
   - Read the target's source and list every external symbol it calls.
   - List every header that exposes the target.

4. **Output of Phase 1**: a small "context block" at the top of the scenario document:
   ```
   Target:        <pkg>/src/foo.c :: foo_create(const char *id, foo_h *out)
   Public header: <pkg>/include/foo.h
   Callers:       <list, from graphify or grep>
   Callees:       <list of external symbols and their headers>
   Cluster:       <if graphify, the community label>
   ```

### Phase 2 — Analyze the target

Goal: extract the function's full *internal behavior model* from its source. Every branch, every return, every external call. No interpretation yet — just enumeration.

#### 2.1 Branch enumeration

Read the function source line-by-line. Record every control-flow point:

- Every `if`, `else if`, `else`, `switch case`, `?:`, short-circuit `&&` / `||`, early `return`, `goto`, exception throw.
- For each, write a one-line predicate: "p1 is NULL", "len > MAX", "alloc returned NULL", "cynara_check returned DENY".

Use a numbered branch table. Branches that don't return their own value (i.e. just modify state and fall through) are still listed — they affect side-effects in success/edge scenarios.

#### 2.2 Return-value extraction (the errno map)

This is the core of the skill. Build a complete table:

```
Return value | Reached when (predicate, in order of evaluation)
-------------|----------------------------------------------------
NONE / 0     | All guards passed; <list any side effects>
INVALID_ARG  | id == NULL || out == NULL                     (line 12)
NO_MEMORY    | g_malloc0 returned NULL                        (line 18)
NOT_FOUND    | db_lookup returned 0 rows                      (line 27)
IO_ERROR     | sqlite3_step != SQLITE_ROW && != SQLITE_DONE  (line 34)
PERM_DENIED  | cynara_check returned not-ALLOWED             (line 42)
NOT_SUPPORTED| system_info_get_platform_bool *value == false (line 47)
```

Rules:

- Each distinct return value **must** appear at least once.
- For functions with no error enum (returns `bool` or `void`), the table still applies — replace "Return value" with "Outcome" and enumerate distinct observable outcomes (true/false, exception thrown, side-effect-A, side-effect-B).
- If two different predicates return the same code, list them on separate rows. They become separate `_N_<reason>` scenarios in Phase 3.
- Use grep to verify completeness: `grep -nE 'return\s+[A-Z_]+_ERROR' <file>` and `grep -nE 'return\s+-?[0-9]+' <file>`. Cross-check that every line you find is in the table.

#### 2.3 External dependency catalogue

For each external symbol the target calls, list:

- The function's documented failure modes (return codes, `errno` values, exceptions).
- Whether the target propagates that failure (which row of the errno map it maps to) or swallows it.

This is what tells you which scenarios require mocking to drive — and which errno values the target *could* return if a mock makes the dependency fail.

#### 2.4 Internal-state catalogue

For class methods and stateful APIs, list:

- Preconditions: what state must hold for the call to be valid (object initialized, db opened, handle non-null).
- Side effects: what state changes after a successful call.
- Invariants: what the function assumes (e.g. "called only from main thread", "called only after `init()`").

These produce corner cases in Phase 3.

### Phase 3 — Generate scenarios

Now turn the analysis into a flat list of test scenarios, grouped by category.

#### 3.1 Success scenarios `[P]`

One per distinct *successful* path through the function. If the function has only one success path, there is one `[P1]`. If it has branches that affect success behavior (e.g. "with callback" vs "without callback", "first call vs cached call"), each gets its own row.

```
[P1] inputs: id="real_id",  out=&handle     → returns NONE; *out != NULL; handle.id == "real_id"
[P2] inputs: id="cached_id", out=&handle    → returns NONE; *out points to cached entry; cache hit counter incremented
```

#### 3.2 Failure scenarios `[N]` — one row per errno

This is mechanical: take the errno map from Phase 2.2, and produce one `[N]` row per row of the map (excluding the success row).

```
[N1]  → INVALID_ARG    when id=NULL,   out=&h
[N2]  → INVALID_ARG    when id="x",    out=NULL
[N3]  → NO_MEMORY      when g_malloc0 mocked to return NULL
[N4]  → NOT_FOUND      when db has no row for id
[N5]  → IO_ERROR       when sqlite3_step mocked to SQLITE_BUSY
[N6]  → PERM_DENIED    when cynara_check mocked to DENY
[N7]  → NOT_SUPPORTED  when system_info_get_platform_bool sets *value=false
```

If two predicates return the same errno (e.g. `INVALID_ARG` for null id AND null out), keep both rows — they are separately testable shapes that pin different guards.

#### 3.3 Edge scenarios `[E]` — boundary values

For each input parameter, enumerate boundary values and record what should happen:

- Numeric: 0, 1, MAX-1, MAX, MAX+1 (overflow), -1, INT_MIN.
- Strings: "", " ", single char, length=buffer_size, length=buffer_size+1, embedded NUL, multi-byte UTF-8.
- Pointers: NULL (covered in `[N]`), uninitialized (caller error — usually skipped), valid-but-empty handle.
- Containers: empty, single element, full capacity, capacity+1.

Each row is either:
- **Already covered by an existing `[P]` or `[N]`** — note that and move on.
- **A new edge** — add a row with expected outcome.

```
[E1] id=""                          → INVALID_ARG (covered by N1 if guard treats "" same as NULL; otherwise its own row)
[E2] id length = MAX_ID_LEN         → NONE (boundary supported)
[E3] id length = MAX_ID_LEN + 1     → INVALID_ARG (truncation rejected)
[E4] id contains embedded NUL        → INVALID_ARG (or whatever the contract says)
```

#### 3.4 Corner scenarios `[C]` — state and ordering

These come from Phase 2.4. They are scenarios where the inputs alone are valid, but the *context* of the call breaks something. They are usually the most missed scenarios in test suites.

```
[C1] init() → use → release() → use again        → INVALID_ARG (use-after-free contract)
[C2] init() → init()                             → already-initialized branch
[C3] use without init                            → INVALID_ARG / specific error
[C4] concurrent calls from two threads            → if API claims thread-safety, must verify
[C5] callback registered, then handle destroyed   → callback must not fire after destroy
[C6] partial init, then exception/error          → cleanup must leave system in valid state
```

For each, note whether the API contract documents the expected behavior (in which case it's a real scenario) or doesn't (in which case it's a code-smell to flag, not a scenario — flag and move on).

### Phase 4 — Emit the scenario document

Output a single Markdown document with this exact structure (see `references/output_template.md` for the canonical schema):

```markdown
# Scenarios — <target signature>

## Context
- Target:    <path :: signature>
- Public:    <header>
- Callers:   <list>
- Callees:   <list>
- Cluster:   <graphify cluster, if any>

## Branch enumeration (Phase 2.1)
| # | Line | Predicate | Action |
|---|------|-----------|--------|
| 1 | 12   | id == NULL || out == NULL | return INVALID_ARG |
| 2 | 18   | g_malloc0() == NULL       | return NO_MEMORY   |
...

## Errno map (Phase 2.2)
| Return | Predicate | Line |
|--------|-----------|------|
| NONE   | (all guards passed) | — |
| INVALID_ARG | id NULL or out NULL | 12 |
...

## External dependencies (Phase 2.3)
| Callee | Failure modes | Mapped to errno |
|--------|---------------|------------------|
| g_malloc0 | NULL on OOM | NO_MEMORY |
| cynara_check | not-ALLOWED | PERM_DENIED |
...

## State catalogue (Phase 2.4)
- Preconditions: ...
- Invariants:    ...
- Side effects:  ...

## Scenarios

### Success [P]
[P1] inputs ...                → NONE; side-effect ...

### Failure [N] — one per distinct errno predicate
[N1] inputs ...                → INVALID_ARG (predicate: id NULL)
[N2] inputs ...                → INVALID_ARG (predicate: out NULL)
[N3] inputs ..., mock g_malloc0 to NULL  → NO_MEMORY
...

### Edge [E]
[E1] id=""                     → covered by N1 / new row
[E2] id length = MAX           → NONE
...

### Corner [C]
[C1] use after release          → INVALID_ARG
[C2] init twice                 → ALREADY_INITIALIZED
...

## Coverage check
- Every distinct return value in §"Errno map" appears in §"Failure":   ✔ / ✖
- Every NULL-able pointer parameter has a row:                          ✔ / ✖
- Every numeric parameter has 0 / max / boundary rows:                  ✔ / ✖
- Every external dependency's failure modes are mapped to a scenario:   ✔ / ✖
- Every documented invariant has at least one corner scenario:          ✔ / ✖

## Open questions
<things the source did not make clear — flag for the user>
```

The "Coverage check" section is mandatory and the skill must fill it in honestly. If any check fails, expand the scenario list before declaring done.

---

## Output traceability rule

Every scenario row's ID (`[P1]`, `[N3]`, `[E2]`, ...) must be referenced from somewhere in Phase 2 (a branch number, an errno-map row, or a state-catalogue entry). The scenario document is *traceable* — a reviewer can ask "where does [N5] come from?" and you can point to a specific line of source. If a scenario has no traceable origin, it is either a corner case that should cite Phase 2.4 or it is speculation — and speculation does not belong in this document.

---

## Working with `graphify`

Quick recipe for invoking `graphify` from inside this skill:

1. Identify the smallest source set that contains the target and its likely callers/callees (usually the package directory; for a leaf utility, just the file).
2. Invoke the skill: `Skill(skill="graphify", args="<path>")`.
3. Read the generated `graph.json` / audit report (graphify will tell you where it wrote them).
4. Filter the graph to nodes within distance ≤ 2 of the target.
5. Extract:
   - Inbound edges → callers (Phase 1.2's "Callers" line and possible corner cases in Phase 3.4).
   - Outbound edges → callees (Phase 2.3's external-dependency catalogue).
   - Community label → "Cluster" line in Phase 1.4.

If `graphify` is not registered (check the available-skills list), say so explicitly in the document's Context block ("Cluster: not run — graphify unavailable") and rely on grep-based mapping. Do NOT fabricate a cluster label.

---

## Handing off to test authors

After Phase 4, the scenario document is ready to be consumed. Each `[P]/[N]/[E]/[C]` row should become one test in whatever framework the team uses — the row's predicate becomes the test's setup, and the expected return becomes its assertion.

If the user asks for code afterwards, ask which framework they want before generating anything — this skill stops at Phase 4. The handoff is intentionally explicit so the test author (human or AI) starts from a complete inventory rather than improvising.

---

## Reference files

- `references/analysis_techniques.md` — concrete recipes: how to enumerate branches in C, C++, Python, Go; grep patterns to extract every distinct return value and errno; how to detect implicit returns and exceptions.
- `references/output_template.md` — the full Markdown schema for the scenario document, with field-by-field semantics. Read this before emitting the document if unsure about formatting.

## Examples

- `examples/01_simple_function.md` — a small C function (no graphify needed). Shows the four phases in compact form.
- `examples/02_complex_with_graphify.md` — a method with many callers and external deps, using `graphify` output to inform corner-case discovery.
