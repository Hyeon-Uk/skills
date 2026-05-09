---
name: architect
description: Apply OOAD + Clean Architecture to design non-trivial structural work for an active package refactor. Design stage of the per-task pipeline. Triggers on /architect.
---

# `/architect` — Design stage of the per-task pipeline

You take the planner's plan and produce a concrete *design*: which
entities/value objects exist, where the boundary lives, what
dependencies point inward, and what contract each new component
exposes. Skip yourself with a one-line waiver if the task is purely
linear (single test file, single doc edit) — the planner usually
flags this.

## Inputs

- `## Refined prompt` and `## Execution plan` sections in the active
  log file.
- The plan / roadmap / rules under `refactoring-plans/`.
- The actual production source files the task will touch (read them).
- Existing RAII-helper headers under the package's `src/.../raii/`
  subtree, if any.

## Output

Append a `## Design` section to the active log file with:

1. **Decision** — keep, evolve, or replace existing structure.
   One sentence.
2. **Components** — list. For each component:
   - name (class / struct / function group),
   - kind (entity / value object / boundary / use case / utility),
   - responsibility (one sentence),
   - dependencies (inward only — Clean Architecture rule).
3. **ASCII diagram** of dependency direction (mandatory unless waiver).
   Format:
   ```
       ┌─────────────────┐    ┌──────────────────┐
       │  Entity Layer   │ ◄─ │ Use Case Layer   │
       └─────────────────┘    └──────────────────┘
                                       ▲
                              ┌──────────────────┐
                              │ Boundary (C API) │
                              └──────────────────┘
   ```
4. **Public contract surface** — exact function signatures (or
   class declarations) the rest of the system will see.
5. **Invariants** — bullet list of pre/post-conditions and
   ownership rules.
6. **Trade-offs considered** — what alternatives were rejected and
   why (≥ 1 alternative per non-trivial design choice).
7. **Test seams** — where the tester will hook in. For each public
   contract function, name the test fixture or factory the tester
   will use.

## Rules

- **Clean Architecture dependency rule** — dependencies always point
  *inward* (boundary → use cases → entities). Never the other way.
- **OOAD discipline** — distinguish entities (have identity, mutable
  over time), value objects (immutable, equality by value), services
  (stateless operations on entities/values).
- **C++ for new structural work** when the package's plan permits;
  pure C remains C. Mixed TUs are fine across the `extern "C"`
  boundary.
- **Google C++ Style** for new C++ artifacts.
- **No silent ownership transfer.** Every pointer / handle must be
  named in invariants ("X owns Y until Z"). RAII wrappers preferred
  to raw pointers.
- **Public ABI is frozen** (R-ABI). New public exports require an
  ADR-style note in the Design section.
- For tasks where a design is genuinely unnecessary, write *exactly*
  this and stop:
  ```
  ## Design
  Waived — task is <reason in one sentence; e.g. "single new test
  file with no new abstraction">.
  ```

## Stop conditions

- All seven sections written, OR a one-line waiver written.
- Hand off to `/developer`.

## Failure modes

- Designing more than the task needs.
- Skipping the ASCII diagram for non-trivial work (supervisor will
  bounce).
- Producing a "Components" list whose dependencies cycle or point
  outward.
- Recommending changes to public C headers without an ADR note.
