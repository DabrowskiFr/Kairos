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

(** Why3 text section of the pipeline cost report. *)

open Pipeline_cost_report_common

let line_count text =
  let len = String.length text in
  if len = 0 then 0
  else
    let newlines = ref 0 in
    String.iter (fun c -> if c = '\n' then incr newlines) text;
    if text.[len - 1] = '\n' then !newlines else !newlines + 1

let count_lines pred text =
  text |> String.split_on_char '\n'
  |> List.fold_left
       (fun acc line ->
         let line = String.trim line in
         if pred line then acc + 1 else acc)
       0

let why3_json why_text ~why_text_s =
  let lines = String.split_on_char '\n' why_text in
  let shared_predicate_count =
    count_lines (starts_with ~prefix:"predicate shared_contract_formula_") why_text
  in
  let step_helper_count =
    count_lines
      (fun line ->
        starts_with ~prefix:"let step_" line
        || starts_with ~prefix:"let ghost step_" line)
      why_text
  in
  let logic_decl_count =
    count_lines
      (fun line ->
        starts_with ~prefix:"predicate " line
        || starts_with ~prefix:"function " line
        || starts_with ~prefix:"val " line)
      why_text
  in
  let assert_count =
    count_lines (starts_with ~prefix:"assert") why_text
  in
  let shared_contract_assert_count =
    count_lines
      (fun line ->
        starts_with ~prefix:"assert" line
        && contains_substring line "shared_contract_formula_")
      why_text
  in
  let max_line_length =
    max_int (List.map String.length lines)
  in
  json_assoc
    [
      ("generated", json_bool true);
      ("generation_wall_s", json_float why_text_s);
      ("byte_count", json_int (String.length why_text));
      ("line_count", json_int (line_count why_text));
      ("max_line_length", json_int max_line_length);
      ("logic_declaration_count", json_int logic_decl_count);
      ("shared_predicate_count", json_int shared_predicate_count);
      ("step_helper_count", json_int step_helper_count);
      ("requires_count", json_int (count_lines (starts_with ~prefix:"requires") why_text));
      ("ensures_count", json_int (count_lines (starts_with ~prefix:"ensures") why_text));
      ("assert_count", json_int assert_count);
      ("shared_contract_assert_count", json_int shared_contract_assert_count);
    ]
