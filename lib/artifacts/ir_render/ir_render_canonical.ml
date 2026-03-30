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

let pretty_ltl (f : ltl) : string = f |> string_of_ltl |> strip_braces |> rewrite_history_vars

let pretty_fo (f : Fo_formula.t) : string = f |> string_of_fo |> strip_braces |> rewrite_history_vars

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

let state_node_id (idx : int) = Printf.sprintf "st_%d" idx
let contract_node_id (idx : int) = Printf.sprintf "c_%d" idx

let canonical_formula_aliases ~(node : Abs.node) =
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
  node.product_transitions
  |> List.iter (fun (pc : Abs.product_contract) ->
         let t = List.nth node.trans pc.program_transition_index in
         let program_guard =
           match t.guard with
           | None -> "true"
           | Some g -> string_of_iexpr g
         in
         register program_guard;
         register (pretty_fo pc.assume_guard);
         pc.cases |> List.iter (fun (case : Abs.product_case) -> register (pretty_fo case.guarantee_guard)));
  let dot_alias_of formula = fst (Hashtbl.find seen formula) in
  let tex_alias_of formula = snd (Hashtbl.find seen formula) in
  { dot_alias_of; tex_alias_of; definitions = List.rev !defs_rev }

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

let render_canonical_lines ~(node : Abs.node) =
  node.product_transitions
  |> List.mapi (fun idx (pc : Abs.product_contract) ->
         let t = List.nth node.trans pc.program_transition_index in
         let head =
           Printf.sprintf "C%d: %s via tr_%d (%s -> %s), A=%s" (idx + 1)
             (string_of_product_state pc.product_src) pc.program_transition_index t.src t.dst
             (pretty_fo pc.assume_guard)
         in
         let reqs =
           pc.requires
           |> List.map (fun (f : Abs.contract_formula) -> "  pre += " ^ pretty_ltl f.value)
         in
         let common_ensures =
           pc.ensures
           |> List.map (fun (f : Abs.contract_formula) -> "  post += " ^ pretty_ltl f.value)
         in
         let cases =
           pc.cases
           |> List.mapi (fun case_idx (case : Abs.product_case) ->
                  let kind =
                    match case.step_class with
                    | Abs.Safe -> "Safe"
                    | Abs.Bad_assumption -> "BadAssumption"
                    | Abs.Bad_guarantee -> "BadGuarantee"
                  in
                  let base =
                    Printf.sprintf "  κ%d.%d: %s -> %s, G=%s" (idx + 1) (case_idx + 1) kind
                      (string_of_product_state case.product_dst)
                      (pretty_fo case.guarantee_guard)
                  in
                  let props =
                    case.propagates
                    |> List.map (fun (f : Abs.contract_formula) -> "    propagate += " ^ pretty_ltl f.value)
                  in
                  let ens =
                    case.ensures
                    |> List.map (fun (f : Abs.contract_formula) -> "    ensure += " ^ pretty_ltl f.value)
                  in
                  let forb =
                    case.forbidden
                    |> List.map (fun (f : Abs.contract_formula) -> "    forbid += " ^ pretty_ltl f.value)
                  in
                  String.concat "\n" (base :: props @ ens @ forb))
         in
         String.concat "\n" (head :: reqs @ common_ensures @ cases))

let render_canonical_tex ~(node : Abs.node) =
  let aliases = canonical_formula_aliases ~node in
  let lines =
    aliases.definitions
    |> List.map (fun (alias, formula) ->
           Printf.sprintf "%s &\\equiv& %s \\\\" alias (escape_tex (mathify formula)))
  in
  "\\[\n\\begin{array}{lcl}\n" ^ String.concat "\n" lines ^ "\n\\end{array}\n\\]\n"

let render_canonical_dot ~(node_name : ident) ~(analysis : Product_analysis.analysis) ~(node : Abs.node) =
  let aliases = canonical_formula_aliases ~node in
  let states =
    node.product_transitions
    |> List.fold_left
         (fun acc (pc : Abs.product_contract) ->
           let acc = pc.product_src :: acc in
           List.fold_left
             (fun acc (case : Abs.product_case) -> case.product_dst :: acc)
             acc pc.cases)
         []
    |> List.sort_uniq Stdlib.compare
  in
  let state_index = Hashtbl.create 32 in
  List.iteri (fun idx st -> Hashtbl.replace state_index st idx) states;
  let state_defs =
    states
    |> List.mapi (fun idx st ->
           let fill, color = state_style ~analysis st in
           Printf.sprintf
             "  %s [shape=box, style=\"rounded,filled\", fillcolor=\"%s\", color=\"%s\", label=\"%s\"];"
             (state_node_id idx) fill color
             (escape_dot_label (string_of_product_state st)))
  in
  let contract_defs, edges =
    node.product_transitions
    |> List.mapi (fun idx (pc : Abs.product_contract) ->
           let t = List.nth node.trans pc.program_transition_index in
           let program_guard =
             match t.guard with
             | None -> "true"
             | Some g -> string_of_iexpr g
           in
           let cid = contract_node_id (idx + 1) in
           let clabel =
             Printf.sprintf "C%d\\nP: %s\\nA: %s" (idx + 1)
               (aliases.dot_alias_of program_guard |> escape_dot_label)
               (aliases.dot_alias_of (pretty_fo pc.assume_guard) |> escape_dot_label)
           in
           let cdef =
             Printf.sprintf
               "  %s [shape=ellipse, style=\"filled\", fillcolor=\"#f4f6f8\", color=\"#4f5b66\", label=\"%s\"];"
               cid clabel
           in
           let src_id =
             state_node_id (Hashtbl.find state_index pc.product_src)
           in
           let head_edge = Printf.sprintf "  %s -> %s [color=\"#4f5b66\", penwidth=1.4];" src_id cid in
          let case_edges =
            pc.cases
            |> List.mapi (fun case_idx (case : Abs.product_case) ->
                   let dst_id = state_node_id (Hashtbl.find state_index case.product_dst) in
                    let color =
                      match case.step_class with
                      | Abs.Safe -> "#2c7a7b"
                      | Abs.Bad_assumption -> "#e67e22"
                      | Abs.Bad_guarantee -> "#c0392b"
                    in
                    let lbl =
                      Printf.sprintf "κ%d.%d\\nG: %s" (idx + 1) (case_idx + 1)
                        (aliases.dot_alias_of (pretty_fo case.guarantee_guard) |> escape_dot_label)
                    in
                    Printf.sprintf "  %s -> %s [label=\"%s\", color=\"%s\", fontcolor=\"%s\"];"
                      cid dst_id lbl color color)
           in
           (cdef, head_edge :: case_edges))
    |> List.split
  in
  let legend_defs = aliases.definitions in
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
    @ List.map (fun s -> "  " ^ s) state_defs
    @ List.map (fun s -> "  " ^ s) contract_defs
    @ List.map (fun s -> "  " ^ s) (List.concat edges)
    @ [ "  }" ]
    @
    if legend_defs = [] then [ "}" ]
    else
      let tmp = Buffer.create 256 in
      add_formula_legend_rows_html tmp ~title:"Formula aliases" legend_defs;
      let legend_block =
        match List.rev states with
        | last_state :: _ ->
            let anchor_id = state_node_id (Hashtbl.find state_index last_state) in
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

let render ~node_name ~(analysis : Product_analysis.analysis) ~(node : Abs.node) =
  {
    canonical_lines = render_canonical_lines ~node;
    canonical_tex = render_canonical_tex ~node;
    canonical_dot = render_canonical_dot ~node_name ~analysis ~node;
  }
