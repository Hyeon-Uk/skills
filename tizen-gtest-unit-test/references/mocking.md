# Mocking pattern reference

This is the canonical mocking pattern used across the Tizen AppFW packages
in this workspace. It has three layers:

```
┌──────────────────────────────────────────────────────────────────┐
│  test_fixture.{hh,cc}    — owns the active mock as a static      │
│  module_mock.{hh}        — empty base class, common to all mocks │
│  mock_hook.{hh}          — MOCK_HOOK_Pn(MOCK_CLASS, fn, args...) │
└──────────────────────────────────────────────────────────────────┘
            ▲                                       ▲
            │ inherits virtually                    │ used by
            │                                       │
┌───────────┴───────────┐                  ┌────────┴───────────────┐
│  <module>_mock.hh     │                  │  <module>_mock.cc      │
│  class XxxMock        │                  │  extern "C" trampolines│
│   : virtual ModuleMock│                  │  call MOCK_HOOK_Pn(...)│
│   MOCK_METHODn(...)   │                  └────────────────────────┘
└───────────────────────┘
```

The trampolines in `<module>_mock.cc` are linked **in place of** the real
library symbols. When the production code under test calls `cynara_check(...)`,
the linker resolves to your `extern "C" int cynara_check(...)` which calls
`TestFixture::GetMock<CynaraMock>().cynara_check(...)`. Each test then sets
expectations on that gmock method.

This is why every package's unit test target links the package's own sources
*directly* (not the installed `.so`) — so that the linker sees both the real
caller and your mock and resolves the unresolved symbol to the mock.

---

## 1. `module_mock.hh` (one per package, common base)

```cpp
#ifndef MOCK_MODULE_MOCK_HH_
#define MOCK_MODULE_MOCK_HH_

class ModuleMock {
 public:
  virtual ~ModuleMock() {}
};

#endif
```

Empty on purpose. Its only job is to be the type that `TestFixture::mock_`
can hold via `unique_ptr<ModuleMock>`, with each concrete mock deriving
**virtually** so that the `Mocks` aggregate can multiply-inherit them.

## 2. `test_fixture.hh` / `test_fixture.cc` (one per package)

```cpp
// test_fixture.hh
#ifndef MOCK_TEST_FIXTURE_HH_
#define MOCK_TEST_FIXTURE_HH_

#include <gtest/gtest.h>
#include <memory>
#include <stdexcept>
#include <string>
#include <utility>
#include "module_mock.hh"

class TestFixture : public ::testing::Test {
 public:
  explicit TestFixture(std::unique_ptr<ModuleMock>&& mock) {
    mock_ = std::move(mock);
  }
  ~TestFixture() override { mock_.reset(); }

  void SetUp() override {}
  void TearDown() override {}

  template <typename T>
  static T& GetMock() {
    auto ptr = dynamic_cast<T*>(mock_.get());
    if (!ptr) {
      throw std::invalid_argument(
          "The test does not provide mock of \"" +
          std::string(typeid(T).name()) + "\"");
    }
    return *ptr;
  }

  static std::unique_ptr<ModuleMock> mock_;
};
#endif
```

```cpp
// test_fixture.cc
#include "test_fixture.hh"
std::unique_ptr<ModuleMock> TestFixture::mock_;
```

## 3. `mock_hook.hh` (one per package)

```cpp
#ifndef MOCK_MOCK_HOOK_HH_
#define MOCK_MOCK_HOOK_HH_

#define MOCK_HOOK_P0(MC, f)                  TestFixture::GetMock<MC>().f()
#define MOCK_HOOK_P1(MC, f, p1)              TestFixture::GetMock<MC>().f(p1)
#define MOCK_HOOK_P2(MC, f, p1, p2)          TestFixture::GetMock<MC>().f(p1, p2)
#define MOCK_HOOK_P3(MC, f, p1, p2, p3)      TestFixture::GetMock<MC>().f(p1, p2, p3)
#define MOCK_HOOK_P4(MC, f, p1, p2, p3, p4)  TestFixture::GetMock<MC>().f(p1, p2, p3, p4)
#define MOCK_HOOK_P5(MC, f, p1, p2, p3, p4, p5)                              \
    TestFixture::GetMock<MC>().f(p1, p2, p3, p4, p5)
#define MOCK_HOOK_P6(MC, f, p1, p2, p3, p4, p5, p6)                          \
    TestFixture::GetMock<MC>().f(p1, p2, p3, p4, p5, p6)
#define MOCK_HOOK_P7(MC, f, p1, p2, p3, p4, p5, p6, p7)                      \
    TestFixture::GetMock<MC>().f(p1, p2, p3, p4, p5, p6, p7)
#define MOCK_HOOK_P8(MC, f, p1, p2, p3, p4, p5, p6, p7, p8)                  \
    TestFixture::GetMock<MC>().f(p1, p2, p3, p4, p5, p6, p7, p8)

#endif
```

Add more arities only when needed.

