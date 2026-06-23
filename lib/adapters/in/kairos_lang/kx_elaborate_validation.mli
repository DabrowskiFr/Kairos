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

(** Surface-language validation performed before lowering to the core AST. *)

val validate_unique_named_decls : string -> ('a -> string) -> 'a list -> unit
val validate_observers : Kx_surface_syntax.node -> unit
val validate_action_contracts : Kx_surface_syntax.node -> unit
val validate_history_def_decl : Kx_surface_syntax.history_def_decl -> unit
val validate_spec_def_decl : Kx_surface_syntax.spec_def_decl -> unit
