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
(** Flatten a base name and several indices into one core identifier. *)

val indexed_ref_name : Surface.Syntax.indexed_ref -> string
(** Return the flattened core name of a surface reference. *)

val same_indexed_ref : Surface.Syntax.indexed_ref -> Surface.Syntax.indexed_ref -> bool
(** Compare two references after applying the flattening convention. *)

val generated_delay_name : Surface.Syntax.indexed_ref -> string
(** Produce the reserved private name used to store [pre] of a reference. *)

val generated_parameter_name : string -> string -> int -> string
(** Produce a reserved name for a generated parameter, from its role, owner and
    position. *)
