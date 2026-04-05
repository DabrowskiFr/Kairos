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

(** Provenance graph primitives used to link generated proof obligations back to
    source-level formulas. *)

(** Unique identifier used to link derived formulas to their sources. *)
type id = int

(** Reset the provenance graph, mainly between runs and tests. *)
val reset : unit -> unit

(** Allocate a fresh identifier. *)
val fresh_id : unit -> id

(** Register an identifier without parent links. *)
val register : id -> unit

(** Record parent links for a derived identifier. *)
val add_parents : child:id -> parents:id list -> unit

(** Direct parents of an identifier, one derivation step away. *)
val parents : id -> id list

(** Transitive closure of parent links. *)
val ancestors : id -> id list
