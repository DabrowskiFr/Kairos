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

(** Facade for semantic validation at the verification-model boundary.

    It groups validation of shared types and functions with validation of each
    translated node. *)

val lookup_constructor :
  Kr_domain_core.Kr_domain_core_syntax.enum_decl list -> Kr_domain_core.Kr_domain_core_syntax.ident -> Kr_domain_core.Kr_domain_core_syntax.ty option
(** Return the enum type that owns a constructor, if any. *)

val validate_unique_type_decls : Kr_domain_core.Kr_domain_core_syntax.enum_decl list -> unit
(** Check enum names, constructors and reserved-name constraints. *)

val validate_function_decls :
  Kr_domain_core.Kr_domain_core_syntax.enum_decl list -> Kr_domain_core.Kr_domain_core_syntax.pure_function_decl list -> unit
(** Type-check the complete set of pure-function declarations. *)

val validate_node : Kr_domain_core.Kr_domain_core_model.node_model -> unit
(** Check one translated node before it is exposed to the engine. *)
