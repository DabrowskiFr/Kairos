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
 * Builds [Ir_proof_views.annotated_node] from [Ir_proof_views.raw_node] while preserving transition
 * structure for diagnostics/export.
 *
 * The formulas may still contain [Ast.hexpr] references (prev^k x);
 * history elimination is performed in pass 5 ([Proof_obligation_lowering]).
 *---------------------------------------------------------------------------*)

(** Build the annotated proof snapshot from a raw snapshot and an IR node. *)

val annotate : raw:Ir_proof_views.raw_node -> node:Ir.node_ir -> Ir_proof_views.annotated_node
