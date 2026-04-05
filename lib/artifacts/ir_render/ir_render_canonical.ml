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

open Ast
open Ast_pretty
open Temporal_support

module Abs = Ir

type rendered = {
  canonical_lines : string list;
  canonical_tex : string;
  canonical_dot : string;
}

type formula_aliases = {
  dot_alias_of : string -> string;
  tex_alias_of : string -> string;
  definitions : (string * string) list;
}

type transition_aliases = {
  dot_alias_of_id : int -> string;
  tex_alias_of_id : int -> string;
  definitions : (string * string) list;
}

let escape_dot_label (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let escape_html_label (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '&' -> Buffer.add_string b "&amp;"
      | '<' -> Buffer.add_string b "&lt;"
      | '>' -> Buffer.add_string b "&gt;"
      | '"' -> Buffer.add_string b "&quot;"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let add_formula_legend_rows_html buf ~title defs =
  if defs <> [] then (
    Buffer.add_string buf
      (Printf.sprintf
         "      <TR><TD COLSPAN=\"2\" ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\"><B>%s</B></FONT></TD></TR>\n"
         (escape_html_label title));
    List.iter
      (fun (alias, formula) ->
        Buffer.add_string buf
          (Printf.sprintf
             "      <TR><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">%s</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">%s</FONT></TD></TR>\n"
             (escape_html_label alias) (escape_html_label formula)))
      defs)

let html_contract_label ~tau =
  String.concat "\n"
    [
      "<";
      "  <TABLE BORDER=\"0\" CELLBORDER=\"1\" CELLSPACING=\"0\" CELLPADDING=\"4\" COLOR=\"#4f5b66\">";
      "    <TR><TD BGCOLOR=\"#e9edf1\" ALIGN=\"LEFT\"><FONT POINT-SIZE=\"11\">"
      ^ escape_html_label tau ^ "</FONT></TD></TR>";
      "  </TABLE>";
      ">";
    ]

let add_sink_legend_block_html buf ~legend_id ~title ~rows_html ~anchor_id =
  Buffer.add_string buf "  subgraph cluster_legend_sink {\n";
  Buffer.add_string buf "    rank=sink;\n";
  Buffer.add_string buf "    color=\"transparent\";\n";
  Buffer.add_string buf "    margin=0;\n";
  Buffer.add_string buf
    (Printf.sprintf "    %s [shape=plaintext,margin=0.1,label=<\n" legend_id);
  Buffer.add_string buf "      <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n";
  Buffer.add_string buf
    (Printf.sprintf
       "        <TR><TD COLSPAN=\"2\" ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\"><B>%s</B></FONT></TD></TR>\n"
       (escape_html_label title));
  Buffer.add_string buf rows_html;
  Buffer.add_string buf "      </TABLE>>];\n";
  Buffer.add_string buf "  }\n";
  Buffer.add_string buf
    (Printf.sprintf "  %s -> %s [style=invis,weight=0];\n" anchor_id legend_id)

let escape_tex (s : string) : string =
  let repl = function
    | '_' -> "\\_"
    | '&' -> "\\&"
    | '%' -> "\\%"
    | '#' -> "\\#"
    | '$' -> "\\$"
    | '{' -> "\\{"
    | '}' -> "\\}"
    | c -> String.make 1 c
  in
  String.to_seq s |> Seq.map repl |> List.of_seq |> String.concat ""

let replace_all ~pattern ~by s =
  let plen = String.length pattern in
  if plen = 0 then s
  else
    let b = Buffer.create (String.length s) in
    let rec loop i =
      if i >= String.length s then ()
      else if i + plen <= String.length s && String.sub s i plen = pattern then (
        Buffer.add_string b by;
        loop (i + plen))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
    in
    loop 0;
    Buffer.contents b

let strip_braces (s : string) : string =
  s |> replace_all ~pattern:"{" ~by:"" |> replace_all ~pattern:"}" ~by:""

let rewrite_history_vars (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let is_digit c = c >= '0' && c <= '9' in
  let is_ident_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'
  in
  let rec loop i =
    if i >= len then ()
    else if i + 7 <= len && String.sub s i 7 = "__pre_k" then
      let j = i + 7 in
      let rec read_digits k = if k < len && is_digit s.[k] then read_digits (k + 1) else k in
      let k = read_digits j in
      if k > j && k < len && s.[k] = '_' then
        let vstart = k + 1 in
        let rec read_ident m = if m < len && is_ident_char s.[m] then read_ident (m + 1) else m in
        let vend = read_ident vstart in
        if vend > vstart then (
          let depth = String.sub s j (k - j) in
          let v = String.sub s vstart (vend - vstart) in
          if depth = "1" then Buffer.add_string b ("pre(" ^ v ^ ")")
          else Buffer.add_string b ("pre_k(" ^ v ^ ", " ^ depth ^ ")");
          loop vend)
        else (
          Buffer.add_char b s.[i];
          loop (i + 1))
      else (
        Buffer.add_char b s.[i];
        loop (i + 1))
    else (
      Buffer.add_char b s.[i];
      loop (i + 1))
  in
  loop 0;
  Buffer.contents b

let pretty_formula (f : Fo_formula.t) : string =
  f |> string_of_fo |> strip_braces |> rewrite_history_vars

let pretty_fo (f : Fo_formula.t) : string = f |> string_of_fo |> strip_braces |> rewrite_history_vars

let pretty_stmt (s : Ast.stmt) : string =
  match s.stmt with
  | SAssign (v, e) -> v ^ " := " ^ Ast_pretty.string_of_iexpr e
  | SIf (c, _t, []) -> "if " ^ Ast_pretty.string_of_iexpr c ^ " then { ... }"
  | SIf (c, _t, _e) -> "if " ^ Ast_pretty.string_of_iexpr c ^ " then { ... } else { ... }"
  | SCall (inst, args, rets) ->
      "(" ^ String.concat ", " rets ^ ") := " ^ inst
      ^ "(" ^ String.concat ", " (List.map Ast_pretty.string_of_iexpr args) ^ ")"
  | SSkip -> "skip"
  | SMatch (e, _branches, _default) -> "match " ^ Ast_pretty.string_of_iexpr e ^ " { ... }"

let pretty_transition (t : Abs.transition) : string =
  let guard =
    match t.guard_iexpr with
    | None -> "true"
    | Some g -> string_of_iexpr g
  in
  let body =
    match t.body_stmts with
    | [] -> "skip"
    | xs -> String.concat "; " (List.map pretty_stmt xs)
  in
  Printf.sprintf "%s -> %s when %s / %s" t.src_state t.dst_state guard body

let pretty_transition_core (t : Abs.transition) : string =
  let guard =
    match t.guard_iexpr with
    | None -> "true"
    | Some g -> string_of_iexpr g
  in
  let body =
    match t.body_stmts with
    | [] -> "skip"
    | xs -> String.concat "; " (List.map pretty_stmt xs)
  in
  Printf.sprintf "%s -> %s when %s / %s" t.src_state t.dst_state guard body

let mathify (s : string) : string =
  s
  |> replace_all ~pattern:"<>" ~by:"\\neq "
  |> replace_all ~pattern:" -> " ~by:" \\rightarrow "
  |> replace_all ~pattern:" and " ~by:" \\land "
  |> replace_all ~pattern:" or " ~by:" \\lor "
  |> replace_all ~pattern:"not " ~by:"\\neg "
  |> replace_all ~pattern:"true" ~by:"\\top"
  |> replace_all ~pattern:"false" ~by:"\\bot"

let string_of_product_state (st : Abs.product_state) =
  Printf.sprintf "(%s, A%d, G%d)" st.prog_state st.assume_state_index st.guarantee_state_index

let contract_node_id (idx : int) = Printf.sprintf "c_%d" idx

let sanitize_id (s : string) : string =
  String.map
    (fun c ->
      match c with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> c
      | _ -> '_')
    s

let source_node_id_of (id : string) =
  "s_" ^ String.lowercase_ascii (sanitize_id id)

let safe_destination_node_id_of (id : string) =
  "d_" ^ String.lowercase_ascii (sanitize_id id)

let case_destination_node_id_of (id : string) =
  "k_" ^ String.lowercase_ascii (sanitize_id id)

let safe_cases (pc : Abs.product_step_summary) : Abs.safe_product_case list =
  pc.safe_cases

let bad_cases (pc : Abs.product_step_summary) : Abs.unsafe_product_case list =
  pc.unsafe_cases

let safe_guarantee_guard (pc : Abs.product_step_summary) : Fo_formula.t option =
  match safe_cases pc with
  | [] -> None
  | first :: rest ->
      Some
        (List.fold_left
           (fun acc (case : Abs.safe_product_case) ->
             Fo_formula.FOr (acc, case.admissible_guard.logic))
           first.admissible_guard.logic rest)

let safe_product_dsts (pc : Abs.product_step_summary) : Abs.product_state list =
  pc.safe_cases
  |> List.map (fun (case : Abs.safe_product_case) -> case.product_dst)
  |> List.sort_uniq Stdlib.compare

let safe_admissible_guards (pc : Abs.product_step_summary) : Abs.summary_formula list =
  pc.safe_cases
  |> List.map (fun (case : Abs.safe_product_case) -> case.admissible_guard)

let string_of_product_state_list (xs : Abs.product_state list) : string =
  "[" ^ String.concat ", " (List.map string_of_product_state xs) ^ "]"

let canonical_formula_aliases ~(node : Abs.node_ir) =
  let seen = Hashtbl.create 32 in
  let defs_rev = ref [] in
  let next = ref 1 in
  let register formula =
    if not (Hashtbl.mem seen formula) then (
      let dot_alias = Printf.sprintf "φ%d" !next in
      let tex_alias = Printf.sprintf "\\phi_{%d}" !next in
      incr next;
      Hashtbl.add seen formula (dot_alias, tex_alias);
      defs_rev := (tex_alias, formula) :: !defs_rev)
  in
  node.summaries
  |> List.iter (fun (pc : Abs.product_step_summary) ->
         let t = pc.identity.program_step in
         let program_guard =
           match t.guard_iexpr with
           | None -> "true"
           | Some g -> string_of_iexpr g
         in
         register program_guard;
         register (pretty_fo pc.identity.assume_guard);
         Option.iter (fun g -> register (pretty_fo g)) (safe_guarantee_guard pc);
         bad_cases pc
         |> List.iter (fun (case : Abs.unsafe_product_case) ->
                register (pretty_fo case.excluded_guard.logic)));
  let dot_alias_of formula = fst (Hashtbl.find seen formula) in
  let tex_alias_of formula = snd (Hashtbl.find seen formula) in
  { dot_alias_of; tex_alias_of; definitions = List.rev !defs_rev }

let canonical_transition_aliases ~(node : Abs.node_ir) =
  let by_id : (int, string) Hashtbl.t = Hashtbl.create 32 in
  List.iter
    (fun (pc : Abs.product_step_summary) ->
      if not (Hashtbl.mem by_id pc.trace.step_uid) then
        Hashtbl.add by_id pc.trace.step_uid
          (pretty_transition_core pc.identity.program_step))
    node.summaries;
  let definitions =
    Hashtbl.to_seq by_id |> List.of_seq |> List.sort (fun (a, _) (b, _) -> Int.compare a b)
    |> List.map (fun (id, repr) -> (Printf.sprintf "t_{%d}" id, repr))
  in
  {
    dot_alias_of_id = (fun id -> Printf.sprintf "t%d" id);
    tex_alias_of_id = (fun id -> Printf.sprintf "t_{%d}" id);
    definitions;
  }

let state_style ~(analysis : Product_analysis.analysis) (st : Abs.product_state) =
  if st.assume_state_index = analysis.assume_bad_idx && analysis.assume_bad_idx >= 0 then
    ("#fff1e0", "#e67e22")
  else if st.guarantee_state_index = analysis.guarantee_bad_idx && analysis.guarantee_bad_idx >= 0 then
    ("#fdecea", "#c0392b")
  else if
    String.equal st.prog_state analysis.exploration.initial_state.prog_state
    && st.assume_state_index = analysis.exploration.initial_state.assume_state
    && st.guarantee_state_index = analysis.exploration.initial_state.guarantee_state
  then ("#eaf2ff", "#3b6fb6")
  else ("#ffffff", "#666666")

let source_id_of_contract (contract_index : int) : string =
  Printf.sprintf "S%d" contract_index

let safe_destination_id_of_contract ~(contract_index : int)
    (pc : Abs.product_step_summary) : string option =
  if safe_product_dsts pc = [] then None
  else Some (Printf.sprintf "D%d" contract_index)

let render_canonical_lines ~(node : Abs.node_ir) =
  node.summaries
  |> List.mapi (fun idx (pc : Abs.product_step_summary) ->
         let contract_index = idx + 1 in
         let t = pc.identity.program_step in
         let head =
           Printf.sprintf "C%d: %s=%s via tr_%d (%s -> %s), A=%s" contract_index
             (source_id_of_contract contract_index)
             (string_of_product_state pc.identity.product_src)
             pc.trace.step_uid t.src_state t.dst_state
             (pretty_fo pc.identity.assume_guard)
         in
         let reqs =
           pc.requires
           |> List.map (fun (f : Abs.summary_formula) -> "  pre += " ^ pretty_formula f.logic)
         in
         let common_ensures =
           pc.ensures
           |> List.map (fun (f : Abs.summary_formula) -> "  post += " ^ pretty_formula f.logic)
         in
         let safe_part =
           match (safe_destination_id_of_contract ~contract_index pc, safe_guarantee_guard pc) with
           | None, _ -> []
           | Some _, None -> []
           | Some dst_id, Some g ->
               [
                 Printf.sprintf "  κ%d.safe: Safe -> %s=%s, G=%s" contract_index dst_id
                   (string_of_product_state_list (safe_product_dsts pc))
                   (pretty_fo g);
               ]
               @ (safe_admissible_guards pc
                 |> List.map (fun (f : Abs.summary_formula) -> "    propagate += " ^ pretty_formula f.logic))
        in
        let cases =
          bad_cases pc
           |> List.mapi (fun case_idx (case : Abs.unsafe_product_case) ->
                  let case_id =
                    Printf.sprintf "K%d_%d" contract_index
                      (List.length pc.safe_cases + case_idx + 1)
                  in
                  let kind =
                    "BadGuarantee"
                  in
                  let base =
                    Printf.sprintf "  κ%d.%d: %s -> %s=%s, G=%s" contract_index (case_idx + 1) kind
                      case_id
                      (string_of_product_state case.product_dst)
                      (pretty_fo case.excluded_guard.logic)
                  in
                  let props =
                    []
                  in
                  let forb =
                    [ case.excluded_guard ]
                    |> List.map (fun (f : Abs.summary_formula) -> "    forbid += " ^ pretty_formula f.logic)
                  in
                  String.concat "\n" (base :: props @ forb))
         in
         String.concat "\n" (head :: reqs @ common_ensures @ safe_part @ cases))

let render_canonical_tex ~(node : Abs.node_ir) =
  let aliases = canonical_formula_aliases ~node in
  let transition_aliases = canonical_transition_aliases ~node in
  let phi_lines =
    aliases.definitions
    |> List.map (fun (alias, formula) ->
           Printf.sprintf "%s &\\equiv& %s \\\\" alias (escape_tex (mathify formula)))
  in
  let t_lines =
    transition_aliases.definitions
    |> List.map (fun (alias, transition) ->
           Printf.sprintf "%s &\\equiv& %s \\\\" alias (escape_tex transition))
  in
  let blocks =
    [
      ("\\[\n\\begin{array}{lcl}\n", phi_lines);
      ("\\[\n\\begin{array}{lcl}\n", t_lines);
    ]
    |> List.filter_map (fun (prefix, lines) ->
           if lines = [] then None
           else Some (prefix ^ String.concat "\n" lines ^ "\n\\end{array}\n\\]\n"))
  in
  String.concat "\n" blocks

let render_canonical_dot ~(node_name : ident) ~(analysis : Product_analysis.analysis) ~(node : Abs.node_ir) =
  let aliases = canonical_formula_aliases ~node in
  let transition_aliases = canonical_transition_aliases ~node in
  let source_defs =
    node.summaries
    |> List.mapi (fun idx (pc : Abs.product_step_summary) ->
           let contract_index = idx + 1 in
           let sid_raw = source_id_of_contract contract_index in
           let sid = source_node_id_of sid_raw in
           let fill, color = state_style ~analysis pc.identity.product_src in
           let label =
             Printf.sprintf "%s = %s" sid_raw (string_of_product_state pc.identity.product_src)
           in
           Printf.sprintf
             "  %s [shape=box, style=\"rounded,filled\", fillcolor=\"%s\", color=\"%s\", label=\"%s\"];"
             sid fill color
             (escape_dot_label label))
    |> List.sort_uniq String.compare
  in
  let contract_defs = ref [] in
  let safe_defs = ref [] in
  let case_defs = ref [] in
  let edges = ref [] in
  node.summaries
  |> List.iteri (fun idx (pc : Abs.product_step_summary) ->
         let cid_num = idx + 1 in
         let contract_index = idx + 1 in
         let t = pc.identity.program_step in
         let program_guard =
           match t.guard_iexpr with
           | None -> "true"
           | Some g -> string_of_iexpr g
         in
         let cid = contract_node_id cid_num in
         let clabel =
           html_contract_label
             ~tau:(transition_aliases.dot_alias_of_id pc.trace.step_uid)
         in
         let cdef =
           Printf.sprintf
             "  %s [shape=plain, margin=0, label=%s];"
             cid clabel
         in
         contract_defs := cdef :: !contract_defs;
         let src_id = source_node_id_of (source_id_of_contract contract_index) in
         let head_lbl =
           Printf.sprintf "P: %s, A: %s"
             (aliases.dot_alias_of program_guard |> escape_dot_label)
             (aliases.dot_alias_of (pretty_fo pc.identity.assume_guard) |> escape_dot_label)
         in
         let head_edge =
           Printf.sprintf
             "  %s -> %s [label=\"%s\", color=\"#4f5b66\", fontcolor=\"#4f5b66\", penwidth=1.4];"
             src_id cid head_lbl
         in
         edges := head_edge :: !edges;
         begin
           match (safe_destination_id_of_contract ~contract_index pc, safe_guarantee_guard pc) with
           | None, _ -> ()
           | Some _, None -> ()
           | Some did_raw, Some g ->
               let did = safe_destination_node_id_of did_raw in
               let safe_label =
                 Printf.sprintf "%s = %s" did_raw
                   (string_of_product_state_list (safe_product_dsts pc))
               in
               let ddef =
                 Printf.sprintf
                   "  %s [shape=box, style=\"rounded,dashed\", color=\"#2c7a7b\", fontcolor=\"#2c7a7b\", label=\"%s\"];"
                   did
                   (escape_dot_label safe_label)
               in
               safe_defs := ddef :: !safe_defs;
               let safe_edge =
                 Printf.sprintf "  %s -> %s [label=\"G: %s\", color=\"#2c7a7b\", fontcolor=\"#2c7a7b\"];"
                   cid did
                   (aliases.dot_alias_of (pretty_fo g) |> escape_dot_label)
               in
               edges := safe_edge :: !edges
         end;
         bad_cases pc
         |> List.iteri (fun case_idx (case : Abs.unsafe_product_case) ->
                let case_id =
                  Printf.sprintf "K%d_%d" contract_index
                    (List.length pc.safe_cases + case_idx + 1)
                in
                let did = case_destination_node_id_of case_id in
                let fill, border = state_style ~analysis case.product_dst in
                let dst_label =
                  Printf.sprintf "%s = %s" case_id
                    (string_of_product_state case.product_dst)
                in
                let ddef =
                  Printf.sprintf
                    "  %s [shape=box, style=\"rounded,filled\", fillcolor=\"%s\", color=\"%s\", label=\"%s\"];"
                    did fill border
                    (escape_dot_label dst_label)
                in
                case_defs := ddef :: !case_defs;
                let color =
                  "#c0392b"
                in
                let lbl =
                  Printf.sprintf "G: %s"
                    (aliases.dot_alias_of (pretty_fo case.excluded_guard.logic) |> escape_dot_label)
                in
                let edge =
                  Printf.sprintf "  %s -> %s [label=\"%s\", color=\"%s\", fontcolor=\"%s\"];"
                    cid did lbl color color
                in
                edges := edge :: !edges));
  let contract_defs = List.rev !contract_defs in
  let safe_defs = List.sort_uniq String.compare (List.rev !safe_defs) in
  let case_defs = List.sort_uniq String.compare (List.rev !case_defs) in
  let edges = List.rev !edges in
  let formula_legend_defs = aliases.definitions in
  let transition_legend_defs = transition_aliases.definitions in
  String.concat "\n"
    ([
       "digraph canonical_proof {";
       "  rankdir=TB;";
       "  compound=true;";
       "  graph [fontname=\"Helvetica\"];";
       "  node [fontname=\"Helvetica\"];";
       "  edge [fontname=\"Helvetica\"];";
       "  subgraph cluster_main {";
       "    rankdir=LR;";
       "    color=\"transparent\";";
       Printf.sprintf "    labelloc=\"t\";";
       Printf.sprintf "    label=\"Canonical proof structure for %s\";" (escape_dot_label node_name);
     ]
    @ List.map (fun s -> "  " ^ s) source_defs
    @ List.map (fun s -> "  " ^ s) contract_defs
    @ List.map (fun s -> "  " ^ s) safe_defs
    @ List.map (fun s -> "  " ^ s) case_defs
    @ List.map (fun s -> "  " ^ s) edges
    @ [ "  }" ]
    @
    if formula_legend_defs = [] && transition_legend_defs = [] then [ "}" ]
    else
      let tmp = Buffer.create 256 in
      add_formula_legend_rows_html tmp ~title:"Formula aliases" formula_legend_defs;
      add_formula_legend_rows_html tmp ~title:"Transition aliases" transition_legend_defs;
      let legend_block =
        match List.rev node.summaries with
        | _ :: _ ->
            let last_contract_index = List.length node.summaries in
            let anchor_id = source_node_id_of (source_id_of_contract last_contract_index) in
            [
              "  subgraph cluster_legend_sink {";
              "    rank=sink;";
              "    color=\"transparent\";";
              "    margin=0;";
              "    legend_canonical [shape=plaintext,margin=0.1,label=<";
              "      <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">";
            ]
            @ (Buffer.contents tmp |> String.split_on_char '\n' |> List.filter (fun s -> s <> "") |> List.map (fun s -> "  " ^ s))
            @ [
                "      </TABLE>>];";
                "  }";
                Printf.sprintf "  %s -> legend_canonical [style=invis,weight=100];" anchor_id;
              ]
        | [] -> []
      in
      legend_block @ [ "}" ])

let render ~node_name ~(analysis : Product_analysis.analysis) ~(node : Abs.node_ir) =
  {
    canonical_lines = render_canonical_lines ~node;
    canonical_tex = render_canonical_tex ~node;
    canonical_dot = render_canonical_dot ~node_name ~analysis ~node;
  }
