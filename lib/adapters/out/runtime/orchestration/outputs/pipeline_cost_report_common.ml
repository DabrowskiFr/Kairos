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

module Json = Yojson.Safe
module StringMap = Map.Make (String)
module StringSet = Set.Make (String)

let json_int n = `Int n
let json_float f = `Float f
let json_string s = `String s
let json_bool b = `Bool b
let json_list f xs = `List (List.map f xs)
let json_assoc xs = `Assoc xs

let json_opt f = function None -> `Null | Some x -> f x

let count_if pred xs =
  List.fold_left (fun acc x -> if pred x then acc + 1 else acc) 0 xs

let sum_int xs = List.fold_left ( + ) 0 xs

let max_int xs =
  List.fold_left max 0 xs

let average_int xs =
  match xs with
  | [] -> 0.0
  | _ -> float_of_int (sum_int xs) /. float_of_int (List.length xs)

let top_values limit xs =
  let rec take n = function
    | _ when n <= 0 -> []
    | [] -> []
    | x :: tl -> x :: take (n - 1) tl
  in
  take limit xs

let top_string_values limit xs = top_values limit xs

let truncate_string max_len s =
  if String.length s <= max_len then s
  else String.sub s 0 max_len ^ "..."

let starts_with ~prefix s =
  let lp = String.length prefix in
  String.length s >= lp && String.sub s 0 lp = prefix

let contains_substring s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  let rec loop i =
    if len_sub = 0 then true
    else if i + len_sub > len_s then false
    else if String.sub s i len_sub = sub then true
    else loop (i + 1)
  in
  loop 0
