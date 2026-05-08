# Example 1 — Simple C-API, no external mocks

Subject: `tizen_core_task_*` (from `tizen-core/tests/tizen-core_unittests/`).
This API is self-contained: the package owns its own runtime and we don't
need to mock external libraries to drive it. So we use a plain
`::testing::Test`, not `TestFixture`.

---

## Phase 1 — Analysis worksheet (extract)

```
Method:    int tizen_core_task_create(const char *name, bool use_thread,
                                      tizen_core_task_h *task)
Purpose:   Create a new task with the given name; return its handle.
Returns:   TIZEN_CORE_ERROR_NONE on success
           TIZEN_CORE_ERROR_INVALID_PARAMETER
             - name == NULL
             - task  == NULL
             - name == "main" (reserved)
             - name already exists in the registry

Success cases (_P):
  [P1] name="new_task", use_thread=true,  task!=NULL → returns NONE,
                                                       *task != NULL,
                                                       handle is destroyable.

Failure cases (_N):
  [N1] name=NULL,        use_thread=false, task=NULL → INVALID_PARAMETER
  [N2] name="main",      use_thread=true,  task!=NULL → INVALID_PARAMETER
        (already created in SetUp; reserved name)
  [N3] name="test_task", use_thread=true,  task!=NULL → INVALID_PARAMETER
        (already created in SetUp; duplicate name)

Edge cases:
  [E1] empty string name           → covered transitively in _N if rejected,
                                     otherwise needs its own row.
  [E2] task == NULL only (name OK) → INVALID_PARAMETER (covered by N1)

Corner cases:
  [C1] create→destroy→create same name  → second create succeeds.
  [C2] create→shutdown without destroy  → tested via tizen_core_shutdown_P.

External deps to mock:
  - none. Self-contained.

Private/static helpers (NOT tested directly):
  - find_task_by_name   — exercised by [N3].
  - alloc_task_handle   — exercised by [P1].
```

The `_N` test bundles N1, N2, N3 into one body because they all return
the same `INVALID_PARAMETER`. If they returned different codes they would
be split.

---

## Phase 2 — Generated tests

`tizen_core_test.cc` (excerpt, real code from the repo):

```cpp
class TizenCoreTest : public ::testing::Test {
 public:
  void SetUp() override {
    tizen_core_init();
    tizen_core_task_create("test_task", true, &task_);
    tizen_core_task_create("main", false, &main_task_);
  }

  void TearDown() override {
    if (main_task_) tizen_core_task_destroy(main_task_);
    if (task_)      tizen_core_task_destroy(task_);
    tizen_core_shutdown();
  }

  tizen_core_task_h task_      = nullptr;
  tizen_core_task_h main_task_ = nullptr;
};

TEST_F(TizenCoreTest, tizen_core_task_create_P) {
  tizen_core_task_h task = nullptr;
  int ret = tizen_core_task_create("new_task", true, &task);
  ASSERT_EQ(ret, TIZEN_CORE_ERROR_NONE);
  ASSERT_NE(task, nullptr);
  tizen_core_task_destroy(task);
}

TEST_F(TizenCoreTest, tizen_core_task_create_N) {
  // [N1] both name and out-param NULL
  int ret = tizen_core_task_create(nullptr, false, nullptr);
  ASSERT_EQ(ret, TIZEN_CORE_ERROR_INVALID_PARAMETER);

  tizen_core_task_h task = nullptr;
  // [N2] reserved name "main"
  ret = tizen_core_task_create("main", true, &task);
  ASSERT_EQ(ret, TIZEN_CORE_ERROR_INVALID_PARAMETER);

  // [N3] duplicate of an already-created task
  ret = tizen_core_task_create("test_task", true, &task);
  ASSERT_EQ(ret, TIZEN_CORE_ERROR_INVALID_PARAMETER);
}

TEST_F(TizenCoreTest, tizen_core_task_destroy_P) {
  int ret = tizen_core_task_destroy(task_);
  ASSERT_EQ(ret, TIZEN_CORE_ERROR_NONE);
  task_ = nullptr;
}

TEST_F(TizenCoreTest, tizen_core_task_destroy_N) {
  int ret = tizen_core_task_destroy(nullptr);
  ASSERT_EQ(ret, TIZEN_CORE_ERROR_INVALID_PARAMETER);
}
```

Things to notice:

1. Strict 1:1 of public function → `_P` + `_N` test pair.
2. Each `_N` body asserts the **exact** `INVALID_PARAMETER` enum, not
   `ASSERT_NE(ret, 0)`.
3. Multiple invalid shapes are bundled into one `_N` body **only because
   they share a return code**. If `name="main"` returned
   `ALREADY_EXISTS` and `name=nullptr` returned `INVALID_PARAMETER`, they
   would be split into `_N_invalid_param` and `_N_already_exists`.
4. The fixture's `SetUp/TearDown` provides the named state that `_N`
   cases require ("there is already a task called `test_task`"). The
   tests don't invent that state inline.
5. No mocking is done because the subject has no external dependencies —
   doing so would just hide the real behavior of the runtime.
