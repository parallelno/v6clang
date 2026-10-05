# Test usage of LLD as a library.
# This test covers a more singular case where only one LLD driver is used in the
# target application executable.

add_lld_unittests(LLDAsLibELFTests
  ROCm.cpp
  SomeDrivers.cpp
  V6ClangPackedSectionsTest.cpp
)

target_include_directories(LLDAsLibELFTests PRIVATE ${LLD_SOURCE_DIR}/ELF)

target_link_libraries(LLDAsLibELFTests
  PRIVATE
  lldCommon
  lldELF
)
