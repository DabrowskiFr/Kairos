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
open Core_syntax
open Ast

let parse_line_col_from_error (msg : string) : (int * int) option =
  let re = Str.regexp ".*:\\([0-9]+\\):\\([0-9]+\\)" in
  if Str.string_match re msg 0 then
    Some (int_of_string (Str.matched_group 1 msg), int_of_string (Str.matched_group 2 msg))
  else None

type diagnostic = {
  line : int;
  col : int;
  severity : int;
  source : string;
  message : string;
}

let mk_diag ~severity ~source ~message : diagnostic =
  let line, col =
    match parse_line_col_from_error message with
    | Some (l, c) -> (max 0 (l - 1), max 0 (c - 1))
    | None -> (0, 0)
  in
  { line; col; severity; source; message }

let diagnostics_for_text ~uri:_ ~(text : string) : diagnostic list =
  try
    let _source, info =
      Parse_api.parse_source_text_with_info ~filename:"<lsp-buffer>" ~text
    in
    let diags = ref [] in
    List.iter
      (fun e ->
        diags :=
          mk_diag ~severity:1 ~source:"kairos-parse"
            ~message:e.Parse_api.message
          :: !diags)
      info.Parse_api.parse_errors;
    List.iter
      (fun w -> diags := mk_diag ~severity:2 ~source:"kairos-parse" ~message:w :: !diags)
      info.Parse_api.warnings;
    List.rev !diags
  with exn ->
    let msg = Printexc.to_string exn in
    [ mk_diag ~severity:1 ~source:"kairos-parse" ~message:msg ]

type outline_sections = {
  nodes : (string * int) list;
  transitions : (string * int) list;
  contracts : (string * int) list;
}

let outline_sections_of_text (text : string) : outline_sections =
  let node_re = Str.regexp "^[ \t]*node[ \t]+\\([A-Za-z0-9_']+\\)" in
  let trans_re = Str.regexp "\\([A-Za-z0-9_']+\\)[ \t]*->[ \t]*\\([A-Za-z0-9_']+\\)" in
  let contract_re =
    Str.regexp
      "\\brequires\\b\\|\\bensures\\b\\|\\bassumes\\b\\|\\bguarantees\\b\\|\\bassume\\b\\|\\bguarantee\\b"
  in
  let transitions_header_re = Str.regexp "^[ \t]*transitions\\b" in
  let section_header_re =
    Str.regexp
      "^[ \t]*\\(states\\|contracts\\|locals\\|invariants\\|instances\\|transitions\\|end\\)\\b"
  in
  let src_state_re = Str.regexp "^[ \t]*\\([A-Za-z0-9_']+\\)[ \t]*:[ \t]*\\({\\)?[ \t]*$" in
  let to_dst_re = Str.regexp "^[ \t]*to[ \t]+\\([A-Za-z0-9_']+\\)\\b" in
  let nodes = ref [] in
  let transitions = ref [] in
  let contracts = ref [] in
  let seen_trans = Hashtbl.create 32 in
  let seen_contracts = Hashtbl.create 32 in
  let add_trans name line_no =
    let k = String.lowercase_ascii (String.trim name) ^ "@" ^ string_of_int line_no in
    if not (Hashtbl.mem seen_trans k) then (
      Hashtbl.add seen_trans k ();
      transitions := (name, line_no) :: !transitions)
  in
  let add_contract name line_no =
    let k = String.lowercase_ascii (String.trim name) ^ "@" ^ string_of_int line_no in
    if not (Hashtbl.mem seen_contracts k) then (
      Hashtbl.add seen_contracts k ();
      contracts := (name, line_no) :: !contracts)
  in
  let in_transitions = ref false in
  let current_src = ref None in
  let lines = String.split_on_char '\n' text in
  List.iteri
    (fun idx raw_line ->
      let line = String.trim (Str.global_replace (Str.regexp "\r") "" raw_line) in
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
  { nodes = List.rev !nodes; transitions = List.rev !transitions; contracts = List.rev !contracts }

let yojson_of_name_line_list (xs : (string * int) list) : Yojson.Safe.t =
  `List
    (List.map
       (fun (name, line) -> `Assoc [ ("name", `String name); ("line", `Int line) ])
       xs)

