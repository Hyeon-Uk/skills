# Example 2 — Mock-heavy C-API

Subject: `widget_service_get_widget_disabled` (from
`widget-service/unittest/`). This API touches `cynara` (privilege check),
`system_info` (platform feature flag), `tzplatform_config` (paths), and
an internal sqlite db. Every external lib is mocked.

---

## Phase 1 — Analysis worksheet

```
Method:    int widget_service_get_widget_disabled(const char *widget_id,
                                                  bool *is_disabled)
Purpose:   Return whether the named widget has been disabled by the user.
Returns:   WIDGET_ERROR_NONE
           WIDGET_ERROR_INVALID_PARAMETER  (widget_id == NULL || is_disabled == NULL)
           WIDGET_ERROR_PERMISSION_DENIED  (cynara denies)
           WIDGET_ERROR_NOT_SUPPORTED      (system_info reports widget unsupported)
           WIDGET_ERROR_IO_ERROR           (db read fails — covered separately)

Success cases (_P):
  [P1] valid id, supported platform, allowed by cynara, db has row → NONE,
                                                                     *is_disabled set.

Failure cases (_N):
  [N1] widget_id == NULL                                → INVALID_PARAMETER
  [N2] is_disabled == NULL                              → INVALID_PARAMETER
  [N3] cynara_initialize() returns nonzero              → PERMISSION_DENIED
  [N4] system_info_get_platform_bool() reports false    → NOT_SUPPORTED
  [N5] (sqlite mocked to fail SELECT)                   → IO_ERROR

Edge cases:
  [E1] very long widget_id (path-overflow)              → INVALID_PARAMETER if rejected
  [E2] widget_id with NUL in middle                     → covered by [E1]

Corner cases:
  [C1] cynara succeeds initialize but check returns DENY → PERMISSION_DENIED.
       (different from [N3], so split into _N_permission_denied_init
       and _N_permission_denied_check if both code paths exist.)

External deps to mock (3rd-party + cross-Tizen):
  - cynara_initialize / cynara_creds_self_get_client / cynara_check / cynara_finish
  - system_info_get_platform_bool
  - tzplatform_mkpath  (so sqlite uses a temp file in the test cwd)
  - aul_app_com_*      (for related APIs in this fixture)
  - sqlite3_*          (only when forcing IO_ERROR for [N5])

Private/static helpers (NOT tested directly):
  - __cynara_check_privilege  → exercised via [P1] (allowed) and [N3]/[C1] (denied)
  - __open_db                 → exercised via [P1] and [N5]
```

In the actual codebase only [P1], [N1] (NULL id) and [N3] are present.
Adding the remaining rows in a follow-up patch is exactly the kind of
gap the analysis-first workflow is designed to surface.

---

## Phase 2 — Generated tests

`test_widget_service.cc` (excerpts, real code from the repo, lightly
trimmed):

```cpp
namespace {

int __fake_system_info_get_platform_bool(const char* key, bool* value) {
  *value = true; return 0;
}
int __fake_cynara_initialize(cynara** c, const cynara_configuration* cf) {
  return CYNARA_API_SUCCESS;
}
int __fake_cynara_creds_self_get_client(cynara_client_creds m, char** out) {
  return CYNARA_API_SUCCESS;
}
int __fake_cynara_check(cynara* c, const char* client, const char* sess,
                        const char* user, const char* priv) {
  return CYNARA_API_ACCESS_ALLOWED;
}
int __fake_cynara_finish(cynara* c) { return 0; }
const char* __fake_tzplatform_mkpath(tzplatform_variable id, const char* p) {
  return ".widget_test.db";
}

class Mocks : public ::testing::NiceMock<AulMock>,
              public ::testing::NiceMock<CynaraMock>,
              public ::testing::NiceMock<GlibMock>,
              public ::testing::NiceMock<PkgMgrInfoMock>,
              public ::testing::NiceMock<SystemInfoMock>,
              public ::testing::NiceMock<TzplatformConfigMock>,
              public ::testing::NiceMock<VconfMock> {};

}  // namespace

class WidgetServiceTest : public TestFixture {
 public:
  WidgetServiceTest() : TestFixture(std::make_unique<::Mocks>()) {}

  void SetUp() override {
    EXPECT_CALL(GetMock<TzplatformConfigMock>(), tzplatform_mkpath(_, _))
        .WillRepeatedly(Invoke(__fake_tzplatform_mkpath));

    int ret = widget_service_check_db_integrity(false);
    ASSERT_EQ(ret, WIDGET_ERROR_NONE);
    // ... seed sample rows via the parser ...
  }

  void TearDown() override { remove(".widget_test.db"); }
};

// [P1] full happy path — every external dep wired to a "success" fake.
TEST_F(WidgetServiceTest, GetDisabled) {
  EXPECT_CALL(GetMock<SystemInfoMock>(), system_info_get_platform_bool(_, _))
      .WillRepeatedly(Invoke(__fake_system_info_get_platform_bool));
  EXPECT_CALL(GetMock<CynaraMock>(), cynara_initialize(_, _))
      .WillRepeatedly(Invoke(__fake_cynara_initialize));
  EXPECT_CALL(GetMock<CynaraMock>(), cynara_creds_self_get_client(_, _))
      .WillRepeatedly(Invoke(__fake_cynara_creds_self_get_client));
  EXPECT_CALL(GetMock<CynaraMock>(), cynara_check(_, _, _, _, _))
      .WillRepeatedly(Invoke(__fake_cynara_check));
  EXPECT_CALL(GetMock<CynaraMock>(), cynara_finish(_))
      .WillRepeatedly(Invoke(__fake_cynara_finish));

  bool is_disabled;
  int ret = widget_service_get_widget_disabled("org.tizen.gallery.widget",
                                               &is_disabled);
  ASSERT_EQ(ret, WIDGET_ERROR_NONE);
}

// [N1] NULL widget_id  AND  [N3] cynara init fails — same fixture, two
// distinct return codes asserted in sequence. Bundled because the second
// assertion *requires* the cynara mock to have been re-armed and the
// failure code is the contract being pinned per call.
TEST_F(WidgetServiceTest, GetDisabled_N) {
  EXPECT_CALL(GetMock<CynaraMock>(), cynara_initialize(_, _))
      .WillOnce(Return(1));    // forces PERMISSION_DENIED on the second call

  bool is_disabled;
  int ret = widget_service_get_widget_disabled(NULL, &is_disabled);
  ASSERT_EQ(ret, WIDGET_ERROR_INVALID_PARAMETER);   // [N1]

  ret = widget_service_get_widget_disabled("org.tizen.gallery.widget",
                                           &is_disabled);
  ASSERT_EQ(ret, WIDGET_ERROR_PERMISSION_DENIED);   // [N3]
}
```

Things to notice:

1. **`Mocks` aggregate** virtually inherits every mock the file's tests
   need, wrapped in `NiceMock<>` so unmocked calls don't pollute output.
2. **Stable mocks go in `SetUp()`** (here, `tzplatform_mkpath` and DB
   seeding). Per-case mocks go inside the `TEST_F` body.
3. **`__fake_*` helpers** in an anonymous namespace at the top of the
   file, named after the mocked symbol, used with `Invoke(...)`.
4. **Bundled `_N` test** because the asserted error codes are *different*
   per call but each call has its own assertion. This is acceptable;
   what is NOT acceptable is bundling without per-call assertions.
5. **Forced failure path** uses `WillOnce(Return(1))` for the offending
   mocked call — the simplest way to drive an `_N`.
