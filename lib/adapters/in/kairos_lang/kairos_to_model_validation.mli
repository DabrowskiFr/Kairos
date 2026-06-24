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

(** Semantic validation for the elaborated Kairos model. *)

val lookup_constructor :
  Core_syntax.enum_decl list -> Core_syntax.ident -> Core_syntax.ty option

val validate_unique_type_decls : Core_syntax.enum_decl list -> unit

val validate_function_decls :
  Core_syntax.enum_decl list -> Core_syntax.pure_function_decl list -> unit

val validate_node : Verification_model.node_model -> unit