let yojson_of_outline_sections (s : outline_sections) : Yojson.Safe.t =
  `Assoc
    [
      ("nodes", yojson_of_name_line_list s.nodes);
      ("transitions", yojson_of_name_line_list s.transitions);
      ("contracts", yojson_of_name_line_list s.contracts);
    ]

type goal_tree_entry = {
  idx : int;
  goal : string;
  status : string;
  time_s : float;
  dump_path : string option;
  source : string;
  vcid : string option;
}

type goal_tree_transition = {
  transition : string;
  source : string;
  succeeded : int;
  total : int;
  items : goal_tree_entry list;
}

type goal_tree_node = {
  node : string;
  source : string;
  succeeded : int;
  total : int;
  transitions : goal_tree_transition list;
}

let normalize_status (status : string) : string = String.lowercase_ascii (String.trim status)

let grouped_source_key (source : string) : string =
  let s = String.trim source in
  if s = "" then "<no transition>"
  else
    try
      let idx = String.index s ':' in
      String.trim (String.sub s 0 idx)
    with Not_found -> s

let parse_source_scope (source : string) : string * string =
  let s = String.trim source in
  let node = grouped_source_key s in
  let trans_re = Str.regexp "\\([A-Za-z0-9_']+\\)[ \t]*->[ \t]*\\([A-Za-z0-9_']+\\)" in
  let transition =
    try
      ignore (Str.search_forward trans_re s 0);
      Printf.sprintf "%s -> %s" (Str.matched_group 1 s) (Str.matched_group 2 s)
    with Not_found -> "<no transition>"
  in
  (node, transition)

let extract_goal_sources_by_index (vc_text : string) : (int, string) Hashtbl.t =
  let tbl = Hashtbl.create 64 in
  let goal_re = Str.regexp "^[ \t]*goal[ \t]+" in
  let comment_re = Str.regexp "^\\s*\\(\\* \\(.+\\) \\*\\)\\s*$" in
  let len = String.length vc_text in
  let rec scan pos acc =
    if pos >= len then List.rev acc
    else
      try
        let _ = Str.search_forward goal_re vc_text pos in
        let start = Str.match_beginning () in
        let next =
          try
            let _ = Str.search_forward goal_re vc_text (Str.match_end ()) in
            Str.match_beginning ()
          with Not_found -> len
        in
        scan next ((start, next) :: acc)
      with Not_found -> if pos = 0 && len > 0 then [ (0, len) ] else List.rev acc
  in
  let spans = scan 0 [] in
  List.iteri
    (fun idx (a, b) ->
      let task = String.sub vc_text a (b - a) in
      let lines = String.split_on_char '\n' task in
      let label =
        List.find_map
          (fun line ->
            if Str.string_match comment_re line 0 then Some (Str.matched_group 2 line)
            else None)
          lines
        |> Option.value ~default:""
      in
      if label <> "" then Hashtbl.replace tbl idx label)
    spans;
  tbl

let group_goal_entries (entries : goal_tree_entry list) : goal_tree_node list =
  let nodes : (string, (string, goal_tree_entry list ref) Hashtbl.t * string list ref) Hashtbl.t =
    Hashtbl.create 32
  in
  let node_order = ref [] in
  let node_counts : (string, int * int) Hashtbl.t = Hashtbl.create 32 in
  List.iter
    (fun (e : goal_tree_entry) ->
      let node, transition = parse_source_scope e.source in
      if not (Hashtbl.mem nodes node) then (
        Hashtbl.add nodes node (Hashtbl.create 8, ref []);
        Hashtbl.add node_counts node (0, 0);
        node_order := !node_order @ [ node ]);
      let trans_map, trans_order = Hashtbl.find nodes node in
      if not (Hashtbl.mem trans_map transition) then (
        Hashtbl.add trans_map transition (ref []);
        trans_order := !trans_order @ [ transition ]);
      let r = Hashtbl.find trans_map transition in
      r := !r @ [ e ];
      let s, t = Hashtbl.find node_counts node in
      let s' = if normalize_status e.status = "valid" then s + 1 else s in
      Hashtbl.replace node_counts node (s', t + 1))
    entries;
  List.map
    (fun node ->
      let trans_map, trans_order = Hashtbl.find nodes node in
      let transitions =
        List.map
          (fun transition ->
            let items = !(Hashtbl.find trans_map transition) in
            let s, t =
              List.fold_left
                (fun (s, t) (e : goal_tree_entry) ->
                  let s' = if normalize_status e.status = "valid" then s + 1 else s in
                  (s', t + 1))
                (0, 0) items
            in
            { transition; source = node ^ ": " ^ transition; succeeded = s; total = t; items })
          !trans_order
      in
      let succeeded, total = Hashtbl.find node_counts node in
      { node; source = node; succeeded; total; transitions })
    !node_order

let goals_tree_final ~goals ~vc_text : goal_tree_node list =
  let source_by_index = extract_goal_sources_by_index vc_text in
  let entries =
    List.mapi
      (fun idx (goal, status_txt, time_s, dump_path, vcid) ->
        let source_idx = Hashtbl.find_opt source_by_index idx in
        let source = match source_idx with Some s when s <> "" -> s | _ -> "" in
        { idx; goal; status = String.trim status_txt; time_s; dump_path; source; vcid })
      goals
  in
  group_goal_entries entries

let goals_tree_pending ~(goal_names : string list) ~(vc_ids : int list) : goal_tree_node list =
  let entries =
    List.mapi
      (fun idx goal ->
        let vcid = List.nth_opt vc_ids idx in
        {
          idx;
          goal;
          status = "pending";
          time_s = 0.0;
          dump_path = None;
          source = "";
          vcid = Option.map string_of_int vcid;
        })
      goal_names
  in
  group_goal_entries entries

let yojson_of_goal_entry ~(display_no : int) (e : goal_tree_entry) : Yojson.Safe.t =
  `Assoc
    [
      ("idx", `Int e.idx);
      ("display_no", `Int display_no);
      ("goal", `String e.goal);
      ("status", `String e.status);
      ("time_s", `Float e.time_s);
      ("dump_path", match e.dump_path with None -> `Null | Some s -> `String s);
      ("source", `String e.source);
      ("vcid", match e.vcid with None -> `Null | Some s -> `String s);
    ]

