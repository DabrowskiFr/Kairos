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

let normalize_status (status : string) : string =
  String.lowercase_ascii (String.trim status)

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
  let trans_re =
    Str.regexp "\\([A-Za-z0-9_']+\\)[ \t]*->[ \t]*\\([A-Za-z0-9_']+\\)"
  in
  let transition =
    try
      ignore (Str.search_forward trans_re s 0);
      Printf.sprintf "%s -> %s" (Str.matched_group 1 s)
        (Str.matched_group 2 s)
    with Not_found -> "<no transition>"
  in
  (node, transition)

let extract_goal_sources_by_index (vc_text : string) : (int, string) Hashtbl.t
    =
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
      with Not_found ->
        if pos = 0 && len > 0 then [ (0, len) ] else List.rev acc
  in
  let spans = scan 0 [] in
  List.iteri
    (fun idx (a, b) ->
      let task = String.sub vc_text a (b - a) in
      let lines = String.split_on_char '\n' task in
      let label =
        List.find_map
          (fun line ->
            if Str.string_match comment_re line 0 then
              Some (Str.matched_group 2 line)
            else None)
          lines
        |> Option.value ~default:""
      in
      if label <> "" then Hashtbl.replace tbl idx label)
    spans;
  tbl

let group_goal_entries (entries : goal_tree_entry list) : goal_tree_node list =
  let nodes :
      (string, (string, goal_tree_entry list ref) Hashtbl.t * string list ref)
      Hashtbl.t =
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
                  let s' =
                    if normalize_status e.status = "valid" then s + 1 else s
                  in
                  (s', t + 1))
                (0, 0) items
            in
            {
              transition;
              source = node ^ ": " ^ transition;
              succeeded = s;
              total = t;
              items;
            })
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
        {
          idx;
          goal;
          status = String.trim status_txt;
          time_s;
          dump_path;
          source;
          vcid;
        })
      goals
  in
  group_goal_entries entries

let goals_tree_pending
    ~(goal_names : string list)
    ~(vc_ids : int list) :
    goal_tree_node list =
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

let yojson_of_goal_entry
    ~(display_no : int)
    (e : goal_tree_entry) :
    Yojson.Safe.t =
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
                         (fun i e ->
                           yojson_of_goal_entry ~display_no:(i + 1) e)
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
