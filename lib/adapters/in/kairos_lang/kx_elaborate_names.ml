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

module S = Kx_surface_syntax

let indexed_ident_many base idxs = String.concat "_" (base :: idxs)

let indexed_ref_name (r : S.indexed_ref) =
  indexed_ident_many r.ref_base r.ref_indices

let same_indexed_ref (a : S.indexed_ref) (b : S.indexed_ref) =
  String.equal a.ref_base b.ref_base && a.ref_indices = b.ref_indices

let generated_history_prefix = "__kairos_history_"

let generated_history_name def_name r =
  generated_history_prefix ^ def_name ^ "_" ^ indexed_ref_name r
