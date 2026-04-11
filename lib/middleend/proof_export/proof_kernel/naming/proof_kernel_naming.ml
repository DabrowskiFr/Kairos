(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)
open Core_syntax
open Ast
open Logic_pretty
open Proof_kernel_types

let phase_state_case_name ~(prog_state : ident) ~(guarantee_state : int) : string =
  Printf.sprintf "phase_case_%s_g%d" (String.lowercase_ascii prog_state) guarantee_state

let phase_step_case_stem (step : product_step_ir) : string =
  Printf.sprintf "%s_to_%s_a%d_%d_g%d_%d"
    (String.lowercase_ascii step.src.prog_state)
    (String.lowercase_ascii step.dst.prog_state)
    step.src.assume_state_index step.dst.assume_state_index
    step.src.guarantee_state_index step.dst.guarantee_state_index

let phase_step_pre_case_name (step : product_step_ir) : string =
  "phase_pre_" ^ phase_step_case_stem step

let phase_step_post_case_name (step : product_step_ir) : string =
  "phase_post_" ^ phase_step_case_stem step

let string_of_role = function Assume -> "assume" | Guarantee -> "guarantee"

let string_of_step_kind = function
  | StepSafe -> "safe"
  | StepBadAssumption -> "bad_assumption"
  | StepBadGuarantee -> "bad_guarantee"

let string_of_step_origin = function
  | StepFromExplicitExploration -> "explicit"
  | StepFromFallbackSynthesis -> "fallback"

let string_of_product_coverage = function
  | CoverageEmpty -> "empty"
  | CoverageExplicit -> "explicit"
  | CoverageFallback -> "fallback"

let string_of_clause_origin = function
  | OriginSourceProductSummary -> "source/product_summary"
  | OriginPhaseStepPreSummary -> "phase/step_pre_summary"
  | OriginPhaseStepSummary -> "phase/step_summary"
  | OriginSafety -> "safety"
  | OriginInitNodeInvariant -> "init/node_inv"
  | OriginInitAutomatonCoherence -> "init/automaton"
  | OriginPropagationNodeInvariant -> "propagation/node_inv"
  | OriginPropagationAutomatonCoherence -> "propagation/automaton"

let string_of_clause_time = function
  | CurrentTick -> "current"
  | PreviousTick -> "previous"
  | StepTickContext -> "step_ctx"

let string_of_clause_fact_desc = function
  | FactProgramState st -> "st = " ^ st
  | FactGuaranteeState idx -> "guarantee_state = " ^ string_of_int idx
  | FactPhaseFormula f -> "phase(" ^ string_of_fo f ^ ")"
  | FactFormula f -> string_of_fo f
  | FactFalse -> "false"

let string_of_relational_clause_fact_desc = function
  | RelFactProgramState st -> "st = " ^ st
  | RelFactGuaranteeState idx -> "guarantee_state = " ^ string_of_int idx
  | RelFactPhaseFormula f -> "phase(" ^ string_of_fo f ^ ")"
  | RelFactFormula f -> string_of_fo f
  | RelFactFalse -> "false"

let string_of_clause_fact (fact : clause_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_clause_time fact.time) (string_of_clause_fact_desc fact.desc)

let string_of_relational_clause_fact (fact : relational_clause_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_clause_time fact.time)
    (string_of_relational_clause_fact_desc fact.desc)

let string_of_product_state (st : product_state_ir) =
  Printf.sprintf "(P=%s, A=%d, G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let string_of_edge (edge : automaton_edge_ir) =
  Printf.sprintf "%d->%d if %s" edge.src_index edge.dst_index (string_of_fo edge.guard)
