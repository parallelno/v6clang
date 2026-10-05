// RUN: clang -target i8080-unknown-v6clang -O0 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t-o0.elf
// RUN: llvm-dwarfdump --debug-info --debug-rnglists %t-o0.elf | FileCheck %s --check-prefix=TYPES
// RUN: llvm-dwarfdump --verify %t-o0.elf
// RUN: clang -target i8080-unknown-v6clang -O2 -g -fno-v6clang-auto-include -nostdlib -Wl,-e,main %s -o %t-o2.elf
// RUN: llvm-dwarfdump --debug-info --debug-rnglists %t-o2.elf | FileCheck %s --check-prefix=INLINE
// RUN: llvm-dwarfdump --verify %t-o2.elf

// TYPES-DAG: DW_TAG_enumeration_type
// TYPES-DAG: DW_AT_name{{.*}}("mode")
// TYPES-DAG: DW_TAG_enumerator
// TYPES-DAG: DW_TAG_typedef
// TYPES-DAG: DW_AT_name{{.*}}("word_t")
// TYPES-DAG: DW_TAG_structure_type
// TYPES-DAG: DW_AT_name{{.*}}("layout")
// TYPES-DAG: DW_AT_byte_size{{.*}}(0x0b)
// TYPES-DAG: DW_TAG_member
// TYPES-DAG: DW_AT_name{{.*}}("tag")
// TYPES-DAG: DW_AT_data_member_location{{.*}}(0x00)
// TYPES-DAG: DW_AT_name{{.*}}("value")
// TYPES-DAG: DW_AT_data_member_location{{.*}}(0x01)
// TYPES-DAG: DW_TAG_union_type
// TYPES-DAG: DW_AT_name{{.*}}("choice")
// TYPES-DAG: DW_TAG_array_type
// TYPES-DAG: DW_TAG_subrange_type
// TYPES-DAG: DW_AT_count{{.*}}(0x03)
// TYPES-DAG: DW_TAG_pointer_type
// TYPES-DAG: DW_TAG_const_type
// TYPES-DAG: DW_TAG_volatile_type
// TYPES-DAG: DW_TAG_lexical_block
// TYPES-DAG: DW_AT_name{{.*}}("shadow")
// TYPES-DAG: DW_AT_name{{.*}}("outer")

// INLINE: DW_AT_name{{.*}}("inline_outer")
// INLINE: DW_TAG_inlined_subroutine
// INLINE: DW_AT_abstract_origin
// INLINE: DW_AT_call_file
// INLINE: DW_AT_call_line
// INLINE: DW_TAG_inlined_subroutine

typedef unsigned int word_t;
typedef int (*callback_t)(int);

enum mode { mode_zero, mode_one = 7 };

struct layout {
  unsigned char tag;
  word_t value;
  int values[3];
  enum mode current;
};

union choice {
  word_t word;
  unsigned char bytes[2];
};

volatile int sink;

__attribute__((always_inline)) static inline int inline_leaf(int value) {
  int local = value + 3;
  sink = local;
  return local;
}

__attribute__((always_inline)) static inline int inline_outer(int value) {
  int outer = inline_leaf(value);
  return outer + 1;
}

__attribute__((noinline))
int scopes_types(int shadow, const struct layout *input, volatile union choice *output,
                 callback_t callback) {
  word_t outer = input->value;
  {
    int shadow = callback(outer);
    output->word = shadow;
    sink = shadow;
  }
  return inline_outer(outer) + shadow + (int)input->values[2];
}

__attribute__((noinline))
int identity(int value) { return value; }

int main(void) {
  struct layout input = { 1, 0x1234, { 2, 3, 4 }, mode_one };
  union choice output;
  return scopes_types(5, &input, &output, identity);
}