## 4. A concrete `<module>_mock` pair

`aul_mock.hh` — declares the gmock methods, one per intercepted C symbol:

```cpp
#ifndef MOCK_AUL_MOCK_HH_
#define MOCK_AUL_MOCK_HH_

#include <aul.h>
#include <bundle.h>
#include <gmock/gmock.h>
#include "module_mock.hh"

class AulMock : public virtual ModuleMock {
 public:
  ~AulMock() override {}

  MOCK_METHOD0(aul_debug_info_init, int (void));
  MOCK_METHOD1(aul_widget_instance_count, int (const char*));
  MOCK_METHOD2(aul_launch_app_async, int (const char*, bundle*));
  MOCK_METHOD3(aul_app_get_pkgid_bypid, int (int, char*, int));
  // ... one MOCK_METHODn per symbol the production code calls
};
#endif
```

`aul_mock.cc` — `extern "C"` trampolines that the linker resolves
**in place of** the real `libaul.so` symbols when building the unittest:

```cpp
#include "aul_mock.hh"
#include "mock_hook.hh"
#include "test_fixture.hh"

extern "C" int aul_debug_info_init(void) {
  return MOCK_HOOK_P0(AulMock, aul_debug_info_init);
}

extern "C" int aul_widget_instance_count(const char* widget_id) {
  return MOCK_HOOK_P1(AulMock, aul_widget_instance_count, widget_id);
}

extern "C" int aul_launch_app_async(const char* appid, bundle* b) {
  return MOCK_HOOK_P2(AulMock, aul_launch_app_async, appid, b);
}

extern "C" int aul_app_get_pkgid_bypid(int pid, char* buf, int len) {
  return MOCK_HOOK_P3(AulMock, aul_app_get_pkgid_bypid, pid, buf, len);
}
```

**Important**: the test target's CMakeLists must NOT add `-laul` (or whatever
the real library is) to the link line. If it does, the linker may pick the
real symbol over your trampoline, and your `EXPECT_CALL`s will silently never
trigger. Link only `gmock`, `dlog`, `glib-2.0`, and the package's own sources.

## 5. The `Mocks` aggregate

In each test file, define one aggregate that virtually inherits all the
mocks the file's tests need. Wrap each parent in `::testing::NiceMock<>`
to silence "uninteresting call" warnings (you only want failures from
`EXPECT_CALL`s you actually wrote).

```cpp
class Mocks : public ::testing::NiceMock<AulMock>,
              public ::testing::NiceMock<CynaraMock>,
              public ::testing::NiceMock<GlibMock>,
              public ::testing::NiceMock<PkgMgrInfoMock>,
              public ::testing::NiceMock<SystemInfoMock>,
              public ::testing::NiceMock<TzplatformConfigMock>,
              public ::testing::NiceMock<VconfMock> {};
```

Pass this to `TestFixture` from the fixture constructor:

```cpp
class WidgetServiceTest : public TestFixture {
 public:
  WidgetServiceTest() : TestFixture(std::make_unique<Mocks>()) {}
};
```

## 6. Setting expectations

Use the `gmock` matchers (`_`, `Eq`, `An<T>()`, ...) and actions (`Return`,
`Invoke`, `DoAll`, `SetArgPointee`, `InvokeArgument<N>`):

```cpp
using ::testing::_;
using ::testing::DoAll;
using ::testing::Invoke;
using ::testing::Return;
using ::testing::SetArgPointee;

// stable for the whole test
EXPECT_CALL(GetMock<TzplatformConfigMock>(), tzplatform_mkpath(_, _))
    .WillRepeatedly(Invoke(__fake_tzplatform_mkpath));

// just for this case
EXPECT_CALL(GetMock<CynaraMock>(), cynara_initialize(_, _))
    .WillOnce(Return(1));   // simulate failure to drive the _N path

// out-param + return value pair
EXPECT_CALL(GetMock<SystemInfoMock>(), system_info_get_platform_int(_, _))
    .WillOnce(DoAll(SetArgPointee<1>(320), Return(SYSTEM_INFO_ERROR_NONE)));

// fire a callback registered through a mocked function
EXPECT_CALL(GetMock<AulMock>(), aul_app_com_create(_, _, _, _, _))
    .WillOnce(DoAll(InvokeArgument<2>("end", AUL_APP_COM_R_OK, b, nullptr),
                    Return(0)));
```

`__fake_*` free functions in the anonymous namespace at the top of the test
file are the canonical place to put non-trivial fake behavior. Keep them
short and pure — no test state, no globals beyond the `TestFixture`.

## 7. When NOT to mock

- The package's **own** internal helpers — those are the system under test.
- Pure data/header-only utilities (`bundle_create`, `g_strdup`) when their
  side effects are part of what you are asserting. Mocking them just
  duplicates work and hides bugs. Mock them only when their failure modes
  (out-of-memory, etc.) are actually part of an `_N` case.
- Standard C library functions (`strncpy`, `memcpy`). Trust them.
