(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Public Why3-side datatypes shared across emission and proof passes. *)

(* {1 Shared Emission Types} *)

(* Environment snapshot used while emitting Why3 for a node. *)
type env_info = {
  (* Runtime view used by the Why backend. *)
  runtime_view : Why_runtime_view.t;
  (* Name of the generated Why3 module. *)
  module_name : string;
  (* Extra imports required by this module. *)
  imports : Why3.Ptree.decl list;
  (* Local mirror types synthesized for callee instances. *)
  instance_type_decls : Why3.Ptree.decl list;
  (* Node state type declaration. *)
  type_state : Why3.Ptree.decl;
  (* Variable tuple type declaration. *)
  type_vars : Why3.Ptree.decl;
  (* Emission environment (names, links, pre‑k). *)
  env : Why_term_support.env;
  (* Why3 binders for inputs. *)
  inputs : Why3.Ptree.binder list;
  (* Return expression for the node. *)
  ret_expr : Why3.Ptree.expr;
  (* Mapping from pre‑k expressions to generated info. *)
  pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list;
  (* Flat list of pre‑k infos. *)
  pre_k_infos : Temporal_support.pre_k_info list;
  (* Predicate to decide whether an [old] is needed for a hexpr. *)
  hexpr_needs_old : Ast.hexpr -> bool;
  (* Input names as identifiers. *)
  input_names : Ast.ident list;
}

(* Pre/post contract payload ready for Why3 emission. *)
type step_contract_info = {
  step : Why_runtime_view.runtime_product_transition_view;
  pre : Why3.Ptree.term list;
  post : Why3.Ptree.term list;
  forbidden : Why3.Ptree.term list;
}

type contract_info = {
  (* Preconditions. *)
  pre : Why3.Ptree.term list;
  (* Postconditions. *)
  post : Why3.Ptree.term list;
  (* Labels for preconditions. *)
  pre_labels : string list;
  (* Labels for postconditions. *)
  post_labels : string list;
  (* Origin labels for preconditions. *)
  pre_origin_labels : string list;
  (* Origin labels for postconditions. *)
  post_origin_labels : string list;
  (* Optional source-state tags aligned with preconditions. *)
  pre_source_states : string option list;
  (* Optional source-state tags aligned with postconditions. *)
  post_source_states : string option list;
  (* Optional VC ids associated to postconditions. *)
  post_vcids : string option list;
  (* Kernel contracts compiled per product step. *)
  step_contracts : step_contract_info list;
}
