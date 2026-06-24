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

type module_profile = {
  name : string;
  line_count : int;
  byte_count : int;
}

let helper_class name =
  if contains_substring name "_bad_guarantee_group_" then
    ("bad-guarantee", true)
  else if contains_substring name "_safe_group_" then ("safe", true)
  else if contains_substring name "_bad_guarantee_" then
    ("bad-guarantee", false)
  else if contains_substring name "_safe_" then ("safe", false)
  else ("unknown", false)

let module_name_of_header line =
  let trimmed = String.trim line in
  let prefix = "module " in
  if not (starts_with ~prefix trimmed) then None
  else
    let rest =
      String.sub trimmed (String.length prefix)
        (String.length trimmed - String.length prefix)
    in
    match String.split_on_char ' ' rest with
    | name :: _ when name <> "" -> Some name
    | _ -> None

let module_profiles text =
  let finish acc = function
    | None -> acc
    | Some (name, lines, bytes) ->
        { name; line_count = lines; byte_count = bytes } :: acc
  in
  let rec loop acc current = function
    | [] -> List.rev (finish acc current)
    | line :: rest -> (
        match module_name_of_header line with
        | Some name ->
            let acc = finish acc current in
            loop acc (Some (name, 1, String.length line + 1)) rest
        | None ->
            let current =
              match current with
              | None -> None
              | Some (name, lines, bytes) ->
                  Some (name, lines + 1, bytes + String.length line + 1)
            in
            loop acc current rest)
  in
  loop [] None (String.split_on_char '\n' text)

let helper_profiles text =
  module_profiles text
  |> List.filter (fun profile -> contains_substring profile.name "__step_")

let helper_profile_json helpers =
  let class_count expected_class expected_grouped =
    count_if
      (fun helper ->
        let cls, grouped = helper_class helper.name in
        cls = expected_class && grouped = expected_grouped)
      helpers
  in
  let top_helpers =
    helpers
    |> List.sort (fun left right ->
           match Int.compare right.byte_count left.byte_count with
           | 0 -> Int.compare right.line_count left.line_count
           | cmp -> cmp)
    |> top_values 20
  in
  let helper_json helper =
    let cls, grouped = helper_class helper.name in
    json_assoc
      [
        ("name", json_string helper.name);
        ("class", json_string cls);
        ("grouped", json_bool grouped);
        ("line_count", json_int helper.line_count);
        ("byte_count", json_int helper.byte_count);
      ]
  in
  json_assoc
    [
      ("helper_module_count", json_int (List.length helpers));
      ("safe_group_helper_count", json_int (class_count "safe" true));
      ("safe_individual_helper_count", json_int (class_count "safe" false));
      ( "bad_guarantee_group_helper_count",
        json_int (class_count "bad-guarantee" true) );
      ( "bad_guarantee_individual_helper_count",
        json_int (class_count "bad-guarantee" false) );
      ("unknown_helper_count", json_int (class_count "unknown" false));
      ("top_helpers_by_bytes", json_list helper_json top_helpers);
    ]

let why3_json why_text ~why_text_s =
  let lines = String.split_on_char '\n' why_text in
  let helpers = helper_profiles why_text in
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
      ("helper_profile", helper_profile_json helpers);
    ]
