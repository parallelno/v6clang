//===- IntrinsicsV6CLANG.td - Defines V6CLANG intrinsics -----------*- tablegen -*-===//
//
// Part of the LLVM Project, under the Apache License v2.0 with LLVM Exceptions.
// See https://llvm.org/LICENSE.txt for license information.
// SPDX-License-Identifier: Apache-2.0 WITH LLVM-exception
//
//===----------------------------------------------------------------------===//
//
// This file defines all the V6CLANG (Intel 8080) target-specific intrinsics.
//
//===----------------------------------------------------------------------===//

let TargetPrefix = "v6clang" in {

// I/O port access
def int_v6clang_in  : Intrinsic<[llvm_i8_ty], [llvm_i8_ty],
    [IntrInaccessibleMemOnly, IntrNoCallback]>,
    ClangBuiltin<"__builtin_v6clang_in">;

def int_v6clang_out : Intrinsic<[], [llvm_i8_ty, llvm_i8_ty],
    [IntrInaccessibleMemOnly, IntrNoCallback]>,
    ClangBuiltin<"__builtin_v6clang_out">;

// Interrupt control
def int_v6clang_di  : Intrinsic<[], [], [IntrNoDuplicate, IntrHasSideEffects, IntrNoCallback]>,
    ClangBuiltin<"__builtin_v6clang_di">;

def int_v6clang_ei  : Intrinsic<[], [], [IntrNoDuplicate, IntrHasSideEffects, IntrNoCallback]>,
    ClangBuiltin<"__builtin_v6clang_ei">;

// Processor control
def int_v6clang_hlt : Intrinsic<[], [], [IntrNoDuplicate, IntrHasSideEffects, IntrNoCallback]>,
    ClangBuiltin<"__builtin_v6clang_hlt">;

def int_v6clang_nop : Intrinsic<[], [], [IntrHasSideEffects, IntrNoCallback]>,
    ClangBuiltin<"__builtin_v6clang_nop">;

} // TargetPrefix = "v6clang"
