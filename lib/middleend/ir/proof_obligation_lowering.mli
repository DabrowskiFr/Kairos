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

(** Pass 5: history elimination over the Kairos IR. *)

(*---------------------------------------------------------------------------
 * Kairos — Pass 5: History elimination.
 *
 * Substitutes all [Ast.hexpr] references of the form [prev^k x] (i.e.
 * [HPreK(x, k)]) with the corresponding ghost local variable
 * [IVar "__pre_k{k}_x"], producing a [Ir.verified_node] that is
 * ready for trivial structural Why3 emission.
 *
 * The pass also:
 * - appends the introduced [__pre_k{k}_x] variables to the node's locals;
 * - attaches the shift+capture statements to every transition's
 *   [pre_k_updates] field.
 *---------------------------------------------------------------------------*)

(** Eliminate history references from the annotated view stored inside the IR. *)

val apply_node : Ir.node -> Ir.node
val apply_program : Ir.node list -> Ir.node list
