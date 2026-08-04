(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type proof_case_decomposition_strategy =
  Kr_verification_optimization.Proof_case_decomposition.strategy =
  | Monolithic
  | Separate_guarantees
  | Split_multiple_weak_until

type step_strategy =
  Kr_verification_optimization.Proof_plan.step_strategy =
  | Preserve_individual
  | Group_steps

type condition_strategy =
  Kr_verification_optimization.Proof_plan.condition_strategy =
  | Preserve_occurrences
  | Deduplicate

type formula_strategy =
  Kr_verification_optimization.Proof_plan.formula_strategy =
  | Inline_formulas
  | Share_repeated

type postcondition_strategy =
  Kr_verification_optimization.Proof_plan.postcondition_strategy =
  | Inline_postconditions
  | Bundle_repeated

type proof_plan_strategy =
  Kr_verification_optimization.Proof_plan.strategy =
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

let string_of_proof_case_decomposition_strategy = function
  | Monolithic -> "monolithic"
  | Separate_guarantees -> "separate"
  | Split_multiple_weak_until -> "multi-weak-until"

let string_of_proof_plan_strategy = function
  | Direct -> "direct"
  | Planned _ -> "planned"

let string_of_reachability_strategy = function
  | Trivial -> "trivial"
  | Contradiction_closure -> "contradiction-closure"

let groups_step_contracts = function
  | Direct -> false
  | Planned { steps = Preserve_individual; _ } -> false
  | Planned { steps = Group_steps; _ } -> true

let deduplicates_obligation_conditions = function
  | Direct -> false
  | Planned { conditions = Preserve_occurrences; _ } -> false
  | Planned { conditions = Deduplicate; _ } -> true

let shares_contract_formulas = function
  | Direct -> false
  | Planned { formulas = Inline_formulas; _ } -> false
  | Planned { formulas = Share_repeated; _ } -> true

let bundles_individual_postconditions = function
  | Direct -> false
  | Planned { postconditions = Inline_postconditions; _ } -> false
  | Planned { postconditions = Bundle_repeated; _ } -> true

type verification_optimizations = {
  proof_case_decomposition_strategy : proof_case_decomposition_strategy;
  reachability_strategy : reachability_strategy;
  proof_plan_strategy : proof_plan_strategy;
}

type proof_optimizations = {
  verification : verification_optimizations;
}

let reference_proof_optimizations =
  {
    verification =
      {
        proof_case_decomposition_strategy = Monolithic;
        reachability_strategy = Trivial;
        proof_plan_strategy = Direct;
      };
  }

let default_proof_optimizations =
  {
    verification =
      {
        proof_case_decomposition_strategy = Separate_guarantees;
        reachability_strategy = Contradiction_closure;
        proof_plan_strategy =
          Planned
            {
              steps = Group_steps;
              conditions = Deduplicate;
              formulas = Share_repeated;
              postconditions = Bundle_repeated;
            };
      };
  }

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
