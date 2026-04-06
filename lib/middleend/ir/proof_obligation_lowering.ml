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

open Ast

let unique_pre_k_infos (pre_k_map : (hexpr * Temporal_support.pre_k_info) list) : Temporal_support.pre_k_info list =
  pre_k_map
  |> List.fold_left
       (fun acc (_, info) ->
         if List.exists (fun existing -> existing.Temporal_support.names = info.Temporal_support.names) acc then
           acc
         else acc @ [ info ])
       []

(** {2 Pre-k locals}

    Compute the [__pre_k{k}_x] vdecls that must be added to the node locals.
    Replicates [Proof_kernel_types.pre_k_locals_of_ast] but works directly from
    the [pre_k_map] stored in the [raw_node] (avoids a round-trip through the
    AST). *)
let pre_k_extra_locals ~(existing_names : ident list)
    (pre_k_map : (hexpr * Temporal_support.pre_k_info) list) : vdecl list =
  unique_pre_k_infos pre_k_map
  |> List.concat_map (fun info ->
         List.filter_map
           (fun name ->
             if List.mem name existing_names then None
             else Some { vname = name; vty = info.Temporal_support.vty })
           info.Temporal_support.names)

(** {2 Formula substitution}

    Substitute [HPreK(x, k)] → [HNow (IVar "__pre_k{k}_x")] in an [ltl_o].
    Uses [Fo_specs.lower_fo_pre_k] which returns [None] when a [HPreK] is not
    found in the map; in that case we keep the formula verbatim. *)
let lower_fo_o (pre_k_map : (hexpr * Temporal_support.pre_k_info) list)
    (f : Ir.summary_formula) : Ir.summary_formula =
  let rec lower_formula (formula : Fo_formula.t) : Fo_formula.t option =
    match formula with
    | Fo_formula.FTrue | Fo_formula.FFalse -> Some formula
    | Fo_formula.FAtom atom ->
        Fo_specs.lower_fo_pre_k ~pre_k_map atom |> Option.map (fun atom' -> Fo_formula.FAtom atom')
    | Fo_formula.FNot a -> lower_formula a |> Option.map (fun a' -> Fo_formula.FNot a')
    | Fo_formula.FAnd (a, b) -> begin
        match (lower_formula a, lower_formula b) with
        | Some a', Some b' -> Some (Fo_formula.FAnd (a', b'))
        | _ -> None
      end
    | Fo_formula.FOr (a, b) -> begin
        match (lower_formula a, lower_formula b) with
        | Some a', Some b' -> Some (Fo_formula.FOr (a', b'))
        | _ -> None
      end
    | Fo_formula.FImp (a, b) -> begin
        match (lower_formula a, lower_formula b) with
        | Some a', Some b' -> Some (Fo_formula.FImp (a', b'))
        | _ -> None
      end
  in
  match lower_formula f.logic with Some logic -> { f with logic } | None -> f

let lower_product_transition ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list)
    (pc : Ir.product_step_summary) : Ir.product_step_summary =
  let lower = lower_fo_o pre_k_map in
  {
    pc with
    requires = List.map lower pc.requires;
    ensures = List.map lower pc.ensures;
    safe_cases =
      List.map
        (fun (c : Ir.safe_product_case) ->
          {
            c with
            admissible_guard = lower c.admissible_guard;
          })
        pc.safe_cases;
    unsafe_cases =
      List.map
        (fun (c : Ir.unsafe_product_case) ->
          {
            c with
            excluded_guard = lower c.excluded_guard;
          })
        pc.unsafe_cases;
  }

(** {2 Main pass} *)

let eliminate (annotated : Ir_proof_views.annotated_node) : Ir_proof_views.verified_node =
  let raw = annotated.raw in
  let pre_k_map = raw.pre_k_map in
  let existing_names = List.map (fun (v : vdecl) -> v.vname) raw.core.locals in
  let extra_locals = pre_k_extra_locals ~existing_names pre_k_map in
  let lower = lower_fo_o pre_k_map in
  let transitions =
    List.map
      (fun (t : Ir_proof_views.annotated_transition) ->
        ({
          Ir_proof_views.core = t.raw.core;
          guard = t.raw.guard;
          clauses =
            {
              requires = List.map lower t.clauses.requires;
              ensures = List.map lower t.clauses.ensures;
            };
        } : Ir_proof_views.verified_transition))
      annotated.transitions
  in
  {
    Ir_proof_views.core = { raw.core with locals = raw.core.locals @ extra_locals };
    transitions;
    product_transitions = [];
    assumes = raw.assumes;
    guarantees = raw.guarantees;
    init_invariant_goals = List.map lower annotated.init_invariant_goals;
    user_invariants = annotated.user_invariants;
  }

let apply_node (node : Ir.node_ir) : Ir.node_ir =
  {
    node with
    summaries = List.map (lower_product_transition ~pre_k_map:node.context.pre_k_map) node.summaries;
  }

let apply_program (program : Ir.node_ir list) : Ir.node_ir list = List.map apply_node program
