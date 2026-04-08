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

let with_origin ?loc origin logic : Ir.summary_formula =
  { logic; meta = { origin = Some origin; oid = Provenance.fresh_id (); loc } }

let values (xs : Ir.summary_formula list) : Fo_formula.t list =
  List.map (fun (x : Ir.summary_formula) -> x.logic) xs

let temporal_bindings_of_layout (layout : Ir.temporal_layout) : Fo_specs.temporal_binding list =
  Fo_specs.temporal_bindings_of_pre_k_map ~pre_k_map:layout

let temporal_bindings_of_node (node : Ir.node_ir) : Fo_specs.temporal_binding list =
  temporal_bindings_of_layout node.temporal_layout
