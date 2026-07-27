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

let next_oid = ref 0

let fresh_oid () =
  incr next_oid;
  !next_oid

let make ?loc ?family logic : 'phase Ir.summary_formula =
  { logic; meta = { oid = fresh_oid (); loc; family } }

let values (xs : 'phase Ir.summary_formula list) : 'phase Core_syntax.hexpr list =
  List.map (fun (x : 'phase Ir.summary_formula) -> x.logic) xs

let temporal_bindings_of_layout (layout : Ir.temporal_layout) : Pre_k_lowering.temporal_binding list =
  Pre_k_lowering.temporal_bindings_of_layout ~temporal_layout:layout

let temporal_bindings_of_node (node : Core_syntax.historical Ir.node_ir) : Pre_k_lowering.temporal_binding list =
  temporal_bindings_of_layout node.temporal_layout
