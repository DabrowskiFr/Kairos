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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Physical sharing pass for repeated canonical IR formulas.

    This pass does not rewrite formulas. It only reuses structurally equal
    formula values to reduce downstream allocation and comparison costs. *)

(** Share formulas inside one node IR. *)
val run_node : Ir.node_ir -> Ir.node_ir

(** Share formulas independently in each node of a program IR. *)
val run_program : Ir.node_ir list -> Ir.node_ir list
