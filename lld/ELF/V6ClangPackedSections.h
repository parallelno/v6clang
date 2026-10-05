//===- V6ClangPackedSections.h --------------------------------------*- C++ -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//

#ifndef LLD_ELF_V6ClangPACKEDSECTIONS_H
#define LLD_ELF_V6ClangPACKEDSECTIONS_H

#include "llvm/ADT/ArrayRef.h"
#include <cstdint>

namespace lld::elf {

class OutputSection;

enum class V6ClangPackKind { Filler, Anchor, Window };

struct V6ClangPackBlock {
    V6ClangPackKind kind;
    uint64_t size;
    uint64_t originalOrder;
    uint64_t addr = 0;
};

enum class V6ClangPackResult {
    Success,
    InvalidBlock,
    AddressOverflow,
    AddressSpaceOverflow,
};

V6ClangPackResult
assignV6ClangPackedBlockAddresses(llvm::MutableArrayRef<V6ClangPackBlock> blocks,
                                                            uint64_t startAddr, uint64_t &endAddr);

bool assignV6ClangPackedSectionOffsets(OutputSection &osec, uint64_t startAddr,
                                   uint64_t &endAddr);

} // namespace lld::elf

#endif