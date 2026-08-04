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

(** Small operations shared by function and node validation.

    This module centralizes name lookup, type comparison and consistently
    classified frontend errors; it does not perform a complete validation by
    itself. *)

val fail_node : string -> string -> 'a
(** Raise a type error contextualized with the node name. *)

val lookup_constructor :
  Kr_domain_core.Core_syntax.enum_decl list -> Kr_domain_core.Core_syntax.ident -> Kr_domain_core.Core_syntax.ty option
(** Find the enum type to which a constructor belongs. *)

val validate_unique_type_decls : Kr_domain_core.Core_syntax.enum_decl list -> unit
(** Reject duplicate or invalid enum declarations and constructors. *)

val validate_identifier_collisions :
  string ->
  Kr_domain_core.Core_syntax.enum_decl list ->
  vars:Kr_domain_core.Core_syntax.vdecl list ->
  states:Kr_domain_core.Core_syntax.ident list ->
  unit
(** Reject node variables or control states that reuse constructor names. *)

val type_name : Kr_domain_core.Core_syntax.ty -> string
(** Produce the source-facing name of a type for diagnostics. *)

val same_ty : Kr_domain_core.Core_syntax.ty -> Kr_domain_core.Core_syntax.ty -> bool
(** Test exact equality of two core types. *)
