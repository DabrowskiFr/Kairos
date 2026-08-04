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

(** Validate pure functions after their translation to core syntax.

    This checks declaration uniqueness, names, calls and expression types. It
    also enforces the restricted logical language allowed in function
    contracts. *)

val validate_function_decls :
  Kr_domain_core.Kr_domain_core_syntax.enum_decl list -> Kr_domain_core.Kr_domain_core_syntax.pure_function_decl list -> unit
(** Validate all declarations together so calls between functions can be
    checked. Raises a typed frontend error on failure. *)
