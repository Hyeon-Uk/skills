/*
 * Copyright (c) 2026 Samsung Electronics Co., Ltd All Rights Reserved
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * http://www.apache.org/licenses/LICENSE-2.0
 */

// Pattern B header: package-specific helpers used by smoke_test.cc and
// smoke_test_helper.cc. Substitutions:
//   <PKG>     — uppercase guard token, e.g. WGT
//   <pkg>     — lowercase, e.g. wgt
//   <Pkg>     — CamelCase, e.g. Wgt

#ifndef SMOKE_TESTS_<PKG>_SMOKE_UTILS_H_
#define SMOKE_TESTS_<PKG>_SMOKE_UTILS_H_

#include <smoke_tests/common/smoke_utils.h>

#include <filesystem>
#include <string>
#include <vector>

namespace smoke_test {

// kSmokePackagesDirectory points at where %install dropped test_samples/.
// Resolved at runtime against ${SHAREDIR}/<pkg>-installer-ut/test_samples.
extern const std::filesystem::path kSmokePackagesDirectory;

// Boolean smoke validator — replaces a hand-rolled grep/file check.
// Returns true iff the package id was registered for the given uid.
bool ValidatePackage(const std::string& pkgid, uid_t uid);

// Uninstall every package that the smoke suite might have installed,
// idempotently. Used by SmokeEnvironment::TearDown to leave the device
// in a clean state even after a crashed run.
class <Pkg>BackendInterface;  // forward decl
void UninstallAllSmokeApps(common_installer::RequestMode mode,
                           uid_t uid,
                           <Pkg>BackendInterface* backend);

}  // namespace smoke_test

#endif  // SMOKE_TESTS_<PKG>_SMOKE_UTILS_H_
