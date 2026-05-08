# Template for <pkg>/test/smoke_tests/CMakeLists.txt (Pattern B).
#
# Substitutions:
#   <PKG>          — uppercase, e.g. WGT
#   <pkg>          — lowercase, e.g. wgt
#   ${SHAREDIR}    — usually share/ under install prefix
#   ${BINDIR}      — usually bin/ under install prefix
#   ${INCLUDEDIR}  — usually include/ under install prefix
#
# Reference: wgt-backend/test/smoke_tests/CMakeLists.txt.

SET(DESTINATION_DIR <pkg>-installer-ut)
SET(TARGET_<PKG>_SMOKE_UTILS <pkg>-smoke-utils)

ADD_EXECUTABLE(${TARGET_SMOKE_TEST}
  smoke_test.cc
)
# Optional: heavier sibling suite kept separate so smoke stays fast.
# ADD_EXECUTABLE(${TARGET_SMOKE_TEST_EXTENSIVE}
#   extensive_smoke_test.cc
# )
ADD_EXECUTABLE(${TARGET_SMOKE_TEST_HELPER}
  smoke_test_helper.cc
)
ADD_LIBRARY(${TARGET_<PKG>_SMOKE_UTILS} SHARED
  <pkg>_smoke_utils.cc
)

TARGET_INCLUDE_DIRECTORIES(${TARGET_SMOKE_TEST} PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/../)
TARGET_INCLUDE_DIRECTORIES(${TARGET_SMOKE_TEST_HELPER} PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/../)
TARGET_INCLUDE_DIRECTORIES(${TARGET_<PKG>_SMOKE_UTILS} PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}/../)

# `test_samples/` is the directory of real .wgt/.tpk/.rpk fixtures the smoke
# suite installs at runtime. ISARC64 guard mirrors the existing convention.
IF(${ISARC64} MATCHES "0")
INSTALL(DIRECTORY test_samples/ DESTINATION ${SHAREDIR}/${DESTINATION_DIR}/test_samples)
ENDIF()

APPLY_PKG_CONFIG(${TARGET_SMOKE_TEST} PUBLIC
  GMOCK_DEPS
  GUM_DEPS    # add/remove DEPS to match the package's runtime needs
)

# GTest's pkgconfig doesn't expose gtest_main on Tizen, so link
# GTEST_MAIN_LIBRARIES explicitly. Match the existing convention.
TARGET_LINK_LIBRARIES(${TARGET_SMOKE_TEST} PRIVATE
  ${TARGET_LIBNAME_<PKG>}
  ${GTEST_MAIN_LIBRARIES}
  ${TARGET_SMOKE_UTILS}        # common helpers from app-installers
  ${TARGET_<PKG>_SMOKE_UTILS}  # this package's own helpers
)
TARGET_LINK_LIBRARIES(${TARGET_SMOKE_TEST_HELPER} PRIVATE
  ${TARGET_LIBNAME_<PKG>}
  ${TARGET_<PKG>_SMOKE_UTILS}
)
TARGET_LINK_LIBRARIES(${TARGET_<PKG>_SMOKE_UTILS} PRIVATE
  ${TARGET_LIBNAME_<PKG>}
  ${TARGET_SMOKE_UTILS}
)

INSTALL(TARGETS ${TARGET_SMOKE_TEST}        DESTINATION ${BINDIR}/${DESTINATION_DIR})
INSTALL(TARGETS ${TARGET_SMOKE_TEST_HELPER} DESTINATION ${BINDIR}/${DESTINATION_DIR})
INSTALL(TARGETS ${TARGET_<PKG>_SMOKE_UTILS} DESTINATION ${LIB_INSTALL_DIR})
INSTALL(FILES <pkg>_smoke_utils.h DESTINATION ${INCLUDEDIR}/app-installers/smoke_tests/)
