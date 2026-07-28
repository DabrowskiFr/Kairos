(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Proof-generation policy and runtime execution configuration. *)

type proof_encoding = Explicit_product

val string_of_proof_encoding : proof_encoding -> string
val proof_encoding_of_string : string -> proof_encoding option
val default_proof_encoding : proof_encoding

type contract_partition_strategy =
  Kairos_verification_optimization.Contract_partition.strategy =
  | Monolithic
  | Weak_until of {
      public_non_w : public_non_w_strategy;
    }

and public_non_w_strategy =
  Kairos_verification_optimization.Contract_partition.public_non_w_strategy =
  | Separate
  | Group_by_family

type step_strategy =
  Kairos_verification_optimization.Proof_plan.step_strategy =
  | Preserve_individual
  | Group_safe

type condition_strategy =
  Kairos_verification_optimization.Proof_plan.condition_strategy =
  | Preserve_occurrences
  | Deduplicate

type formula_strategy =
  Kairos_verification_optimization.Proof_plan.formula_strategy =
  | Inline_formulas
  | Share_repeated

type postcondition_strategy =
  Kairos_verification_optimization.Proof_plan.postcondition_strategy =
  | Inline_postconditions
  | Bundle_repeated

type proof_plan_strategy =
  Kairos_verification_optimization.Proof_plan.strategy =
  | Direct
  | Planned of {
      steps : step_strategy;
      conditions : condition_strategy;
      formulas : formula_strategy;
      postconditions : postcondition_strategy;
    }

type formula_interning_strategy =
  Kairos_verification_optimization.Formula_interning.strategy =
  | Preserve_allocations
  | Intern_location_free

val string_of_contract_partition_strategy :
  contract_partition_strategy -> string

val string_of_proof_plan_strategy : proof_plan_strategy -> string

val string_of_formula_interning_strategy :
  formula_interning_strategy ->
  string

val groups_public_non_w_guarantees :
  contract_partition_strategy -> bool

val groups_step_contracts : proof_plan_strategy -> bool
val deduplicates_obligation_conditions : proof_plan_strategy -> bool
val shares_contract_formulas : proof_plan_strategy -> bool
val bundles_individual_postconditions : proof_plan_strategy -> bool
val shares_lowered_formulas : formula_interning_strategy -> bool

type verification_optimizations = {
  contract_partition_strategy : contract_partition_strategy;
  formula_interning_strategy : formula_interning_strategy;
  proof_plan_strategy : proof_plan_strategy;
}

type proof_optimizations = {
  verification : verification_optimizations;
}

val reference_proof_optimizations : proof_optimizations
val default_proof_optimizations : proof_optimizations

type config = {
  input_file : string;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  compute_proof_diagnostics : bool;
  prove : bool;
  proof_jobs : int;
  generate_why_text : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_dot_png : bool;
  dump_failed_smt : bool;
  collect_ir_metrics : bool;
  proof_progress_path : string option;
  stop_on_first_nonvalid : bool;
  proof_encoding : proof_encoding;
  proof_optimizations : proof_optimizations;
}
