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

let product_transition_index_of_id transition_id : int option =
  let raw =
    if String.starts_with ~prefix:"tr_" transition_id then
      String.sub transition_id 3 (String.length transition_id - 3)
    else ""
  in
  let len = String.length raw in
  let rec first_non_digit i =
    if i >= len then len else match raw.[i] with '0' .. '9' -> first_non_digit (i + 1) | _ -> i
  in
  let prefix_len = first_non_digit 0 in
  if prefix_len = 0 then None else int_of_string_opt (String.sub raw 0 prefix_len)