let yojson_of_goals_tree (nodes : goal_tree_node list) : Yojson.Safe.t =
  `List
    (List.map
       (fun node ->
         let transitions_json =
           `List
             (List.map
                (fun transition ->
                  let items_json =
                    `List
                      (List.mapi
                         (fun i e -> yojson_of_goal_entry ~display_no:(i + 1) e)
                         transition.items)
                  in
                  `Assoc
                    [
                      ("transition", `String transition.transition);
                      ("source", `String transition.source);
                      ("succeeded", `Int transition.succeeded);
                      ("total", `Int transition.total);
                      ("items", items_json);
                    ])
                node.transitions)
         in
         `Assoc
           [
             ("node", `String node.node);
             ("source", `String node.source);
             ("succeeded", `Int node.succeeded);
             ("total", `Int node.total);
             ("transitions", transitions_json);
           ])
       nodes)

let lines_of_text (text : string) : string array = text |> String.split_on_char '\n' |> Array.of_list

let is_ident_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' | '\'' -> true
  | _ -> false

let identifier_at_line (line_s : string) (ch : int) : (string * int * int) option =
  let n = String.length line_s in
  if n = 0 then None
  else
    let i = max 0 (min (if ch >= n then n - 1 else ch) (n - 1)) in
    if not (is_ident_char line_s.[i]) then None
    else
      let rec left k = if k > 0 && is_ident_char line_s.[k - 1] then left (k - 1) else k in
      let rec right k = if k < n && is_ident_char line_s.[k] then right (k + 1) else k in
      let a = left i in
      let b = right i in
      if a >= b then None else Some (String.sub line_s a (b - a), a, b)

let identifier_at (text : string) (line : int) (character : int) : string option =
  let lines = lines_of_text text in
  if Array.length lines = 0 then None
  else
    let l = max 0 (min line (Array.length lines - 1)) in
    match identifier_at_line lines.(l) character with Some (id, _, _) -> Some id | None -> None

let identifier_occurrences (text : string) (ident : string) : (int * int * int) list =
  let lines = lines_of_text text in
  let out = ref [] in
  Array.iteri
    (fun li line_s ->
      let n = String.length line_s in
      let m = String.length ident in
      if m > 0 && n >= m then
        for i = 0 to n - m do
          if String.sub line_s i m = ident then
            let left_ok = i = 0 || not (is_ident_char line_s.[i - 1]) in
            let right_ok = i + m = n || not (is_ident_char line_s.[i + m]) in
            if left_ok && right_ok then out := (li, i, i + m) :: !out
        done)
    lines;
  List.rev !out

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  vars : string list;
}

let semantic_symbols_of_program (p : Ast.program) : semantic_symbols =
  let tbl_all = Hashtbl.create 256 in
  let tbl_nodes = Hashtbl.create 64 in
  let tbl_states = Hashtbl.create 128 in
  let tbl_vars = Hashtbl.create 256 in
  let add tbl s = if s <> "" then Hashtbl.replace tbl s () in
  List.iter
    (fun (n : Ast.node) ->
      let sem = n.semantics in
      add tbl_nodes sem.sem_nname;
      add tbl_all sem.sem_nname;
      List.iter (fun st -> add tbl_states st; add tbl_all st) sem.sem_states;
      List.iter (fun v -> add tbl_vars v.vname; add tbl_all v.vname) sem.sem_inputs;
      List.iter (fun v -> add tbl_vars v.vname; add tbl_all v.vname) sem.sem_outputs;
      List.iter (fun v -> add tbl_vars v.vname; add tbl_all v.vname) sem.sem_locals)
    p;
  let to_list tbl = Hashtbl.to_seq_keys tbl |> List.of_seq |> List.sort_uniq String.compare in
  { all = to_list tbl_all; nodes = to_list tbl_nodes; states = to_list tbl_states; vars = to_list tbl_vars }

let parse_program_from_text (text : string) : Ast.program option =
  try
    let source, _info =
      Parse_api.parse_source_text_with_info ~filename:"<lsp-buffer>" ~text
    in
    Some source.nodes
  with _ -> None

let symbol_kind (symbols : semantic_symbols) (ident : string) : string option =
  if List.mem ident symbols.nodes then Some "node"
  else if List.mem ident symbols.states then Some "state"
  else if List.mem ident symbols.vars then Some "variable"
  else if List.mem ident symbols.all then Some "symbol"
  else None

let first_definition_position ~(text : string) ~(ident : string) ~(symbols : semantic_symbols) :
    (int * int * int) option =
  let lines = lines_of_text text in
  let find_by_re re =
    let found = ref None in
    Array.iteri
      (fun li line_s ->
        if !found = None && Str.string_match re line_s 0 then
          match String.index_opt line_s ident.[0] with
          | Some i -> found := Some (li, i, i + String.length ident)
          | None -> ())
      lines;
    !found
  in
  if List.mem ident symbols.nodes then
    find_by_re (Str.regexp ("^[ \t]*node[ \t]+" ^ Str.quote ident ^ "\\b"))
  else if List.mem ident symbols.states then
    find_by_re (Str.regexp ("^[ \t]*states\\b.*\\b" ^ Str.quote ident ^ "\\b"))
  else if List.mem ident symbols.vars then
    find_by_re (Str.regexp ("^[ \t]*.*\\b" ^ Str.quote ident ^ "\\b[ \t]*[:,)]"))
  else None

type document_symbol = { name : string; line : int; character : int }

let document_symbols_for_text (text : string) : document_symbol list =
  let sec = outline_sections_of_text text in
  List.map (fun (name, line) -> { name; line = max 0 (line - 1); character = 0 }) sec.nodes

let completion_items_for_text (text : string) : string list =
  let tbl = Hashtbl.create 256 in
  let push s = if String.length s > 0 then Hashtbl.replace tbl s () in
  let keywords =
    [
      "node"; "returns"; "contracts"; "ensures"; "requires"; "assumes"; "guarantees";
      "locals"; "states"; "invariants"; "transitions"; "to"; "end"; "if"; "then"; "else";
      "match"; "skip"; "init";
    ]
  in
  List.iter push keywords;
  begin
    match parse_program_from_text text with
    | Some p ->
        let syms = semantic_symbols_of_program p in
        List.iter push syms.all
    | None -> ()
  end;
  Hashtbl.to_seq_keys tbl |> List.of_seq |> List.sort_uniq String.compare

let format_text (text : string) : string =
  let lines = String.split_on_char '\n' text in
  let fmt_lines =
    List.map
      (fun s ->
        let t = String.trim s in
        if t = "" then "" else t)
      lines
  in
  String.concat "\n" fmt_lines
