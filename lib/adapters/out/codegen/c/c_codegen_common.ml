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

let ( let* ) = Result.bind

module StringSet = Set.Make (String)

let errorf fmt = Printf.ksprintf (fun msg -> Error msg) fmt

let map_result f xs =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | x :: rest ->
        let* y = f x in
        loop (y :: acc) rest
  in
  loop [] xs

let concat_map_result f xs =
  let* chunks = map_result f xs in
  Ok (List.concat chunks)

let indent n = String.make (2 * n) ' '
let line n s = indent n ^ s
let blank = ""
let join_lines lines = String.concat "\n" lines ^ "\n"
