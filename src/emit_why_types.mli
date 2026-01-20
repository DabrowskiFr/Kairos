(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

(** {1 Shared Emission Types} *)

type env_info = {
  node : Ast.node;
  module_name : string;
  imports : Why3.Ptree.decl list;
  type_mon_state : Why3.Ptree.decl list;
  type_state : Why3.Ptree.decl;
  type_vars : Why3.Ptree.decl;
  init_decl : Why3.Ptree.decl;
  env : Support.env;
  inputs : Why3.Ptree.binder list;
  ret_expr : Why3.Ptree.expr;
  ghost_updates : Why3.Ptree.expr;
  has_ghost_updates : bool;
  folds : Support.fold_info list;
  pre_k_map : (Ast.hexpr * Support.pre_k_info) list;
  pre_k_infos : Support.pre_k_info list;
  needs_step_count : bool;
  needs_first_step : bool;
  needs_first_step_folds : bool;
  has_initial_only_contracts : bool;
  hexpr_needs_old : Ast.hexpr -> bool;
  input_names : Ast.ident list;
  fold_init_links : (Ast.ident * Ast.ident * Ast.ident) list;
  mon_state_ctors : Ast.ident list;
  init_for_var : Ast.ident -> Ast.iexpr;
}

type contract_info = {
  pre : Why3.Ptree.term list;
  post : Why3.Ptree.term list;
  pre_labels : string list;
  post_labels : string list;
}
