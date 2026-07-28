(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type proof_encoding = Explicit_product

let string_of_proof_encoding = function Explicit_product -> "explicit-product"

let proof_encoding_of_string = function
  | "explicit-product" -> Some Explicit_product
  | _ -> None

let default_proof_encoding = Explicit_product

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

let string_of_contract_partition_strategy = function
  | Monolithic -> "monolithic"
  | Weak_until _ -> "weak-until"

let string_of_proof_plan_strategy = function
  | Direct -> "direct"
  | Planned _ -> "planned"

let string_of_formula_interning_strategy = function
  | Preserve_allocations -> "preserve-allocations"
  | Intern_location_free -> "intern-location-free"

let groups_public_non_w_guarantees = function
  | Monolithic -> false
  | Weak_until { public_non_w = Separate } -> false
  | Weak_until { public_non_w = Group_by_family } -> true

let groups_step_contracts = function
  | Direct -> false
  | Planned { steps = Preserve_individual; _ } -> false
  | Planned { steps = Group_safe; _ } -> true

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

let shares_lowered_formulas = function
  | Preserve_allocations -> false
  | Intern_location_free -> true

type verification_optimizations = {
  contract_partition_strategy : contract_partition_strategy;
  formula_interning_strategy : formula_interning_strategy;
  proof_plan_strategy : proof_plan_strategy;
}

type proof_optimizations = {
  verification : verification_optimizations;
}

let reference_proof_optimizations =
  {
    verification =
      {
        contract_partition_strategy = Monolithic;
        formula_interning_strategy = Preserve_allocations;
        proof_plan_strategy = Direct;
      };
  }

let default_proof_optimizations =
  {
    verification =
      {
        contract_partition_strategy =
          Weak_until { public_non_w = Group_by_family };
        formula_interning_strategy = Intern_location_free;
        proof_plan_strategy =
          Planned
            {
              steps = Group_safe;
              conditions = Deduplicate;
              formulas = Share_repeated;
              postconditions = Bundle_repeated;
            };
      };
  }

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
