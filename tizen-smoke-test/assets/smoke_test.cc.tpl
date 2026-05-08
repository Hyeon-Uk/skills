/*
 * Copyright (c) 2026 Samsung Electronics Co., Ltd All Rights Reserved
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 */

// Pattern B template — replace these placeholders before scaffolding:
//   <Pkg>            — fixture root, e.g. WgtBackend, TpkBackend, RpkInstaller
//   <pkg>            — file/binary slug, e.g. wgt, tpk, rpk
//   <PackageType>    — enum value for ci::PackageType (WGT / TPK / RPK / ...)
//   <BackendIface>   — backend interface class name (WgtBackendInterface, ...)
//   <smoke_utils.h>  — package-specific helpers header
//
// Reference: wgt-backend/test/smoke_tests/smoke_test.cc.

#include <gtest/gtest.h>
#include <gtest/gtest-death-test.h>
#include <signal.h>
#include <smoke_tests/common/smoke_utils.h>

#include <filesystem>
#include <memory>
#include <vector>

#include "smoke_tests/<pkg>_smoke_utils.h"

namespace ci = common_installer;
namespace fs = std::filesystem;
namespace st = smoke_test;

namespace smoke_test {

// Owns system-level setup that lives across all TEST_F instances:
// test user creation, backup/restore of system paths, DB initialization.
// One instance, registered with AddGlobalTestEnvironment in main().
class SmokeEnvironment : public testing::Environment {
 public:
  explicit SmokeEnvironment(ci::RequestMode mode) : request_mode_(mode) {}

  void SetUp() override {
    if (request_mode_ == ci::RequestMode::USER)
      ASSERT_TRUE(AddTestUser(&test_user));
    backups_ = SetupBackupDirectories(test_user.uid);
    for (auto& path : backups_) ASSERT_TRUE(BackupPath(path));
    CreateDatabase();
  }

  void TearDown() override {
    // Don't run real DeleteTestUser as the global user — the assert protects
    // against a smoke run that, due to a logic bug, somehow inherited a
    // production-relevant uid.
    ASSERT_TRUE(request_mode_ == ci::RequestMode::GLOBAL ||
                (request_mode_ == ci::RequestMode::USER &&
                 kGlobalUserUid != test_user.uid));
    <BackendIface> backend(std::to_string(test_user.uid));
    UninstallAllSmokeApps(request_mode_, test_user.uid, &backend);
    for (auto& path : backups_) ASSERT_TRUE(RestorePath(path));
    if (request_mode_ == ci::RequestMode::USER) ASSERT_TRUE(DeleteTestUser());
  }

  User test_user;

 private:
  ci::RequestMode request_mode_;
  std::vector<fs::path> backups_;
};

}  // namespace smoke_test

namespace {

smoke_test::SmokeEnvironment* env = nullptr;

// If the test binary is killed mid-install, we still need to unwind:
// otherwise the device is left with backups *.bck / a stale test user.
void signalHandler(int signum) {
  if (env) env->TearDown();
  exit(signum);
}

}  // namespace

namespace smoke_test {

class <Pkg>SmokeTest : public ::testing::Test {
 public:
  <Pkg>SmokeTest()
      : backend(std::to_string(env->test_user.uid)),
        params{ci::PackageType::<PackageType>, /*preload=*/false} {
    params.test_user.uid = env->test_user.uid;
    params.test_user.gid = env->test_user.gid;
  }

 protected:
  <BackendIface> backend;
  TestParameters params;
};

// One install + uninstall round trip. Keep the assertions tight — this is
// smoke, not coverage. If the install pipeline regresses, this test fails;
// if a deeper invariant regresses, that's a job for the unit test suite.
TEST_F(<Pkg>SmokeTest, InstallationMode) {
  fs::path path = kSmokePackagesDirectory / "InstallationMode.<pkg>";
  std::string pkgid = "smoke<pkg>03";
  ASSERT_EQ(backend.Install(path), ci::AppInstaller::Result::OK);
  ASSERT_TRUE(ValidatePackage(pkgid, env->test_user.uid));
  ASSERT_EQ(backend.Uninstall(pkgid), ci::AppInstaller::Result::OK);
}

}  // namespace smoke_test

int main(int argc, char** argv) {
  signal(SIGINT, signalHandler);
  signal(SIGTERM, signalHandler);
  signal(SIGABRT, signalHandler);

  testing::InitGoogleTest(&argc, argv);

  // RequestMode comes from a CLI flag in production usage — default to USER
  // so the suite is hermetic by default and doesn't touch GLOBAL state.
  smoke_test::env = new smoke_test::SmokeEnvironment(
      common_installer::RequestMode::USER);
  testing::AddGlobalTestEnvironment(smoke_test::env);

  return RUN_ALL_TESTS();
}
