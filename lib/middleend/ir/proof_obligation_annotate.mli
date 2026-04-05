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

(*---------------------------------------------------------------------------
 * Kairos — Pass 4: Annotated-view materialization.
 *
 * Builds [Ir.annotated_node] from [Ir.raw_node] while preserving transition
 * structure for diagnostics/export.
 *
 * The formulas may still contain [Ast.hexpr] references (prev^k x);
 * history elimination is performed in pass 5 ([Proof_obligation_lowering]).
 *---------------------------------------------------------------------------*)

(** Materializes the annotated proof view stored inside the IR. *)

val apply_node : analysis:Product_build.analysis -> Ir.node -> Ir.node
val apply_program : analyses:(Ast.ident * Product_build.analysis) list -> Ir.node list -> Ir.node list
