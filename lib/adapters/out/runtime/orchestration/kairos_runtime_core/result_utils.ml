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

let ( let* ) = Result.bind

let find_assoc ~missing key xs =
  match List.assoc_opt key xs with
  | Some value -> Ok value
  | None -> Error (missing key)

let rec all = function
  | [] -> Ok []
  | x :: xs ->
      let* x = x in
      let* xs = all xs in
      Ok (x :: xs)

let rec map4 ~length_mismatch f xs ys zs ws =
  match (xs, ys, zs, ws) with
  | [], [], [], [] -> Ok []
  | x :: xs, y :: ys, z :: zs, w :: ws ->
      let* x = f x y z w in
      let* xs = map4 ~length_mismatch f xs ys zs ws in
      Ok (x :: xs)
  | _ -> Error length_mismatch
