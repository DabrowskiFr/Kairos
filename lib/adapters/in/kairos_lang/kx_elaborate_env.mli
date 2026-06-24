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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Shared environment and small expansion helpers for surface elaboration. *)

type env = {
  enum_sets : (Kx_core_syntax.ident * Kx_core_syntax.ident list) list;
  functions :
    (Kx_core_syntax.ident * (Kx_core_syntax.vdecl list * Kx_core_syntax.ty)) list;
  spec_defs : (Kx_core_syntax.ident * Kx_surface_syntax.spec_def_decl) list;
  history_defs :
    (Kx_core_syntax.ident * Kx_surface_syntax.history_def_decl) list;
  predicates : (Kx_core_syntax.ident * Kx_surface_syntax.predicate_decl) list;
  actions : (Kx_core_syntax.ident * Kx_surface_syntax.action_decl) list;
  history_aliases : (Kx_core_syntax.ident * (Kx_core_syntax.ident * int)) list;
}

val empty_env : env

type spec_context = {
  formula_params : (Kx_core_syntax.ident * Kx_surface_syntax.ltl) list;
  hexpr_params : (Kx_core_syntax.ident * Kx_surface_syntax.hexpr) list;
  nat_params : (Kx_core_syntax.ident * int) list;
  spec_stack : Kx_core_syntax.ident list;
}

val empty_spec_context : spec_context
val add_enum_set : env -> Kx_core_syntax.ident -> Kx_core_syntax.ident list -> env
val enum_members : env -> Kx_core_syntax.ident -> Kx_core_syntax.ident list
val expand_enum_or_single : env -> Kx_core_syntax.ident -> Kx_core_syntax.ident list
val expand_index_choices : env -> Kx_core_syntax.ident list list -> Kx_core_syntax.ident list list
val lower_raw_vdecl : env -> Kx_surface_syntax.raw_vdecl -> Kx_core_syntax.vdecl list
val lower_raw_vdecls : env -> Kx_surface_syntax.raw_vdecl list -> Kx_core_syntax.vdecl list
val range_values : int -> int -> int list
val eval_nat : spec_context -> Kx_surface_syntax.nat_expr -> int
val function_sig : env -> Kx_core_syntax.ident -> (Kx_core_syntax.vdecl list * Kx_core_syntax.ty) option
val is_bool_function : env -> Kx_core_syntax.ident -> bool
