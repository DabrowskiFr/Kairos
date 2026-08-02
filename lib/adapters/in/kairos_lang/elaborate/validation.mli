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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Well-formedness checks that require the structure of the surface language.

    These checks run before lowering because distinctions such as observers,
    methods, selectors and loop variants no longer exist explicitly in the core
    AST. *)

val validate_unique_named_decls : string -> ('a -> string) -> 'a list -> unit
(** Reject duplicate names in one declaration family. *)

val validate_control_graph : Surface.Ast.node -> unit
(** Check control states, the initial state and transition endpoints. *)

val validate_observers : Surface.Ast.node -> unit
(** Check observer assignments, dependencies and restrictions on [pre]. *)

val validate_method_contracts : Surface.Ast.node -> unit
(** Check the syntactic restrictions of method pre- and postconditions. *)

val validate_method_parameters : Surface.Ast.node -> unit
(** Check method parameter declarations and their permitted uses. *)

val validate_method_call_graph : Surface.Ast.node -> unit
(** Reject recursive cycles between methods. *)

val validate_while_variants : Surface.Ast.node -> unit
(** Require and validate termination variants where the language demands them. *)

val validate_spec_def_decl : Surface.Ast.spec_def_decl -> unit
(** Check one reusable specification definition before it can be expanded. *)
