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

(** Shared semantic-validation helpers for the elaborated Kairos model. *)

val fail_node : string -> string -> 'a

val lookup_constructor :
  Core_syntax.enum_decl list -> Core_syntax.ident -> Core_syntax.ty option

val validate_unique_type_decls : Core_syntax.enum_decl list -> unit

val validate_identifier_collisions :
  string ->
  Core_syntax.enum_decl list ->
  vars:Core_syntax.vdecl list ->
  states:Core_syntax.ident list ->
  unit

val type_name : Core_syntax.ty -> string

val same_ty : Core_syntax.ty -> Core_syntax.ty -> bool
