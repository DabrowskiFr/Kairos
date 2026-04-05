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
open Generated_names
open Temporal_support
open Ast_pretty
module Naming = Proof_kernel_naming

let render_reactive_program (p : Proof_kernel_types.reactive_program_ir) : string list =
  let header =
    Printf.sprintf "reactive_program %s init=%s states=%d transitions=%d" p.node_name p.init_state
      (List.length p.states) (List.length p.transitions)
  in
  let states = List.map (fun st -> Printf.sprintf "  state %s" st) p.states in
  let transitions =
    List.map
      (fun (t : Proof_kernel_types.reactive_transition_ir) ->
        Printf.sprintf "  trans %s -> %s guard=%s" t.src_state t.dst_state (string_of_fo t.guard))
      p.transitions
  in
  header :: (states @ transitions)

let render_automaton (a : Proof_kernel_types.safety_automaton_ir) : string list =
  let bad =
    match a.bad_state_index with None -> "none" | Some idx -> string_of_int idx
  in
  let header =
    Printf.sprintf "%s_automaton init=%d bad=%s states=%d edges=%d" (Naming.string_of_role a.role)
      a.initial_state_index bad (List.length a.state_labels) (List.length a.edges)
  in
  let states =
    List.map (fun (idx, lbl) -> Printf.sprintf "  state %d = %s" idx lbl) a.state_labels
  in
  let edges = List.map (fun edge -> "  edge " ^ Naming.string_of_edge edge) a.edges in
  header :: (states @ edges)

let render_generated_clause kind (clause : Proof_kernel_types.generated_clause_ir) : string =
  let subject =
    match clause.anchor with
    | Proof_kernel_types.ClauseAnchorProductState st -> Naming.string_of_product_state st
    | Proof_kernel_types.ClauseAnchorProductStep step ->
        Printf.sprintf "%s -> %s" (Naming.string_of_product_state step.src)
          (Naming.string_of_product_state step.dst)
  in
  let hyps = String.concat ", " (List.map Naming.string_of_clause_fact clause.hypotheses) in
  let concls = String.concat ", " (List.map Naming.string_of_clause_fact clause.conclusions) in
  Printf.sprintf "  %s %s on %s if [%s] then [%s]" kind
    (Naming.string_of_clause_origin clause.origin) subject hyps concls

let render_historical_clauses (ir : Proof_kernel_types.node_ir) : string list =
  List.map (render_generated_clause "historical_clause") ir.historical_generated_clauses

let render_eliminated_clauses (ir : Proof_kernel_types.node_ir) : string list =
  List.map (render_generated_clause "eliminated_clause") ir.eliminated_generated_clauses

let render_product (ir : Proof_kernel_types.node_ir) : string list =
  let header =
    Printf.sprintf "explicit_product initial=%s states=%d steps=%d historical=%d eliminated=%d symbolic=%d"
      (Naming.string_of_product_state ir.initial_product_state) (List.length ir.product_states)
      (List.length ir.product_steps) (List.length ir.historical_generated_clauses)
      (List.length ir.eliminated_generated_clauses)
      (List.length ir.symbolic_generated_clauses)
  in
  let coverage = Printf.sprintf "  coverage %s" (Naming.string_of_product_coverage ir.product_coverage) in
  let states = List.map (fun st -> "  pstate " ^ Naming.string_of_product_state st) ir.product_states in
  let steps =
    List.map
      (fun (step : Proof_kernel_types.product_step_ir) ->
        Printf.sprintf
          "  pstep %s -- %s->%s / A[%d->%d] / G[%d->%d] --> %s [%s/%s]"
          (Naming.string_of_product_state step.src) (fst step.program_transition)
          (snd step.program_transition) step.assume_edge.src_index step.assume_edge.dst_index
          step.guarantee_edge.src_index step.guarantee_edge.dst_index
          (Naming.string_of_product_state step.dst) (Naming.string_of_step_kind step.step_kind)
          (Naming.string_of_step_origin step.step_origin))
      ir.product_steps
  in
  let historical_clauses = render_historical_clauses ir in
  let eliminated_clauses = render_eliminated_clauses ir in
  let symbolic_clauses =
    List.map
      (fun (clause : Proof_kernel_types.relational_generated_clause_ir) ->
        let subject =
          match clause.anchor with
          | Proof_kernel_types.ClauseAnchorProductState st -> Naming.string_of_product_state st
          | Proof_kernel_types.ClauseAnchorProductStep step ->
              Printf.sprintf "%s -> %s" (Naming.string_of_product_state step.src)
                (Naming.string_of_product_state step.dst)
        in
        let hyps = String.concat ", " (List.map Naming.string_of_relational_clause_fact clause.hypotheses) in
        let concls = String.concat ", " (List.map Naming.string_of_relational_clause_fact clause.conclusions) in
        Printf.sprintf "  symbolic_clause %s on %s if [%s] then [%s]"
          (Naming.string_of_clause_origin clause.origin) subject hyps concls)
      ir.symbolic_generated_clauses
  in
  header
  :: (coverage
     :: (states @ steps @ historical_clauses @ eliminated_clauses @ symbolic_clauses))

let render_node_ir (ir : Proof_kernel_types.node_ir) : string list =
  [ "-- Kernel-compatible pipeline IR --" ]
  @ render_reactive_program ir.reactive_program
  @ render_automaton ir.assume_automaton
  @ render_automaton ir.guarantee_automaton
  @ render_product ir
