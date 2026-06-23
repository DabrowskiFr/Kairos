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

type outline_sections = {
  nodes : (string * int) list;
  transitions : (string * int) list;
  contracts : (string * int) list;
}

let outline_sections_of_text (text : string) : outline_sections =
  let node_re = Str.regexp "^[ \t]*node[ \t]+\\([A-Za-z0-9_']+\\)" in
  let trans_re =
    Str.regexp "\\([A-Za-z0-9_']+\\)[ \t]*->[ \t]*\\([A-Za-z0-9_']+\\)"
  in
  let contract_re =
    Str.regexp
      "\\brequires\\b\\|\\bensures\\b\\|\\bassumes\\b\\|\\bguarantees\\b\\|\\bassume\\b\\|\\bguarantee\\b"
  in
  let transitions_header_re = Str.regexp "^[ \t]*transitions\\b" in
  let section_header_re =
    Str.regexp
      "^[ \t]*\\(states\\|contracts\\|locals\\|invariants\\|instances\\|transitions\\|end\\)\\b"
  in
  let src_state_re =
    Str.regexp "^[ \t]*\\([A-Za-z0-9_']+\\)[ \t]*:[ \t]*\\({\\)?[ \t]*$"
  in
  let to_dst_re = Str.regexp "^[ \t]*to[ \t]+\\([A-Za-z0-9_']+\\)\\b" in
  let nodes = ref [] in
  let transitions = ref [] in
  let contracts = ref [] in
  let seen_trans = Hashtbl.create 32 in
  let seen_contracts = Hashtbl.create 32 in
  let add_trans name line_no =
    let k =
      String.lowercase_ascii (String.trim name) ^ "@" ^ string_of_int line_no
    in
    if not (Hashtbl.mem seen_trans k) then (
      Hashtbl.add seen_trans k ();
      transitions := (name, line_no) :: !transitions)
  in
  let add_contract name line_no =
    let k =
      String.lowercase_ascii (String.trim name) ^ "@" ^ string_of_int line_no
    in
    if not (Hashtbl.mem seen_contracts k) then (
      Hashtbl.add seen_contracts k ();
      contracts := (name, line_no) :: !contracts)
  in
  let in_transitions = ref false in
  let current_src = ref None in
  let lines = String.split_on_char '\n' text in
  List.iteri
    (fun idx raw_line ->
      let line =
        String.trim (Str.global_replace (Str.regexp "\r") "" raw_line)
      in
      if Str.string_match transitions_header_re line 0 then (
        in_transitions := true;
        current_src := None)
      else if Str.string_match section_header_re line 0 then (
        in_transitions := false;
        current_src := None);
      if Str.string_match node_re line 0 then (
        let name = Str.matched_group 1 line in
        nodes := (name, idx + 1) :: !nodes);
      if
        (try
           ignore (Str.search_forward trans_re line 0);
           true
         with Not_found -> false)
      then
        let from_s = Str.matched_group 1 line in
        let to_s = Str.matched_group 2 line in
        add_trans (Printf.sprintf "%s -> %s" from_s to_s) (idx + 1);
      if !in_transitions && Str.string_match src_state_re line 0 then
        current_src := Some (Str.matched_group 1 line);
      if !in_transitions && Str.string_match to_dst_re line 0 then
        match !current_src with
        | Some src ->
            let dst = Str.matched_group 1 line in
            add_trans (Printf.sprintf "%s -> %s" src dst) (idx + 1)
        | None -> ();
      if
        (try
           ignore (Str.search_forward contract_re line 0);
           true
         with Not_found -> false)
      then
        add_contract (String.trim line) (idx + 1))
    lines;
  {
    nodes = List.rev !nodes;
    transitions = List.rev !transitions;
    contracts = List.rev !contracts;
  }

let yojson_of_name_line_list (xs : (string * int) list) : Yojson.Safe.t =
  `List
    (List.map
       (fun (name, line) ->
         `Assoc [ ("name", `String name); ("line", `Int line) ])
       xs)

let yojson_of_outline_sections (s : outline_sections) : Yojson.Safe.t =
  `Assoc
    [
      ("nodes", yojson_of_name_line_list s.nodes);
      ("transitions", yojson_of_name_line_list s.transitions);
      ("contracts", yojson_of_name_line_list s.contracts);
    ]
