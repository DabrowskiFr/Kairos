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

(** Low-level translation of exported kernel clauses into Why3 contracts. *)

(* {1 Contract Assembly} Translate node contracts (assumes/guarantees and transition
   requires/ensures) into Why3 pre/post terms with labels for UI/VC tracing. *)

(* {1 Contract Assembly} *)

type step_contract_info = {
  step : Why_runtime_view.runtime_product_transition_view;
  pre : Why3.Ptree.term list;
  post : Why3.Ptree.term list;
  forbidden : Why3.Ptree.term list;
}

type contract_info = {
  pre : Why3.Ptree.term list;
  post : Why3.Ptree.term list;
  pre_labels : string list;
  post_labels : string list;
  pre_origin_labels : string list;
  post_origin_labels : string list;
  pre_source_states : string option list;
  post_source_states : string option list;
  post_vcids : string option list;
  step_contracts : step_contract_info list;
}

val set_pure_translation : bool -> unit
val get_pure_translation : unit -> bool
(* Enable/disable pure translation mode (no extra contract generation). *)

val build_contracts :
  nodes:Ast.node list ->
  env:Why_term_support.env ->
  hexpr_needs_old:(Ast.hexpr -> bool) ->
  runtime:Why_runtime_view.t ->
  contract_info
(* Build full contract terms (pre/post) and their labels for a runtime view. *)
