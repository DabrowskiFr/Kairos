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

let make ?loc ?family logic : 'phase Kr_verification_ir.summary_formula =
  { logic; meta = { oid = fresh_oid (); loc; family } }

let values (xs : 'phase Kr_verification_ir.summary_formula list) : 'phase Kr_domain_core_syntax.hexpr list =
  List.map (fun (x : 'phase Kr_verification_ir.summary_formula) -> x.logic) xs

let temporal_bindings_of_layout (layout : Kr_verification_ir.temporal_layout) : Kr_domain_core.Kr_domain_core_history.temporal_binding list =
  Kr_domain_core.Kr_domain_core_history.temporal_bindings_of_layout ~temporal_layout:layout

let temporal_bindings_of_node (node : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir) : Kr_domain_core.Kr_domain_core_history.temporal_binding list =
  temporal_bindings_of_layout node.temporal_layout
