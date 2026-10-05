//===- V6ClangPackedSectionsTest.cpp --------------------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#include "V6ClangPackedSections.h"
#include "gtest/gtest.h"
#include <limits>

using namespace lld::elf;

namespace {

V6ClangPackBlock block(V6ClangPackKind kind, uint64_t size, uint64_t order) {
  return {kind, size, order};
}

TEST(V6ClangPackedSections, EmptyAndSingleBlock) {
  uint64_t end = 0;
  EXPECT_EQ(V6ClangPackResult::Success,
            assignV6ClangPackedBlockAddresses({}, 0x123, end));
  EXPECT_EQ(0x123u, end);

  V6ClangPackBlock filler = block(V6ClangPackKind::Filler, 7, 0);
  EXPECT_EQ(V6ClangPackResult::Success,
            assignV6ClangPackedBlockAddresses(filler, 0x123, end));
  EXPECT_EQ(0x123u, filler.addr);
  EXPECT_EQ(0x12au, end);
}

TEST(V6ClangPackedSections, WindowValidationAndPagePlacement) {
  uint64_t end = 0;
  V6ClangPackBlock exact = block(V6ClangPackKind::Window, 256, 0);
  EXPECT_EQ(V6ClangPackResult::Success,
            assignV6ClangPackedBlockAddresses(exact, 0x101, end));
  EXPECT_EQ(0x200u, exact.addr);
  EXPECT_EQ(0x300u, end);

  V6ClangPackBlock oversized = block(V6ClangPackKind::Window, 257, 0);
  EXPECT_EQ(V6ClangPackResult::InvalidBlock,
            assignV6ClangPackedBlockAddresses(oversized, 0, end));
}

TEST(V6ClangPackedSections, HolesBestFitAndStableTies) {
  V6ClangPackBlock blocks[] = {
      block(V6ClangPackKind::Anchor, 100, 0),
      block(V6ClangPackKind::Anchor, 300, 1),
      block(V6ClangPackKind::Window, 120, 2),
      block(V6ClangPackKind::Window, 256, 3),
      block(V6ClangPackKind::Window, 200, 4),
      block(V6ClangPackKind::Window, 20, 5),
      block(V6ClangPackKind::Window, 20, 6),
      block(V6ClangPackKind::Filler, 40, 7),
      block(V6ClangPackKind::Filler, 60, 8),
  };
  uint64_t end = 0;
  ASSERT_EQ(V6ClangPackResult::Success,
            assignV6ClangPackedBlockAddresses(blocks, 0x10a, end));
  EXPECT_EQ(0x400u, blocks[0].addr);
  EXPECT_EQ(0x200u, blocks[1].addr);
  EXPECT_EQ(0x464u, blocks[2].addr);
  EXPECT_EQ(0x500u, blocks[3].addr);
  EXPECT_EQ(0x32cu, blocks[4].addr);
  EXPECT_EQ(0x4dcu, blocks[5].addr);
  EXPECT_EQ(0x10au, blocks[6].addr);
  EXPECT_EQ(0x15au, blocks[7].addr);
  EXPECT_EQ(0x11eu, blocks[8].addr);
  EXPECT_EQ(0x600u, end);
}

TEST(V6ClangPackedSections, ReferenceWorkloadHasNoWaste) {
  V6ClangPackBlock blocks[] = {
      block(V6ClangPackKind::Anchor, 256, 0),
      block(V6ClangPackKind::Anchor, 256, 1),
      block(V6ClangPackKind::Anchor, 256, 2),
      block(V6ClangPackKind::Anchor, 240, 3),
      block(V6ClangPackKind::Window, 227, 4),
      block(V6ClangPackKind::Window, 17, 5),
      block(V6ClangPackKind::Window, 64, 6),
      block(V6ClangPackKind::Window, 62, 7),
      block(V6ClangPackKind::Filler, 16, 8),
      block(V6ClangPackKind::Filler, 10, 9),
      block(V6ClangPackKind::Filler, 2, 10),
      block(V6ClangPackKind::Filler, 512, 11),
      block(V6ClangPackKind::Filler, 482, 12),
      block(V6ClangPackKind::Filler, 480, 13),
      block(V6ClangPackKind::Filler, 240, 14),
      block(V6ClangPackKind::Filler, 31, 15),
      block(V6ClangPackKind::Filler, 17, 16),
      block(V6ClangPackKind::Filler, 16, 17),
      block(V6ClangPackKind::Filler, 16, 18),
      block(V6ClangPackKind::Filler, 15, 19),
      block(V6ClangPackKind::Filler, 14, 20),
      block(V6ClangPackKind::Filler, 2, 21),
      block(V6ClangPackKind::Filler, 1, 22),
  };
  uint64_t end = 0;
  ASSERT_EQ(V6ClangPackResult::Success,
            assignV6ClangPackedBlockAddresses(blocks, 0, end));
  EXPECT_EQ(3232u, end);
}

TEST(V6ClangPackedSections, RejectsInvalidAndOverflowingBlocks) {
  uint64_t end = 0;
  V6ClangPackBlock empty = block(V6ClangPackKind::Filler, 0, 0);
  EXPECT_EQ(V6ClangPackResult::InvalidBlock,
            assignV6ClangPackedBlockAddresses(empty, 0, end));

  V6ClangPackBlock addressSpace = block(V6ClangPackKind::Filler, 257, 0);
  EXPECT_EQ(V6ClangPackResult::AddressSpaceOverflow,
            assignV6ClangPackedBlockAddresses(addressSpace, 0xff00, end));

  V6ClangPackBlock arithmetic = block(V6ClangPackKind::Anchor, 1, 0);
  EXPECT_EQ(V6ClangPackResult::AddressSpaceOverflow,
            assignV6ClangPackedBlockAddresses(
                arithmetic, std::numeric_limits<uint64_t>::max(), end));
}

} // namespace
