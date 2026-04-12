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

(** Reactive program and explicit/fallback product construction for the kernel IR. *)
open Core_syntax
(** Module [Abs]. *)

module Abs = Ir
(** Module [PT]. *)

module PT = Product_types

(** [build_reactive_program] service entrypoint. *)

val build_reactive_program :
  node_name:ident ->
  source_node:Ast.node ->
  program_transitions:Abs.transition list ->
  Proof_kernel_types.reactive_program_ir

(** [build_automaton] service entrypoint. *)

val build_automaton :
  role:Proof_kernel_types.automaton_role ->
  labels:string list ->
  bad_idx:int ->
  grouped_edges:PT.automaton_edge list ->
  atom_map_exprs:(ident * expr) list ->
  automaton_guard_fo:((ident * expr) list -> Automaton_types.guard -> Core_syntax.hexpr) ->
  Proof_kernel_types.safety_automaton_ir

(** [is_feasible_product_step] service entrypoint. *)

val is_feasible_product_step :
  node:Abs.node_ir ->
  analysis:Temporal_automata.node_data ->
  Proof_kernel_types.product_step_ir ->
  bool

(** [build_product_step] service entrypoint. *)

val build_product_step :
  reactive_program:Proof_kernel_types.reactive_program_ir ->
  PT.product_step ->
  Proof_kernel_types.product_step_ir

(** [synthesize_fallback_product_steps] service entrypoint. *)

val synthesize_fallback_product_steps :
  program_transitions:Abs.transition list ->
  node:Abs.node_ir ->
  analysis:Temporal_automata.node_data ->
  reactive_program:Proof_kernel_types.reactive_program_ir ->
  live_states:PT.product_state list ->
  automaton_guard_fo:((ident * expr) list -> Automaton_types.guard -> Core_syntax.hexpr) ->
  product_state_of_pt:(PT.product_state -> Proof_kernel_types.product_state_ir) ->
  product_step_kind_of_pt:(PT.step_class -> Proof_kernel_types.product_step_kind) ->
  is_live_state:(analysis:Temporal_automata.node_data -> PT.product_state -> bool) ->
  Proof_kernel_types.product_step_ir list
