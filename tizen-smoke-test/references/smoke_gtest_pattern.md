# Pattern B — separate smoke gtest binary

This pattern is used by **installer-shaped packages** — code whose job is to
install/uninstall other packages — where "smoke" really means "the install
pipeline still works end-to-end on a real artefact". Reference implementations:

- `wgt-backend/test/smoke_tests/`
- `tpk-backend/test/smoke_tests/`
- `rpk-installer/test/smoke_tests/`
- `unified-backend/test/smoke_test/`
- `app-installers/test/smoke_tests/`

If you're not writing tests for an installer, you almost certainly want
Pattern A instead. Pattern B has more moving pieces — separate binary,
separate sub-package, `setcap` post-install — and the cost only pays off
when the smoke check is actually a multi-step install round trip.

## Directory layout

```
<pkg>/test/smoke_tests/
  ├── CMakeLists.txt
  ├── smoke_test.cc              # the gtest binary
  ├── smoke_test_helper.cc       # auxiliary process spawned by some tests
  ├── <pkg>_smoke_utils.h
  ├── <pkg>_smoke_utils.cc       # backend interfaces, BackupPath, etc.
  ├── extensive_smoke_test.cc    # heavier sibling binary (optional)
  └── test_samples/              # real .wgt/.tpk/.rpk fixture artefacts
```

`test_samples/` is the directory of small, real packages that the smoke
suite installs at runtime. They ship as data:

```cmake
INSTALL(DIRECTORY test_samples/ DESTINATION ${SHAREDIR}/<pkg>-installer-ut/test_samples)
```

…and `kSmokePackagesDirectory` resolves to that path in C++.

## The `testing::Environment` + signal-handler pattern

Smoke for installers requires *system-level* setup: creating a test user,
backing up paths under `/opt/usr/...` so the test can mutate them safely,
initializing the package DB. This setup must happen exactly once before any
`TEST_F` runs, and unwind exactly once after the last `TEST_F` exits — even
if a `TEST_F` crashed midway.

The shape (canonical version: `wgt-backend/test/smoke_tests/smoke_test.cc:25–47`):

```cpp
class SmokeEnvironment : public testing::Environment {
 public:
  void SetUp() override {
    if (request_mode_ == ci::RequestMode::USER)
      ASSERT_TRUE(AddTestUser(&test_user));
    backups_ = SetupBackupDirectories(test_user.uid);
    for (auto& path : backups_) ASSERT_TRUE(BackupPath(path));
    CreateDatabase();
  }
  void TearDown() override {
    ASSERT_TRUE(request_mode_ == ci::RequestMode::GLOBAL ||
                (request_mode_ == ci::RequestMode::USER &&
                 kGlobalUserUid != test_user.uid));    // safety belt
    UninstallAllSmokeApps(request_mode_, test_user.uid, &backend);
    for (auto& path : backups_) ASSERT_TRUE(RestorePath(path));
    if (request_mode_ == ci::RequestMode::USER) ASSERT_TRUE(DeleteTestUser());
  }
  // ...
};
```

Two non-obvious rules.

### Rule 1 — install signal handlers in `main`

If the test binary is killed mid-install (Ctrl-C, OOM, segfault), gtest does
*not* run `Environment::TearDown()`, and the device is left with `*.bck`
backup files lying around plus a stranded test user.

The fix:

```cpp
void signalHandler(int signum) {
  if (env) env->TearDown();
  exit(signum);
}

int main(int argc, char** argv) {
  signal(SIGINT,  signalHandler);
  signal(SIGTERM, signalHandler);
  signal(SIGABRT, signalHandler);
  // ...
  return RUN_ALL_TESTS();
}
```

Without this, your second smoke run starts with leftover state and "fails"
in ways that look like product regressions.

### Rule 2 — guard `DeleteTestUser` with a uid check

`TearDown` must never delete a user that wasn't created by the test. The
`ASSERT_TRUE(... kGlobalUserUid != test_user.uid)` is a safety belt — if a
logic bug somehow set `test_user.uid` to a system uid, the assertion stops
the smoke suite from doing damage. Keep this assertion verbatim from the
existing packages.

## `setcap` in `%post`

The smoke binary issues real install/uninstall calls, which means it touches
SMACK-protected paths and changes file ownership. On a hardened Tizen image,
that requires Linux capabilities the binary doesn't have by default. The
spec file applies them in `%post`:

```spec
%post -n %{name}-installer-ut
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/<pkg>-installer-ut/smoke-test
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/<pkg>-installer-ut/smoke-test-helper
```

Add a `setcap` line per binary you ship under `<pkg>-installer-ut/`. Without
this, the install calls fail with `EPERM` and the failure looks like a logic
bug in the installer pipeline.

## What goes in a TEST_F (and what doesn't)

Each `TEST_F` should be one round trip with two or three assertions:

```cpp
TEST_F(SmokeTest, InstallationMode) {
  fs::path path = kSmokePackagesDirectory / "InstallationMode.wgt";
  std::string pkgid = "smokewgt03";
  ASSERT_EQ(backend.Install(path), ci::AppInstaller::Result::OK);
  ASSERT_TRUE(ValidatePackage(pkgid, env->test_user.uid));
  ASSERT_EQ(backend.Uninstall(pkgid), ci::AppInstaller::Result::OK);
}
```

Keep these rules in mind:

- **One package per `TEST_F`.** If a regression breaks installs of `.wgt`
  but not `.tpk`, that fault should land on a single failing test name, not
  a multi-package fixture where you have to read the log to find out what
  failed.
- **Always uninstall what you installed.** Even though `Environment::TearDown`
  has a final `UninstallAllSmokeApps`, an explicit `Uninstall` per test is
  what makes the suite re-runnable when a single `TEST_F` is filtered.
- **Don't share state between `TEST_F`s.** A test that depends on `Test1`
  having installed `pkg.wgt` is going to pass when run as a suite and fail
  when run with `--gtest_filter='Test2'`.
- **Keep the assertions strict.** Use `ASSERT_EQ(..., Result::OK)`, not
  `ASSERT_NE(..., Result::FAIL)`. Pinning the exact return value catches
  the case where the installer "succeeds" but emits a different success
  enum that the contract has changed under you.

## Anti-patterns

- **Mocking the installer pipeline.** Defeats the entire purpose. If you
  catch yourself reaching for `MOCK_METHOD`, you're writing a unit test
  in the wrong directory.
- **Hand-rolled fixture binaries that duplicate `Install`/`Uninstall`.**
  Use the existing `BackendInterface` from `app-installers/`. Re-implementing
  the install path in test code means you're testing your test code, not
  the production pipeline.
- **`fs::remove_all("/opt/usr/...")` in `TearDown` instead of `RestorePath`.**
  If the smoke run crashes and the next run sees no backup, full removal
  destroys legitimate user data. Always use `BackupPath`/`RestorePath`.
- **Smoke binaries without `setcap`.** They build, they install, they run,
  they fail with `EPERM`. Always pair a new `INSTALL(TARGETS ...)` line
  with a `setcap` line in `%post`.
