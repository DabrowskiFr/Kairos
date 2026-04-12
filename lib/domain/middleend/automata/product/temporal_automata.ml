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
open Core_syntax
type node_data = {
  exploration : Product_types.exploration;
  assume_bad_idx : int;
  guarantee_bad_idx : int;
  guarantee_state_labels : string list;
  assume_state_labels : string list;
  guarantee_grouped_edges : Automaton_types.transition list;
  assume_grouped_edges : Automaton_types.transition list;
  guarantee_atom_map_exprs : (ident * expr) list;
  assume_atom_map_exprs : (ident * expr) list;
}
