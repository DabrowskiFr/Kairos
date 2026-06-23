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

(** Naming conventions introduced by surface elaboration.

    The parser preserves indexed surface references. Elaboration flattens them
    into core identifiers, and generated histories use the same convention.
*)

val indexed_ident_many : string -> string list -> string
val indexed_ref_name : Kx_surface_syntax.indexed_ref -> string
val same_indexed_ref : Kx_surface_syntax.indexed_ref -> Kx_surface_syntax.indexed_ref -> bool
val generated_history_prefix : string
val generated_history_name : string -> Kx_surface_syntax.indexed_ref -> string
