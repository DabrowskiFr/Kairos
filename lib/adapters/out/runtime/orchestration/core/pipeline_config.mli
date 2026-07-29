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

type proof_case_decomposition_strategy =
  Kairos_verification_optimization.Proof_case_decomposition.strategy =
  | Monolithic
  | Separate_guarantees
  | Split_multiple_weak_until

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

type reachability_strategy =
  Product_reachability.strategy =
  | Trivial
  | Contradiction_closure

val string_of_proof_case_decomposition_strategy :
  proof_case_decomposition_strategy -> string

val string_of_proof_plan_strategy : proof_plan_strategy -> string

val string_of_reachability_strategy : reachability_strategy -> string

val groups_step_contracts : proof_plan_strategy -> bool
val deduplicates_obligation_conditions : proof_plan_strategy -> bool
val shares_contract_formulas : proof_plan_strategy -> bool
val bundles_individual_postconditions : proof_plan_strategy -> bool

type verification_optimizations = {
  proof_case_decomposition_strategy : proof_case_decomposition_strategy;
  reachability_strategy : reachability_strategy;
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
  proof_optimizations : proof_optimizations;
}
