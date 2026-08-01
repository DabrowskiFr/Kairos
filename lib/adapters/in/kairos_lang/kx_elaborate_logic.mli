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

(** Lowering of surface expressions, historical expressions, and LTL formulas.

    This module expands predicates/spec definitions and lowers formula syntax.
    It intentionally does not build nodes, transitions, observers, or generated
    history ghosts. *)

val is_scalar_ref_named : string -> Kx_surface_syntax.indexed_ref -> bool

val resolve_history_source_ref :
  Kx_elaborate_env.spec_context ->
  Kx_surface_syntax.indexed_ref ->
  Kx_surface_syntax.indexed_ref

val bind_spec_param :
  Kx_elaborate_env.spec_context ->
  Kx_surface_syntax.spec_param ->
  Kx_surface_syntax.spec_arg ->
  Kx_elaborate_env.spec_context

val lower_expr :
  Kx_elaborate_env.env -> Kx_surface_syntax.expr -> Kx_core_syntax.expr

val infer_expr_type :
  Kx_elaborate_env.env -> Kx_core_syntax.expr -> Kx_core_syntax.ty

val infer_hexpr_type :
  Kx_elaborate_env.env -> Kx_core_syntax.hexpr -> Kx_core_syntax.ty

val check_expected_type :
  context:string ->
  Kx_core_syntax.ty ->
  Kx_core_syntax.ty ->
  unit

val lower_hexpr :
  ?allow_old:bool ->
  Kx_elaborate_env.env ->
  Kx_elaborate_env.spec_context ->
  Kx_core_syntax.ident list ->
  Kx_surface_syntax.hexpr ->
  Kx_core_syntax.hexpr

val lower_ltl :
  Kx_elaborate_env.env ->
  Kx_elaborate_env.spec_context ->
  Kx_surface_syntax.ltl ->
  Kx_core_syntax.ltl

val lower_contract_ltls :
  Kx_elaborate_env.env -> Kx_surface_syntax.ltl -> Kx_core_syntax.ltl list
