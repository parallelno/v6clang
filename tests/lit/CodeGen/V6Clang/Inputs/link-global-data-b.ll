; Helper file for link-global-data.ll — defines shared_val global variable.

target datalayout = "e-p:16:8-i1:8-i8:8-i16:8-i32:8-i64:8-n8:16-S8"
target triple = "i8080-unknown-v6clang"

@shared_val = global i8 99
