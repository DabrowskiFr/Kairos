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

val is_scalar_ref_named : string -> Surface.Syntax.indexed_ref -> bool
(** Test whether a reference is the unindexed occurrence of a given name. *)

val resolve_history_source_ref :
  Env.spec_context ->
  Surface.Syntax.indexed_ref ->
  Surface.Syntax.indexed_ref
(** Resolve natural indices and expression parameters used as the source of a
    historical operator. *)

val bind_spec_param :
  Env.spec_context ->
  Surface.Syntax.spec_param ->
  Surface.Syntax.spec_arg ->
  Env.spec_context
(** Bind one formal specification parameter to a compatible actual argument. *)

val lower_expr :
  Env.env -> Surface.Syntax.expr -> Core.Syntax.expr
(** Lower an executable surface expression and check referenced calls. *)

val infer_expr_type :
  Env.env -> Core.Syntax.expr -> Core.Syntax.ty
(** Infer the type of an already lowered executable expression. *)

val infer_hexpr_type :
  Env.env -> Core.Syntax.hexpr -> Core.Syntax.ty
(** Infer the type of an already lowered historical expression. *)

val check_expected_type :
  context:string ->
  Core.Syntax.ty ->
  Core.Syntax.ty ->
  unit
(** Reject a type mismatch with a description of the checked context. *)

val lower_hexpr :
  ?allow_old:bool ->
  Env.env ->
  Env.spec_context ->
  Core.Syntax.ident list ->
  Surface.Syntax.hexpr ->
  Core.Syntax.hexpr
(** Lower a historical expression, expanding predicates and history aliases.
    [allow_old] controls whether method-contract [old] expressions are legal. *)

val lower_ltl :
  Env.env ->
  Env.spec_context ->
  Surface.Syntax.ltl ->
  Core.Syntax.ltl
(** Lower one temporal formula, expanding specification calls and finite
    quantifiers. *)

val lower_contract_ltls :
  Env.env -> Surface.Syntax.ltl -> Core.Syntax.ltl list
(** Lower a contract and split its top-level conjunctions and universal
    expansions into separate formulas. *)
