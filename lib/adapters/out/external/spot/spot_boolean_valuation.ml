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

open Core_syntax_builders

type term = (string * bool option) list

let can_merge_terms (left : term) (right : term) : bool =
  let difference_count = ref 0 in
  let rec loop = function
    | [], [] -> !difference_count = 1
    | (_, left_value) :: left_rest, (_, right_value) :: right_rest -> (
        match (left_value, right_value) with
        | Some left_bool, Some right_bool when left_bool = right_bool ->
            loop (left_rest, right_rest)
        | Some _, Some _ ->
            incr difference_count;
            !difference_count <= 1 && loop (left_rest, right_rest)
        | None, None -> loop (left_rest, right_rest)
        | None, Some _ | Some _, None -> false)
    | _ -> false
  in
  loop (left, right)

let merge_terms (left : term) (right : term) : term =
  List.map2
    (fun (left_name, left_value) (_right_name, right_value) ->
      let value =
        match (left_value, right_value) with
        | Some left_bool, Some right_bool when left_bool = right_bool ->
            Some left_bool
        | Some _, Some _ | None, None -> None
        | None, Some value | Some value, None -> Some value
      in
      (left_name, value))
    left right

let unique_terms terms =
  let rec loop accumulator = function
    | [] -> List.rev accumulator
    | term :: rest ->
        if List.exists (( = ) term) accumulator then loop accumulator rest
        else loop (term :: accumulator) rest
  in
  loop [] terms

let prime_implicants terms =
  let rec loop terms primes =
    let terms = unique_terms terms in
    let term_count = List.length terms in
    let used = Array.make term_count false in
    let merged = ref [] in
    for left_index = 0 to term_count - 1 do
      for right_index = left_index + 1 to term_count - 1 do
        let left = List.nth terms left_index in
        let right = List.nth terms right_index in
        if can_merge_terms left right then (
          used.(left_index) <- true;
          used.(right_index) <- true;
          merged := merge_terms left right :: !merged)
      done
    done;
    let new_primes =
      List.fold_left
        (fun accumulator (index, term) ->
          if used.(index) then accumulator else term :: accumulator)
        primes
        (List.mapi (fun index term -> (index, term)) terms)
    in
    if !merged = [] then unique_terms new_primes else loop !merged new_primes
  in
  loop terms []

let term_to_expr term =
  let parts =
    List.filter_map
      (fun (name, value) ->
        match value with
        | None -> None
        | Some true -> Some (mk_var name)
        | Some false -> Some (mk_expr (Core_syntax.EUn (Not, mk_var name))))
      term
  in
  match parts with
  | [] -> mk_bool true
  | [ part ] -> part
  | part :: rest ->
      List.fold_left
        (fun accumulator next -> mk_expr (Core_syntax.EBin (And, accumulator, next)))
        part rest

let terms_to_expr terms =
  match terms with
  | [] -> mk_bool false
  | _ ->
      if List.exists (List.for_all (fun (_, value) -> value = None)) terms then
        mk_bool true
      else
        match List.map term_to_expr terms with
        | [] -> mk_bool false
        | [ part ] -> part
        | part :: rest ->
            List.fold_left
              (fun accumulator next ->
                mk_expr (Core_syntax.EBin (Or, accumulator, next)))
              part rest
