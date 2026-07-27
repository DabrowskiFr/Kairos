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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

let join_with_spans ~sep blocks =
  let b = Buffer.create 4096 in
  let spans = ref [] in
  let offset = ref 0 in
  List.iteri
    (fun i s ->
      if i > 0 then (
        Buffer.add_string b sep;
        offset := !offset + String.length sep);
      let start_offset = !offset in
      Buffer.add_string b s;
      offset := !offset + String.length s;
      spans :=
        { Pipeline_proof_types.start_offset = start_offset; end_offset = !offset }
        :: !spans)
    blocks;
  (Buffer.contents b, List.rev !spans)
