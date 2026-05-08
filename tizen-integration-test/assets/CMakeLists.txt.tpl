# Template for <pkg>/test/integ_tests/CMakeLists.txt
#
# Substitutions:
#   <TARGET_VAR>   — e.g. TARGET_RPC_PORT_INTEGTESTS  (must be SET() in top-level CMakeLists.txt)
#   <TARGET_PKG>   — e.g. TARGET_RPC_PORT             (the real library target this links against)
#   Add or remove *_DEPS lines under APPLY_PKG_CONFIG to match the package's pkg-config deps.

AUX_SOURCE_DIRECTORY(${CMAKE_CURRENT_SOURCE_DIR} INTEG_TEST_SRCS)

ADD_EXECUTABLE(${<TARGET_VAR>}
  ${INTEG_TEST_SRCS})

TARGET_INCLUDE_DIRECTORIES(${<TARGET_VAR>} PUBLIC
  ${CMAKE_CURRENT_SOURCE_DIR}
  ${CMAKE_CURRENT_SOURCE_DIR}/../../include)

APPLY_PKG_CONFIG(${<TARGET_VAR>} PUBLIC
  GLIB_DEPS
  GMOCK_DEPS
  # add more *_DEPS here as needed (AUL_DEPS, BUNDLE_DEPS, DLOG_DEPS, ...)
)

TARGET_LINK_LIBRARIES(${<TARGET_VAR>} PUBLIC ${<TARGET_PKG>})

SET_TARGET_PROPERTIES(${<TARGET_VAR>} PROPERTIES
  COMPILE_FLAGS "-fPIE")
SET_TARGET_PROPERTIES(${<TARGET_VAR>} PROPERTIES
  LINK_FLAGS "-pie")

INSTALL(TARGETS ${<TARGET_VAR>} DESTINATION bin)

# Optional — for suites that ship helper scripts (e.g. cert generation):
# INSTALL(PROGRAMS ${CMAKE_CURRENT_SOURCE_DIR}/certs/mk_certs.sh DESTINATION bin)
