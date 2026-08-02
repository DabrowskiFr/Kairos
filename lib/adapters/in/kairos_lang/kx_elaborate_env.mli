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
  enum_sets : (Kx_core_syntax.ident * Kx_core_syntax.ident list) list;
      (** Enum names and their constructors. *)
  variables : (Kx_core_syntax.ident * Kx_core_syntax.ty) list;
      (** Visible variables and their types. *)
  functions :
    (Kx_core_syntax.ident * (Kx_core_syntax.vdecl list * Kx_core_syntax.ty)) list;
      (** Pure-function parameter and result types. *)
  spec_defs : (Kx_core_syntax.ident * Kx_surface_ast.spec_def_decl) list;
      (** Reusable temporal specification definitions. *)
  predicates : (Kx_core_syntax.ident * Kx_surface_ast.predicate_decl) list;
      (** Reusable first-order predicates. *)
  methods : (Kx_core_syntax.ident * Kx_surface_ast.method_decl) list;
      (** Methods available to executable statements. *)
  history_aliases : (Kx_core_syntax.ident * (Kx_core_syntax.ident * int)) list;
      (** Named aliases for a variable at a fixed past offset. *)
}

val empty_env : env
(** Environment containing no declarations. *)

type spec_context = {
  formula_params : (Kx_core_syntax.ident * Kx_surface_syntax.ltl) list;
      (** Temporal-formula parameters bound to their actual arguments. *)
  hexpr_params : (Kx_core_syntax.ident * Kx_surface_syntax.hexpr) list;
      (** Historical-expression parameters bound to their actual arguments. *)
  nat_params : (Kx_core_syntax.ident * int) list;
      (** Natural-number parameters bound during finite expansion. *)
  spec_stack : Kx_core_syntax.ident list;
      (** Active specification expansions, used to detect recursion. *)
}

val empty_spec_context : spec_context
(** Specification context with no bound parameters. *)

val add_enum_set : env -> Kx_core_syntax.ident -> Kx_core_syntax.ident list -> env
(** Add a non-empty enum declaration, rejecting duplicate names. *)

val enum_members : env -> Kx_core_syntax.ident -> Kx_core_syntax.ident list
(** Resolve an enum name or raise an elaboration error. *)

val expand_enum_or_single : env -> Kx_core_syntax.ident -> Kx_core_syntax.ident list
(** Expand an enum name to its constructors, or keep an ordinary index as a
    singleton. *)

val expand_index_choices : env -> Kx_core_syntax.ident list list -> Kx_core_syntax.ident list list
(** Expand indexed declaration dimensions into their Cartesian combinations. *)

val lower_raw_vdecl : env -> Kx_surface_syntax.raw_vdecl -> Kx_core_syntax.vdecl list
(** Flatten one possibly indexed surface declaration into scalar declarations. *)

val lower_raw_vdecls : env -> Kx_surface_syntax.raw_vdecl list -> Kx_core_syntax.vdecl list
(** Flatten a list of possibly indexed surface declarations. *)

val range_values : int -> int -> int list
(** Enumerate an inclusive integer range; an inverted range is empty. *)

val eval_nat : spec_context -> Kx_surface_syntax.nat_expr -> int
(** Evaluate a natural literal or a bound natural parameter. *)

val function_sig : env -> Kx_core_syntax.ident -> (Kx_core_syntax.vdecl list * Kx_core_syntax.ty) option
(** Look up a pure function's parameter and result types. *)

val is_bool_function : env -> Kx_core_syntax.ident -> bool
(** Test whether a declared pure function returns [bool]. *)

val value_type : env -> Kx_core_syntax.ident -> Kx_core_syntax.ty option
(** Resolve the type of a variable or enum constructor. *)

val type_name : Kx_core_syntax.ty -> string
(** Produce a source-facing type name for diagnostics. *)

val validate_type : env -> string -> Kx_core_syntax.ty -> unit
(** Check that a custom type exists, using the supplied context in errors. *)
