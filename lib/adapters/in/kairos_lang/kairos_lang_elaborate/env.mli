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

(** Name and type information accumulated while elaborating surface syntax.

    The environment resolves declarations visible in a source file, while a
    specification context records parameters bound during one nested
    specification expansion. *)

type env = {
  enum_sets : (Core.Syntax.ident * Core.Syntax.ident list) list;
      (** Enum names and their constructors. *)
  variables : (Core.Syntax.ident * Core.Syntax.ty) list;
      (** Visible variables and their types. *)
  functions :
    (Core.Syntax.ident * (Core.Syntax.vdecl list * Core.Syntax.ty)) list;
      (** Pure-function parameter and result types. *)
  spec_defs : (Core.Syntax.ident * Surface.Ast.spec_def_decl) list;
      (** Reusable temporal specification definitions. *)
  predicates : (Core.Syntax.ident * Surface.Ast.predicate_decl) list;
      (** Reusable first-order predicates. *)
  methods : (Core.Syntax.ident * Surface.Ast.method_decl) list;
      (** Methods available to executable statements. *)
  history_aliases : (Core.Syntax.ident * (Core.Syntax.ident * int)) list;
      (** Named aliases for a variable at a fixed past offset. *)
}

val empty_env : env
(** Environment containing no declarations. *)

type spec_context = {
  formula_params : (Core.Syntax.ident * Surface.Syntax.ltl) list;
      (** Temporal-formula parameters bound to their actual arguments. *)
  hexpr_params : (Core.Syntax.ident * Surface.Syntax.hexpr) list;
      (** Historical-expression parameters bound to their actual arguments. *)
  nat_params : (Core.Syntax.ident * int) list;
      (** Natural-number parameters bound during finite expansion. *)
  spec_stack : Core.Syntax.ident list;
      (** Active specification expansions, used to detect recursion. *)
}

val empty_spec_context : spec_context
(** Specification context with no bound parameters. *)

val add_enum_decl : env -> Core.Syntax.ident -> Core.Syntax.ident list -> env
(** Add a non-empty enum declaration, rejecting duplicate names. *)

val add_function :
  env -> Core.Syntax.ident ->
  (Core.Syntax.vdecl list * Core.Syntax.ty) -> env
(** Add a pure function signature, rejecting duplicate names. *)

val add_spec_def :
  env -> Core.Syntax.ident -> Surface.Ast.spec_def_decl -> env
(** Add a specification definition, rejecting duplicate names. *)

val enum_members : env -> Core.Syntax.ident -> Core.Syntax.ident list
(** Resolve an enum name or raise an elaboration error. *)

val expand_enum_or_single : env -> Core.Syntax.ident -> Core.Syntax.ident list
(** Expand an enum name to its constructors, or keep an ordinary index as a
    singleton. *)

val expand_index_choices : env -> Core.Syntax.ident list list -> Core.Syntax.ident list list
(** Expand indexed declaration dimensions into their Cartesian combinations. *)

val lower_raw_vdecl : env -> Surface.Syntax.raw_vdecl -> Core.Syntax.vdecl list
(** Flatten one possibly indexed surface declaration into scalar declarations. *)

val lower_raw_vdecls : env -> Surface.Syntax.raw_vdecl list -> Core.Syntax.vdecl list
(** Flatten a list of possibly indexed surface declarations. *)

val range_values : int -> int -> int list
(** Enumerate an inclusive integer range; an inverted range is empty. *)

val eval_nat : spec_context -> Surface.Syntax.nat_expr -> int
(** Evaluate a natural literal or a bound natural parameter. *)

val function_sig : env -> Core.Syntax.ident -> (Core.Syntax.vdecl list * Core.Syntax.ty) option
(** Look up a pure function's parameter and result types. *)

val is_bool_function : env -> Core.Syntax.ident -> bool
(** Test whether a declared pure function returns [bool]. *)

val value_type : env -> Core.Syntax.ident -> Core.Syntax.ty option
(** Resolve the type of a variable or enum constructor. *)

val type_name : Core.Syntax.ty -> string
(** Produce a source-facing type name for diagnostics. *)

val validate_type : env -> string -> Core.Syntax.ty -> unit
(** Check that a custom type exists, using the supplied context in errors. *)
