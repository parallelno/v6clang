# Future Optimizations — V6CLANG Backend

### Implementation order

**Phase 1 — Quick wins (Low complexity, immediate benefit)**:

✅ O14_tail_call_optimization.md
✅ O18_loop_counter_peephole.md
✅ O17_redundant_flag_elimination.md
✅ O11_dual_cost_model.md
✅ O13_load_immediate_combining.md
✅ O06_lda_sta_absolute_addr.md

**Phase 2 — Quick extensions (Low complexity, builds on completed work)**:

✅ O21_lhld_shld_absolute_addr.md
✅ O23_conditional_tail_call.md
✅ O27_i16_zero_test.md
✅ O32_xchg_in_copy_phys_reg.md
✅ O33_xchg_peephole_relaxation.md
✅ O34_select_cc_zero_test.md
✅ O28_branch_threading_jmp_only.md
✅ O35_conditional_return_over_ret.md
✅ O36_redundant_lxi_after_zero_test.md
✅ O29_cross_bb_imm_propagation.md
✅ O30_conditional_return.md
✅ O31_dead_phi_constant.md
✅ O37_deferred_zero_load.md
✅ O38_xra_cmp_zero_test.md
✅ O40_add16_dad_expansion.md
✅ O41_pre_ra_inx_dcx_pseudo.md
✅ O42_liveness_aware_expansion.md
✅ O43_shld_lhld_to_push_pop.md
✅ O44_xchg_cancellation.md
✅ O49_direct_memory_alu_isel.md
✅ O51_lsr_cost_tuning.md
✅ O55_additional_peepholes.md
✅ O58_cmpzero_backward_scan.md
✅ O54_optimal_stack_adjustment.md
O54c_stack_arg_passing_push.md
O54b_per_call_frame_cleanup.md
O54d_alloca_constant_size_push.md
✅ O62_efficient_shift_expansion.md
✅ O65_mov_alu_m_fold.md
✅ O67_i8_rotate_isel_via_rlc_rrc.md
✅ O68_wide_shl_rotate_dad_h.md
✅ O69_lea_fi_pointer_use_folding.md
✅ O71_V6CLANG_LOAD16_P_redesign.md
✅ O72_V6CLANG_STORE16_P_redesign.md
✅ O73_V6CLANG_LOAD16_G_redesign.md
✅ O74_V6CLANG_STORE16_G_redesign.md
✅ O75_flag_producing_arith_sdnodes.md
✅ O76_V6CLANG_LOAD8_P_redesign.md
✅ O77_V6CLANG_STORE8_P_redesign.md
✅ O78_V6CLANG_STORE8_IMM_P_redesign.md
✅ O79_mvi_alu_reg_to_alu_imm_fold.md
✅ O80_cmp8_zero_inr_dcr.md
✅ O81_select_cc_i8_through_accumulator.md
✅ O82_mov_chain_collapse_dead_hi.md
✅ O83_pop_push_pair_elimination.md
✅ O84_inx_hl_spill_round_trip_fold.md
✅ O86_constant_shift_specialization.md
✅ O87_negate_specialization.md
✅ O88_mvi_through_mov_collapse.md
✅ O89_dead_hi_byte_bitwise_ops.md
✅ O90_pre_isel_i8_narrow_instcombine_undo.md
✅ O91_cmp8_zero_after_alu_flag_elision.md
✅ O93_bitwise16_immediate_pseudos.md
O66_switch_jump_table_pchl.md

**Phase 3 — Core optimizations (Medium complexity, high payoff)**:

✅ O39_ipra_integration.md
✅ O20_honest_store_load_defs.md
✅ O16_store_to_load_forwarding.md
✅ O24_i16_immediate_cmp.md
✅ O15_conditional_call_optimization.md
✅ O05_build_pair_add16_fusion.md
✅ O02_sequential_lxi_inx_folding.md
✅ O64_liveness_aware_i8_spill_lowering.md
✅ O70_math_header.md
O92_unified_cross_bb_reg_value_forwarding.md

**Phase 4 — Loop & stack (Medium-High complexity, massive payoff)**:

✅ O07_loop_strength_reduction.md
✅ O22_tti_cost_hooks.md
✅ O10_static_stack_allocation.md
✅ O19_inline_arithmetic_expansion.md
✅ O85_type_narrowing_iv_arithmetic_users.md

**Phase 5 — Advanced (High complexity)**:

✅ O61_spill_in_reload_immediate.md
O63_split_spill_pseudo_flags.md
✅ ../plan_asm_interop_overhaul.md

**Deferred**:

O57_shift_rotate_chaining.md

### Tooling and debugger features

- `plan_source_debug_metadata.md` - final ELF/DWARF contract, V6CLANG
	Clang/LLD enablement, artifact validation, and DAP source-to-address mapping.
- v6asm DWARF emission is packaged in `2026.07.29-6dab24c`. Mixed-language,
	relocation-name, and adapter verification are tracked in
	`plan_source_debug_metadata.md`.