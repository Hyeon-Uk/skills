# Example 3 — Filled-in Phase 1 worksheet

This is the level of detail expected before any test code is generated.
Subject: a hypothetical `app_resource_manager_get(...)`-style API.
Read it as a model — fill out the same shape for whatever the user asks.

---

```
Subject under test:  app_resource_manager (file: src/app_resource_manager.c)
Public surface (in-scope):
  - app_resource_manager_init(app_resource_e type, app_resource_manager_h *out)
  - app_resource_manager_get(app_resource_manager_h h, const char *id, char **path)
  - app_resource_manager_release(app_resource_manager_h h)

Out of scope (NOT to be tested directly):
  - static int  __load_resource_table(...)        (file-local helper)
  - static void __free_node(struct node *n)       (file-local helper)
  - private:  ResourceManagerImpl::CacheLookup(...) (called via _get)

================================================================
Method:   int app_resource_manager_init(app_resource_e type,
                                         app_resource_manager_h *out)
Purpose:  Allocate a manager bound to a resource type (image, sound, ...).
Returns:  APP_RESOURCE_ERROR_NONE
          APP_RESOURCE_ERROR_INVALID_PARAMETER  (type out of enum range,
                                                 out == NULL)
          APP_RESOURCE_ERROR_OUT_OF_MEMORY      (alloc fails)
          APP_RESOURCE_ERROR_IO_ERROR           (resource table load fails)

Success cases (_P):
  [P1] type=APP_RESOURCE_TYPE_IMAGE, out!=NULL  → NONE, *out != NULL
  [P2] type=APP_RESOURCE_TYPE_SOUND, out!=NULL  → NONE, *out != NULL

Failure cases (_N):
  [N1] type=APP_RESOURCE_TYPE_IMAGE, out=NULL          → INVALID_PARAMETER
  [N2] type=(app_resource_e)(-1),    out!=NULL         → INVALID_PARAMETER
  [N3] type=APP_RESOURCE_TYPE_IMAGE, out!=NULL,
       g_malloc0 mocked to return NULL                  → OUT_OF_MEMORY
  [N4] type=APP_RESOURCE_TYPE_IMAGE, out!=NULL,
       fopen() mocked to return NULL for table file     → IO_ERROR

Edge cases:
  [E1] type=APP_RESOURCE_TYPE_LAYOUT (highest enum value, supported)
       → NONE  (boundary of valid enum range)
  [E2] type=(app_resource_e)(LAST + 1)
       → INVALID_PARAMETER  (just past valid range; covers [N2])

Corner cases:
  [C1] init→release→init again with same out variable
       → second init returns NONE; out is fresh; no leak.
  [C2] init while a previous init's handle is still live
       → both succeed; they are independent.

External deps to mock:
  - g_malloc0 / g_free                  (GlibMock)        → drive [N3]
  - fopen / fread / fclose              (LibcMock?)       → drive [N4]
                                                            (or stub via
                                                            Mocks aggregate
                                                            of TzplatformConfigMock
                                                            so the table path
                                                            does not exist)

Static/private helpers exercised transitively:
  - __load_resource_table  — covered by [P1], [N4]
  - __free_node            — covered by release_P (separate row)

================================================================
Method:   int app_resource_manager_get(app_resource_manager_h h,
                                        const char *id, char **path)
Purpose:  Look up the file path of a registered resource id.
Returns:  APP_RESOURCE_ERROR_NONE
          APP_RESOURCE_ERROR_INVALID_PARAMETER (h, id, or path is NULL)
          APP_RESOURCE_ERROR_NOT_FOUND        (id not in table)

Success cases (_P):
  [P1] valid handle, known id, path!=NULL
       → NONE, *path != NULL, *path freeable with free().

Failure cases (_N):
  [N1] h=NULL, id="x", path!=NULL                 → INVALID_PARAMETER
  [N2] h=valid, id=NULL, path!=NULL               → INVALID_PARAMETER
  [N3] h=valid, id="x",  path=NULL                → INVALID_PARAMETER
  [N4] h=valid, id="not_present", path!=NULL      → NOT_FOUND

Edge cases:
  [E1] id = ""                          → covered by [N4] (empty key not
                                          in table) — or split if "" is
                                          documented as INVALID.
  [E2] id length = MAX_RESOURCE_KEY_LEN → covered as own _P_long_key if
                                          docs guarantee support.
  [E3] *path returned must be allocated; freeing it must not crash.
       Add ASSERT_NO_FATAL_FAILURE(free(*path)) in [P1].

Corner cases:
  [C1] get() called before init() (h is uninitialized stack variable)
       → INVALID_PARAMETER (covered by [N1] with h=NULL).
  [C2] get() after release() of the same handle
       → INVALID_PARAMETER. Separate test:
         _N_after_release uses release()→get() sequence.

External deps to mock:
  - none directly (the lookup hits an in-memory table populated by init).

================================================================
Method:   int app_resource_manager_release(app_resource_manager_h h)
Purpose:  Free the manager and any cached resources.
Returns:  APP_RESOURCE_ERROR_NONE
          APP_RESOURCE_ERROR_INVALID_PARAMETER (h == NULL)

Success cases (_P):
  [P1] valid handle → NONE, double-release pinned in [C1].

Failure cases (_N):
  [N1] h=NULL → INVALID_PARAMETER

Edge cases:
  [E1] release immediately after init (no get() in between) → NONE.

Corner cases:
  [C1] release(h); release(h);  — second call is INVALID_PARAMETER
       per docs (must not crash). Test as _N_double_release.

External deps to mock:
  - g_free  (GlibMock) — only if asserting cleanup count;
            usually not required.

================================================================
Sanity checklist:
  ✔ Every distinct return code → at least one _N row.
  ✔ Every NULL-able pointer parameter has a row.
  ✔ Every numeric/enum parameter has 0/min, max, and a boundary row.
  ✔ Every external library call appears under "must be mocked".
  ✔ No row references a `static` or `private:` symbol as the test target.

  Two new mock files needed:
   - libc_mock.{hh,cc}  for fopen/fread/fclose (or use existing GlibMock g_file_*)

  Test-name plan (final list to generate):
   - app_resource_manager_init_P
   - app_resource_manager_init_P_sound        (renaming of P2)
   - app_resource_manager_init_P_layout_boundary  (E1)
   - app_resource_manager_init_N               (covers N1+N2)
   - app_resource_manager_init_N_out_of_memory (N3)
   - app_resource_manager_init_N_io_error      (N4)

   - app_resource_manager_get_P                (P1, includes free assertion)
   - app_resource_manager_get_N                (N1+N2+N3, all INVALID_PARAMETER)
   - app_resource_manager_get_N_not_found      (N4)
   - app_resource_manager_get_N_after_release  (C2)

   - app_resource_manager_release_P
   - app_resource_manager_release_N
   - app_resource_manager_release_N_double_release  (C1)
```

Only after a worksheet at this density is it productive to start
writing `TEST_F` bodies. Note how every test name traces back to a
specific row id ([P1], [N3], [C1], ...) — that traceability is the
point.
