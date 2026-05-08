# Example — Pattern B walkthrough using wgt-backend

This is the heavier pattern: the package's job is to install other packages,
so smoke means "install a real .wgt and confirm it landed". Reference
implementation: `wgt-backend/test/smoke_tests/`.

## Phase 1 — Worksheet

```
Package:           wgt-backend
Failure mode:      "the wgt installer no longer accepts a normal .wgt because
                   manifest-parser or signature-check regressed"
Pattern selected:  B — separate smoke gtest binary with setcap'd elevated caps
Signal:            backend.Install(path) returns ci::AppInstaller::Result::OK
                   AND ValidatePackage(pkgid, uid) returns true
                   AND backend.Uninstall(pkgid) returns Result::OK
Pass criterion:    every TEST_F passes
Fail criterion:    any ASSERT_EQ / ASSERT_TRUE fails
Time budget:       under 60 seconds for the smoke binary; extensive_smoke is separate
Boundary:          real installer pipeline, real filesystem mutation under
                   /opt/usr/<test-uid>/, real package DB write
```

Checklist:
- [x] One-sentence failure mode.
- [x] Each TEST_F is one install/uninstall round trip.
- [x] Cleanup on disk via BackupPath/RestorePath; uninstall in TearDown.
- [x] Signal handler installed in main() so a crash still unwinds.
- [x] No mocks of the installer pipeline.

## Phase 2 — Files added

```
wgt-backend/test/smoke_tests/CMakeLists.txt           # already exists
wgt-backend/test/smoke_tests/smoke_test.cc            # already exists
wgt-backend/test/smoke_tests/wgt_smoke_utils.{h,cc}   # already exists
wgt-backend/test/smoke_tests/test_samples/            # real .wgt artefacts
wgt-backend/packaging/wgt-backend.spec                # already has %package + %post + %files for installer-ut
```

(For a new installer package starting from scratch, copy each file from this
list and substitute the names.)

## Phase 3 — One TEST_F

```cpp
TEST_F(SmokeTest, InstallationMode) {
  fs::path path = kSmokePackagesDirectory / "InstallationMode.wgt";
  std::string pkgid = "smokewgt03";
  std::string appid = "smokewgt03.InstallationMode";
  ASSERT_EQ(backend.Install(path), ci::AppInstaller::Result::OK);
  ASSERT_TRUE(ValidatePackage(pkgid, env->test_user.uid));
  ASSERT_EQ(backend.Uninstall(pkgid), ci::AppInstaller::Result::OK);
}
```

Things to notice:

- One package per `TEST_F` — fault isolation.
- `kSmokePackagesDirectory` is resolved at runtime against
  `${SHAREDIR}/wgt-installer-ut/test_samples/`, which the spec installs via
  `INSTALL(DIRECTORY test_samples/ ...)`.
- Both ASSERT_EQs pin the *exact* success enum, not just non-failure.

## Phase 4 — Spec wiring

```spec
%package -n %{name}-installer-ut
Summary:    WGT installer smoke tests
Group:      Development/Libraries
Requires:   %{name}

%description -n %{name}-installer-ut
End-to-end install/uninstall smoke for wgt-backend.

%post -n %{name}-installer-ut
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/wgt-installer-ut/smoke-test
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/wgt-installer-ut/smoke-test-helper
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/wgt-installer-ut/hybrid-smoke-test-helper
/usr/sbin/setcap cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip %{_bindir}/wgt-installer-ut/extensive-smoke-test

%files -n %{name}-installer-ut
%{_bindir}/wgt-installer-ut/smoke-test
%{_bindir}/wgt-installer-ut/smoke-test-helper
%{_bindir}/wgt-installer-ut/hybrid-smoke-test-helper
%{_bindir}/wgt-installer-ut/extensive-smoke-test
%{_libdir}/libwgt-smoke-utils.so*
%{_includedir}/app-installers/smoke_tests/wgt_smoke_utils.h
%{_datadir}/wgt-installer-ut/test_samples/
```

## Phase 5 — Build + run

```bash
cd ~/.openclaw/workspace/gerrit/wgt-backend
gbs build -A x86_64 --include-all

# After install on the device:
sdb root on
sdb shell /usr/bin/wgt-installer-ut/smoke-test --gtest_break_on_failure
```

If the binary runs but `Install` fails with EPERM, run:

```bash
sdb shell getcap /usr/bin/wgt-installer-ut/smoke-test
```

…and confirm it prints `cap_chown,cap_dac_override,cap_fowner,cap_mac_override=eip`.
If empty, the `%post` setcap line didn't run — usually because of a path
typo or because `setcap` itself isn't installed on the image.
