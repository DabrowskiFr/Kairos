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

(** Construction of generated clauses from canonical summaries and product data.

    This module derives source-level, phase and safety clauses before
    relational lowering. *)

(** Product-step lookup helpers used by generated proof clauses. *)

open Core_syntax

(** Module [Abs]. *)

module Abs = Ir
(** Module [PT]. *)

module PT = Product_types
open Proof_kernel_types

(** [simplify_fo] helper value. *)

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

(** [same_product_state_ref] helper value. *)

let same_product_state_ref (a : Abs.product_state) (b : product_state_ir) =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

(** [same_safe_case_step] helper value. *)

let same_safe_case_step (case : Abs.safe_product_case) (step : product_step_ir) =
  step.step_kind = StepSafe
  && same_product_state_ref case.product_dst step.dst
  && simplify_fo case.admissible_guard.logic = simplify_fo step.guarantee_edge.guard

(** [same_unsafe_case_step] helper value. *)

let same_unsafe_case_step (case : Abs.unsafe_product_case) (step : product_step_ir) =
  step.step_kind = StepBadGuarantee
  && same_product_state_ref case.product_dst step.dst
  && simplify_fo case.excluded_guard.logic = simplify_fo step.guarantee_edge.guard

(** [product_transition_index_of_step] helper value. *)

let product_transition_index_of_step (step : product_step_ir) : int option =
  let raw =
    match String.starts_with ~prefix:"tr_" step.program_transition_id with
    | true -> String.sub step.program_transition_id 3 (String.length step.program_transition_id - 3)
    | false -> ""
  in
  let len = String.length raw in
  let rec first_non_digit i =
    if i >= len then len
    else
      match raw.[i] with
      | '0' .. '9' -> first_non_digit (i + 1)
      | _ -> i
  in
  let prefix_len = first_non_digit 0 in
  if prefix_len = 0 then None else int_of_string_opt (String.sub raw 0 prefix_len)

(** [product_summary_of_step] helper value. *)

let product_summary_of_step ~(node : Abs.node_ir) (step : product_step_ir) :
    Abs.product_step_summary option =
  match product_transition_index_of_step step with
  | None -> None
  | Some idx ->
      List.find_opt
        (fun (pc : Abs.product_step_summary) ->
          pc.trace.step_uid = idx
          && same_product_state_ref pc.identity.product_src step.src
          && simplify_fo pc.identity.assume_guard = simplify_fo step.assume_edge.guard
          &&
          match step.step_kind with
          | StepSafe -> List.exists (fun case -> same_safe_case_step case step) pc.safe_cases
          | StepBadGuarantee ->
              List.exists (fun case -> same_unsafe_case_step case step) pc.unsafe_cases
          | StepBadAssumption -> false)
        node.summaries

(** [build_source_summary_clauses] helper value. *)
