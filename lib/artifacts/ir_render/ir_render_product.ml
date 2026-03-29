open Ast
open Ast_builders
open Generated_names
open Temporal_support
open Ast_pretty
open Fo_specs

module PT = Product_types
module Abs = Ir

type rendered = {
  guarantee_automaton_lines : string list;
  assume_automaton_lines : string list;
  guarantee_automaton_tex : string;
  assume_automaton_tex : string;
  product_tex : string;
  product_tex_explicit : string;
  product_lines : string list;
  obligations_lines : string list;
  prune_lines : string list;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  product_dot_explicit : string;
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

let string_of_state (s : PT.product_state) : string =
  Printf.sprintf "(%s, A%d, G%d)" s.prog_state s.assume_state s.guarantee_state

let string_of_step_class = function
  | PT.Safe -> "safe"
  | PT.Bad_assumption -> "bad_A"
  | PT.Bad_guarantee -> "bad_G"

let string_of_prune_reason = function
  | PT.Incompatible_program_assumption -> "program/A incompatible"
  | PT.Incompatible_program_guarantee -> "program/G incompatible"
  | PT.Incompatible_assumption_guarantee -> "A/G incompatible"

let string_of_edge ((src, _guard, dst) : PT.automaton_edge) : string =
  Printf.sprintf "%d->%d" src dst

let obligation_formula (step : PT.product_step) : ltl =
  LNot
    (LAnd
       ( Temporal_support.ltl_of_fo step.prog_guard,
         LAnd
           ( Temporal_support.ltl_of_fo step.assume_guard,
             Temporal_support.ltl_of_fo step.guarantee_guard ) ))

let render_automaton_lines ~prefix labels =
  labels |> List.mapi (fun i lbl -> Printf.sprintf "%s%d = %s" prefix i lbl)

let strip_braces_early (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let rec loop i =
    if i >= len then ()
    else (
      let c = s.[i] in
      if c <> '{' && c <> '}' then Buffer.add_char b c;
      loop (i + 1))
  in
  loop 0;
  Buffer.contents b

let rewrite_history_vars_early (s : string) : string =
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
        let var_start = k + 1 in
        let rec read_ident m = if m < len && is_ident_char s.[m] then read_ident (m + 1) else m in
        let var_end = read_ident var_start in
        if var_end > var_start then (
          let k_str = String.sub s j (k - j) in
          let v = String.sub s var_start (var_end - var_start) in
          if k_str = "1" then Buffer.add_string b ("pre(" ^ v ^ ")")
          else Buffer.add_string b ("pre_k(" ^ v ^ ", " ^ k_str ^ ")");
          loop var_end)
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

let pretty_product_formula (f : Fo_formula.t) : string =
  f |> string_of_fo |> strip_braces_early |> rewrite_history_vars_early

let replace_all ~pattern ~by s =
  let plen = String.length pattern in
  if plen = 0 then s
  else
    let buf = Buffer.create (String.length s) in
    let rec loop i =
      if i >= String.length s then ()
      else if i + plen <= String.length s && String.sub s i plen = pattern then (
        Buffer.add_string buf by;
        loop (i + plen))
      else (
        Buffer.add_char buf s.[i];
        loop (i + 1))
    in
    loop 0;
    Buffer.contents buf

let mathify_formula (s : string) : string =
  s
  |> replace_all ~pattern:"<>" ~by:"≠"
  |> replace_all ~pattern:" -> " ~by:" → "
  |> replace_all ~pattern:" and " ~by:" ∧ "
  |> replace_all ~pattern:" or " ~by:" ∨ "
  |> replace_all ~pattern:"not " ~by:"¬"
  |> replace_all ~pattern:"true" ~by:"⊤"
  |> replace_all ~pattern:"false" ~by:"⊥"

let rec top_level_disjuncts (f : Fo_formula.t) : Fo_formula.t list =
  match f with FOr (a, b) -> top_level_disjuncts a @ top_level_disjuncts b | x -> [ x ]

let pretty_dot_formula (f : Fo_formula.t) : string =
  match top_level_disjuncts f with
  | [ x ] -> x |> pretty_product_formula |> mathify_formula
  | xs ->
      xs
      |> List.map (fun x -> x |> pretty_product_formula |> mathify_formula)
      |> String.concat ", "
      |> Printf.sprintf "{%s}"

let pretty_plain_dot_formula (f : Fo_formula.t) : string =
  f |> pretty_product_formula |> mathify_formula

let render_program_lines ~(node_name : ident) (node : Abs.node) =
  let states =
    node.semantics.sem_states
    |> List.map (fun st -> Printf.sprintf "[%s] P[%s]" node_name st)
  in
  let transitions =
    node.trans
    |> List.map (fun (t : Abs.transition) ->
           let guard =
             match t.guard with
             | None -> "⊤"
             | Some g -> g |> iexpr_to_fo_with_atoms [] |> pretty_plain_dot_formula
           in
           Printf.sprintf "[%s] P[%s -> %s] %s" node_name t.src t.dst guard)
  in
  states @ transitions

let render_product_lines ~(node_name : ident) (analysis : Product_analysis.analysis) =
  let states =
    analysis.exploration.states
    |> List.map (fun st -> Printf.sprintf "[%s] state %s" node_name (string_of_state st))
  in
  let steps =
    analysis.exploration.steps
    |> List.map (fun (step : PT.product_step) ->
           Printf.sprintf "[%s] %s -- P:%s / A[%s]:%s / G[%s]:%s --> %s [%s]" node_name
             (string_of_state step.src)
             (string_of_fo step.prog_guard)
             (string_of_edge step.assume_edge)
             (string_of_fo step.assume_guard)
             (string_of_edge step.guarantee_edge)
             (string_of_fo step.guarantee_guard)
             (string_of_state step.dst)
             (string_of_step_class step.step_class))
  in
  states @ steps

let render_obligation_lines ~(node_name : ident) (analysis : Product_analysis.analysis) =
  analysis.exploration.steps
  |> List.filter_map (fun (step : PT.product_step) ->
         match step.step_class with
         | PT.Bad_guarantee ->
             let src_live =
               step.src.assume_state <> analysis.assume_bad_idx
               && step.src.guarantee_state <> analysis.guarantee_bad_idx
             in
             let simplified = Fo_simplifier.simplify_ltl (obligation_formula step) in
             if (not src_live) || simplified = LTrue || simplified = LFalse then None
             else
               Some
                 (Printf.sprintf "[%s] obligation %s -> %s: %s" node_name
                    (string_of_state step.src)
                    (string_of_state step.dst)
                    (string_of_ltl simplified))
         | _ -> None)

let render_prune_lines ~(node_name : ident) (analysis : Product_analysis.analysis) =
  analysis.exploration.pruned_steps
  |> List.map (fun (step : PT.pruned_step) ->
         Printf.sprintf "[%s] prune %s -- %s / A[%s]:%s / G[%s]:%s [%s]" node_name
           (string_of_state step.src)
           step.prog_transition.src
           (string_of_edge step.assume_edge)
           (string_of_fo step.assume_guard)
           (string_of_edge step.guarantee_edge)
           (string_of_fo step.guarantee_guard)
           (string_of_prune_reason step.reason))

let node_id_of_state (s : PT.product_state) : string =
  Printf.sprintf "n_%s_a%d_g%d" s.prog_state s.assume_state s.guarantee_state

let product_state_index_map (states : PT.product_state list) =
  let tbl = Hashtbl.create 32 in
  List.iteri (fun i st -> Hashtbl.replace tbl st i) states;
  tbl

let product_subscript_digits (n : int) : string =
  let map = function
    | '0' -> "₀"
    | '1' -> "₁"
    | '2' -> "₂"
    | '3' -> "₃"
    | '4' -> "₄"
    | '5' -> "₅"
    | '6' -> "₆"
    | '7' -> "₇"
    | '8' -> "₈"
    | '9' -> "₉"
    | c -> String.make 1 c
  in
  string_of_int n |> String.to_seq |> List.of_seq |> List.map map |> String.concat ""

let pretty_aut_state ~prefix ~idx ~bad_idx =
  if bad_idx >= 0 && idx = bad_idx then Printf.sprintf "%s_bad" prefix
  else prefix ^ product_subscript_digits idx

let pretty_product_state (s : PT.product_state) ~(analysis : Product_analysis.analysis) : string =
  Printf.sprintf "(%s, %s, %s)" s.prog_state
    (pretty_aut_state ~prefix:"A" ~idx:s.assume_state ~bad_idx:analysis.assume_bad_idx)
    (pretty_aut_state ~prefix:"G" ~idx:s.guarantee_state ~bad_idx:analysis.guarantee_bad_idx)

let product_node_fill (s : PT.product_state) ~(analysis : Product_analysis.analysis) =
  if PT.compare_state s analysis.exploration.initial_state = 0 then ("#d9e8ff", "#3f6fb5")
  else if analysis.guarantee_bad_idx >= 0 && s.guarantee_state = analysis.guarantee_bad_idx then
    ("#f6d7d7", "#a53030")
  else if analysis.assume_bad_idx >= 0 && s.assume_state = analysis.assume_bad_idx then
    ("#f9ead7", "#b26a1f")
  else ("white", "#6b7280")

let pretty_step_class = function
  | PT.Safe -> "safe"
  | PT.Bad_assumption -> "bad_A"
  | PT.Bad_guarantee -> "bad_G"

let pretty_edge_ref ~prefix ~(edge : PT.automaton_edge) ~(bad_idx : int) =
  let src, _guard, dst = edge in
  Printf.sprintf "%s[%s → %s]" prefix
    (pretty_aut_state ~prefix ~idx:src ~bad_idx)
    (pretty_aut_state ~prefix ~idx:dst ~bad_idx)

let tau_alias (i : int) : string = "τ" ^ product_subscript_digits i

let split_all_on sep s =
  let sep_len = String.length sep in
  let rec loop acc start =
    if start > String.length s then List.rev acc
    else
      let rec find i =
        if i + sep_len > String.length s then None
        else if String.sub s i sep_len = sep then Some i
        else find (i + 1)
      in
      match find start with
      | None -> List.rev (String.sub s start (String.length s - start) :: acc)
      | Some i ->
          let piece = String.sub s start (i - start) in
          loop (piece :: acc) (i + sep_len)
  in
  loop [] 0

let wrap_formula_lines ?(max_width = 72) (s : string) : string list =
  let s = String.trim s in
  let join_wrapped sep pieces =
    let rec loop acc current = function
      | [] -> List.rev (String.trim current :: acc)
      | piece :: rest ->
          let piece = String.trim piece in
          let candidate = if current = "" then piece else current ^ sep ^ piece in
          if current <> "" && String.length candidate > max_width then
            loop (String.trim current :: acc) piece rest
          else loop acc candidate rest
    in
    loop [] "" pieces
  in
  if s = "" || String.length s <= max_width then [ s ]
  else
    let by_or = split_all_on " ∨ " s in
    if List.length by_or > 1 then join_wrapped " ∨ " by_or
    else
      let by_and = split_all_on " ∧ " s in
      if List.length by_and > 1 then join_wrapped " ∧ " by_and else [ s ]

let add_bottom_formula_table ?(multiline = false) ?(show_title = true) buf ~title
    ~(rows : (string * string) list) =
  if rows <> [] then (
    Buffer.add_string buf "  label=<\n";
    Buffer.add_string buf "    <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n";
    if show_title then
      Buffer.add_string buf
        (Printf.sprintf
           "      <TR><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\"><B>%s</B></FONT></TD></TR>\n"
           (escape_html_label title));
    List.iter
      (fun (alias, formula) ->
        if multiline then
          let lines = String.split_on_char '\n' formula in
          match lines with
          | [] -> ()
          | first :: rest ->
              Buffer.add_string buf
                (Printf.sprintf
                   "      <TR><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">%s</FONT></TD><TD \
                    ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">::=</FONT></TD><TD ALIGN=\"LEFT\"><FONT \
                    POINT-SIZE=\"10\">%s</FONT></TD></TR>\n"
                   (escape_html_label alias) (escape_html_label first));
              List.iter
                (fun line ->
                  Buffer.add_string buf
                    (Printf.sprintf
                       "      <TR><TD></TD><TD></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">%s</FONT></TD></TR>\n"
                       (escape_html_label line)))
                rest
        else
          Buffer.add_string buf
            (Printf.sprintf
               "      <TR><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">%s</FONT></TD><TD \
                ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">::=</FONT></TD><TD ALIGN=\"LEFT\"><FONT \
                POINT-SIZE=\"10\">%s</FONT></TD></TR>\n"
               (escape_html_label alias) (escape_html_label formula)))
      rows;
    Buffer.add_string buf "    </TABLE>>;\n")

type merged_product_edge = {
  src : PT.product_state;
  dst : PT.product_state;
  step_class : PT.step_class;
  prog_guard : Fo_formula.t;
  assume_guard : Fo_formula.t;
  guarantee_guard : Fo_formula.t;
}

type product_edge_visual = {
  color : string;
  style : string;
  category : string;
}

let merge_product_steps_for_dot (analysis : Product_analysis.analysis) : merged_product_edge list =
  let tbl = Hashtbl.create 64 in
  let key_of_step (step : PT.product_step) =
    ( step.src,
      step.dst,
      step.step_class,
      step.assume_edge,
      step.guarantee_edge,
      step.assume_guard,
      step.guarantee_guard )
  in
  List.iter
    (fun (step : PT.product_step) ->
      let key = key_of_step step in
      match Hashtbl.find_opt tbl key with
      | None ->
          Hashtbl.add tbl key
            {
              src = step.src;
              dst = step.dst;
              step_class = step.step_class;
              prog_guard = step.prog_guard;
              assume_guard = step.assume_guard;
              guarantee_guard = step.guarantee_guard;
            }
      | Some merged ->
          Hashtbl.replace tbl key
            { merged with prog_guard = Fo_simplifier.simplify_fo (FOr (merged.prog_guard, step.prog_guard)) })
    analysis.exploration.steps;
  Hashtbl.fold (fun _ step acc -> step :: acc) tbl []
  |> List.sort (fun a b ->
         compare
           ( string_of_state a.src,
             string_of_state a.dst,
             string_of_step_class a.step_class,
             pretty_product_formula a.prog_guard )
         ( string_of_state b.src,
             string_of_state b.dst,
             string_of_step_class b.step_class,
             pretty_product_formula b.prog_guard ))

let product_edge_visual ~(analysis : Product_analysis.analysis) (step : merged_product_edge) :
    product_edge_visual =
  let src_live =
    step.src.assume_state <> analysis.assume_bad_idx
    && step.src.guarantee_state <> analysis.guarantee_bad_idx
  in
  let dst_assume_bad =
    analysis.assume_bad_idx >= 0 && step.dst.assume_state = analysis.assume_bad_idx
  in
  let dst_guarantee_bad =
    analysis.guarantee_bad_idx >= 0 && step.dst.guarantee_state = analysis.guarantee_bad_idx
  in
  if not src_live then
    { color = "#b8b8b8"; style = "dashed"; category = "from bad state" }
  else if dst_assume_bad then
    { color = "#c78a2c"; style = "dashed"; category = "to A_bad" }
  else if dst_guarantee_bad then
    { color = "#c0392b"; style = "solid"; category = "to G_bad" }
  else
    { color = "#222222"; style = "solid"; category = "live to live" }

let render_product_dot ~(node_name : ident) (analysis : Product_analysis.analysis) =
  let buf = Buffer.create 4096 in
  let state_indices = product_state_index_map analysis.exploration.states in
  let is_live_product_state (st : PT.product_state) =
    st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx
  in
  let should_annotate_step (step : merged_product_edge) =
    is_live_product_state step.src
    && (analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx)
  in
  let transition_details_rev = ref [] in
  let transition_alias_of_detail =
    let tbl = Hashtbl.create 64 in
    let next = ref 1 in
    fun detail ->
      match Hashtbl.find_opt tbl detail with
      | Some alias -> alias
      | None ->
          let alias = tau_alias !next in
          incr next;
          Hashtbl.add tbl detail alias;
          transition_details_rev := (alias, detail) :: !transition_details_rev;
          alias
  in
  Buffer.add_string buf "digraph Product {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=b;\n";
  Buffer.add_string buf "  labeljust=l;\n";
  Buffer.add_string buf "  fontsize=10;\n";
  Buffer.add_string buf "  fontname=\"Helvetica\";\n";
  Buffer.add_string buf
    "  node [shape=box,style=\"rounded,filled\",penwidth=1.4,fontname=\"Helvetica\",fontsize=11,margin=0.12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=11,penwidth=1.25,arrowsize=0.75];\n";
  List.iter
    (fun st ->
      let fill, border = product_node_fill st ~analysis in
      let idx = Hashtbl.find state_indices st in
      Buffer.add_string buf
        (Printf.sprintf "  %s [fillcolor=\"%s\",color=\"%s\",label=\"%s\"];\n"
           (node_id_of_state st) fill border
           (escape_dot_label
              (Printf.sprintf "P%s\\n%s" (product_subscript_digits idx)
                 (pretty_product_state st ~analysis)))))
    analysis.exploration.states;
  let seen_edges = Hashtbl.create 64 in
  let merged_steps = merge_product_steps_for_dot analysis in
  List.iter
    (fun (step : merged_product_edge) ->
      let visual = product_edge_visual ~analysis step in
      let edge_label =
        if should_annotate_step step then
          let edge_detail =
            Printf.sprintf "P: %s\nA: %s\nG: %s"
              (pretty_plain_dot_formula step.prog_guard)
              (pretty_plain_dot_formula step.assume_guard)
              (pretty_plain_dot_formula step.guarantee_guard)
          in
          transition_alias_of_detail edge_detail
        else ""
      in
      let key =
        Printf.sprintf "%s|%s|%s|%s|%s" (node_id_of_state step.src) (node_id_of_state step.dst)
          visual.color visual.style edge_label
      in
      if not (Hashtbl.mem seen_edges key) then (
        Hashtbl.add seen_edges key ();
        Buffer.add_string buf
          (if edge_label = "" then
             Printf.sprintf "  %s -> %s [color=\"%s\",style=\"%s\"];\n"
               (node_id_of_state step.src) (node_id_of_state step.dst) visual.color visual.style
           else
             Printf.sprintf "  %s -> %s [color=\"%s\",style=\"%s\",xlabel=\"%s\"];\n"
               (node_id_of_state step.src) (node_id_of_state step.dst) visual.color visual.style
               (escape_dot_label edge_label))))
    merged_steps;
  Buffer.add_string buf
    "  legend_product [shape=plaintext,margin=0.1,label=<\n";
  Buffer.add_string buf "    <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n";
  Buffer.add_string buf
    "      <TR><TD COLSPAN=\"2\" ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\"><B>Edge categories</B></FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#222222\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">live to live</FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#c0392b\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to G_bad</FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#c78a2c\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to A_bad</FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#b8b8b8\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">from bad state</FONT></TD></TR>\n";
  Buffer.add_string buf "    </TABLE>>];\n";
  begin
    match List.rev analysis.exploration.states with
    | last_state :: _ ->
        Buffer.add_string buf
          (Printf.sprintf "  %s -> legend_product [style=invis,weight=0];\n"
             (node_id_of_state last_state))
    | [] -> ()
  end;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let render_product_dot_explicit ~(node_name : ident) (analysis : Product_analysis.analysis) =
  let buf = Buffer.create 4096 in
  let state_indices = product_state_index_map analysis.exploration.states in
  let is_live_product_state (st : PT.product_state) =
    st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx
  in
  let should_annotate_step (step : PT.product_step) =
    is_live_product_state step.src
    && (analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx)
  in
  let transition_details_rev = ref [] in
  let next = ref 1 in
  Buffer.add_string buf "digraph Product {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=b;\n";
  Buffer.add_string buf "  labeljust=l;\n";
  Buffer.add_string buf "  fontsize=10;\n";
  Buffer.add_string buf "  fontname=\"Helvetica\";\n";
  Buffer.add_string buf
    "  node [shape=box,style=\"rounded,filled\",penwidth=1.4,fontname=\"Helvetica\",fontsize=11,margin=0.12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=11,penwidth=1.25,arrowsize=0.75];\n";
  List.iter
    (fun st ->
      let fill, border = product_node_fill st ~analysis in
      let idx = Hashtbl.find state_indices st in
      Buffer.add_string buf
        (Printf.sprintf "  %s [fillcolor=\"%s\",color=\"%s\",label=\"%s\"];\n"
           (node_id_of_state st) fill border
           (escape_dot_label
              (Printf.sprintf "P%s\\n%s" (product_subscript_digits idx)
                 (pretty_product_state st ~analysis)))))
    analysis.exploration.states;
  List.iter
    (fun (step : PT.product_step) ->
      let visual =
        product_edge_visual ~analysis
          {
            src = step.src;
            dst = step.dst;
            step_class = step.step_class;
            prog_guard = step.prog_guard;
            assume_guard = step.assume_guard;
            guarantee_guard = step.guarantee_guard;
          }
      in
      let edge_label =
        if should_annotate_step step then (
          let alias = tau_alias !next in
          incr next;
          let detail =
            Printf.sprintf "P: %s\nA: %s\nG: %s"
              (pretty_plain_dot_formula step.prog_guard)
              (pretty_plain_dot_formula step.assume_guard)
              (pretty_plain_dot_formula step.guarantee_guard)
          in
          transition_details_rev := (alias, detail) :: !transition_details_rev;
          alias)
        else ""
      in
      if edge_label = "" then
        Buffer.add_string buf
          (Printf.sprintf "  %s -> %s [color=\"%s\",style=\"%s\"];\n"
             (node_id_of_state step.src) (node_id_of_state step.dst) visual.color visual.style)
      else (
        let mid_id = Printf.sprintf "edge_mid_%s" (String.lowercase_ascii edge_label) in
        Buffer.add_string buf
          (Printf.sprintf
             "  %s [shape=point,width=0.04,height=0.04,label=\"\",color=\"#ffffff\",fontcolor=\"#ffffff\"];\n"
             mid_id);
        Buffer.add_string buf
          (Printf.sprintf
             "  %s -> %s [color=\"%s\",style=\"%s\",arrowhead=\"none\",constraint=false];\n"
             (node_id_of_state step.src) mid_id visual.color visual.style);
        Buffer.add_string buf
          (Printf.sprintf
             "  %s -> %s [color=\"%s\",style=\"%s\",xlabel=\"%s\",constraint=false];\n"
             mid_id (node_id_of_state step.dst) visual.color visual.style
             (escape_dot_label edge_label))))
    analysis.exploration.steps;
  Buffer.add_string buf
    "  legend_product [shape=plaintext,margin=0.1,label=<\n";
  Buffer.add_string buf "    <TABLE BORDER=\"0\" CELLBORDER=\"0\" CELLSPACING=\"0\" CELLPADDING=\"2\">\n";
  Buffer.add_string buf
    "      <TR><TD COLSPAN=\"2\" ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\"><B>Edge categories</B></FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#222222\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">live to live</FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#c0392b\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to G_bad</FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#c78a2c\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to A_bad</FONT></TD></TR>\n";
  Buffer.add_string buf
    "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#b8b8b8\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">from bad state</FONT></TD></TR>\n";
  Buffer.add_string buf "    </TABLE>>];\n";
  begin
    match List.rev analysis.exploration.states with
    | last_state :: _ ->
        Buffer.add_string buf
          (Printf.sprintf "  %s -> legend_product [style=invis,weight=0];\n"
             (node_id_of_state last_state))
    | [] -> ()
  end;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let render_program_dot ~(node_name : ident) (node : Abs.node) =
  let buf = Buffer.create 4096 in
  let transitions_from_state = Ast_queries.transitions_from_state_fn (Abs.to_ast_node node) in
  Buffer.add_string buf "digraph ProgramAutomaton {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=t;\n";
  Buffer.add_string buf (Printf.sprintf "  label=\"%s program automaton\";\n" node_name);
  Buffer.add_string buf "  fontsize=18;\n";
  Buffer.add_string buf "  fontcolor=\"#275d38\";\n";
  Buffer.add_string buf
    "  node [shape=box,style=\"rounded,filled\",penwidth=1.6,fontname=\"Helvetica\",fontsize=12,margin=0.12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=12,penwidth=1.3,arrowsize=0.8,labeldistance=2.0,labelangle=35];\n";
  List.iter
    (fun st ->
      let fill, border =
        if st = node.semantics.sem_init_state then ("#dff3e4", "#2f7a4c") else ("#eef8f0", "#5e8f6b")
      in
      Buffer.add_string buf
        (Printf.sprintf "  p_%s [label=\"%s\",fillcolor=\"%s\",color=\"%s\",fontcolor=\"%s\"];\n"
           (escape_dot_label st) (escape_dot_label st) fill border border))
    node.semantics.sem_states;
  List.iter
    (fun st ->
      transitions_from_state st
      |> List.iter (fun (t : Ast.transition) ->
             let guard =
             match t.guard with
             | None -> "⊤"
             | Some g -> g |> iexpr_to_fo_with_atoms [] |> pretty_plain_dot_formula
             in
             Buffer.add_string buf
               (Printf.sprintf
                  "  p_%s -> p_%s [xlabel=\"%s\",color=\"#5e8f6b\",fontcolor=\"#5e8f6b\"];\n"
                  (escape_dot_label t.src) (escape_dot_label t.dst) (escape_dot_label guard))))
    node.semantics.sem_states;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let strip_braces (s : string) : string =
  let len = String.length s in
  let b = Buffer.create len in
  let rec loop i =
    if i >= len then ()
    else (
      let c = s.[i] in
      if c <> '{' && c <> '}' then Buffer.add_char b c;
      loop (i + 1))
  in
  loop 0;
  Buffer.contents b

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
        let var_start = k + 1 in
        let rec read_ident m = if m < len && is_ident_char s.[m] then read_ident (m + 1) else m in
        let var_end = read_ident var_start in
        if var_end > var_start then (
          let k_str = String.sub s j (k - j) in
          let v = String.sub s var_start (var_end - var_start) in
          if k_str = "1" then Buffer.add_string b ("pre(" ^ v ^ ")")
          else Buffer.add_string b ("pre_k(" ^ v ^ ", " ^ k_str ^ ")");
          loop var_end)
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

let compact_display_string (s : string) : string = s |> strip_braces |> rewrite_history_vars

let unicode_subscript_digits (n : int) : string =
  let map = function
    | '0' -> "₀"
    | '1' -> "₁"
    | '2' -> "₂"
    | '3' -> "₃"
    | '4' -> "₄"
    | '5' -> "₅"
    | '6' -> "₆"
    | '7' -> "₇"
    | '8' -> "₈"
    | '9' -> "₉"
    | c -> String.make 1 c
  in
  string_of_int n |> String.to_seq |> List.of_seq |> List.map map |> String.concat ""

let phi_alias (i : int) : string = "φ" ^ unicode_subscript_digits i
let tau_alias_unicode (i : int) : string = "τ" ^ unicode_subscript_digits i

let html_state_label ~state_prefix ~idx ~is_bad =
  if is_bad then Printf.sprintf "<I>%s</I><SUB>bad</SUB>" state_prefix
  else Printf.sprintf "<I>%s</I><SUB>%d</SUB>" state_prefix idx

let grouped_guard_rows grouped =
  let tbl = Hashtbl.create 16 in
  let next = ref 1 in
  grouped
  |> List.filter_map (fun (_src, guard, _dst) ->
         let formula = pretty_plain_dot_formula guard in
         if formula = "true" || Hashtbl.mem tbl formula then None
         else (
           let alias = phi_alias !next in
           incr next;
           Hashtbl.add tbl formula alias;
           Some (alias, formula)))

let split_formula_for_tex ?(max_width = 88) (formula : string) : (string * string) list =
  let formula = String.trim formula in
  let build sep latex_op =
    let pieces = split_all_on sep formula |> List.map String.trim |> List.filter (( <> ) "") in
    let rec loop acc current is_first = function
      | [] ->
          if current = "" then List.rev acc
          else
            let op = if is_first then "" else latex_op in
            List.rev ((op, current) :: acc)
      | piece :: rest ->
          if current = "" then loop acc piece is_first rest
          else
            let candidate = current ^ sep ^ piece in
            if String.length candidate <= max_width then loop acc candidate is_first rest
            else
              let op = if is_first then "" else latex_op in
              loop ((op, current) :: acc) piece false rest
    in
    match pieces with
    | [] -> []
    | first :: rest -> loop [] first true rest
  in
  if String.length formula <= max_width then [ ("", formula) ]
  else
    let by_or = build " ∨ " "\\lor" in
    if List.length by_or > 1 then by_or
    else
      let by_and = build " ∧ " "\\land" in
      if List.length by_and > 1 then by_and else [ ("", formula) ]

let latexify_formula (s : string) : string =
  s
  |> replace_all ~pattern:"φ₁" ~by:"\\phi_{1}"
  |> replace_all ~pattern:"φ₂" ~by:"\\phi_{2}"
  |> replace_all ~pattern:"φ₃" ~by:"\\phi_{3}"
  |> replace_all ~pattern:"φ₄" ~by:"\\phi_{4}"
  |> replace_all ~pattern:"φ₅" ~by:"\\phi_{5}"
  |> replace_all ~pattern:"φ₆" ~by:"\\phi_{6}"
  |> replace_all ~pattern:"φ₇" ~by:"\\phi_{7}"
  |> replace_all ~pattern:"φ₈" ~by:"\\phi_{8}"
  |> replace_all ~pattern:"φ₉" ~by:"\\phi_{9}"
  |> replace_all ~pattern:"⊤" ~by:"\\top"
  |> replace_all ~pattern:"⊥" ~by:"\\bot"
  |> replace_all ~pattern:"¬" ~by:"\\neg "
  |> replace_all ~pattern:" ∧ " ~by:" \\land "
  |> replace_all ~pattern:" ∨ " ~by:" \\lor "
  |> replace_all ~pattern:" → " ~by:" \\rightarrow "
  |> replace_all ~pattern:"pre_k(" ~by:"\\mathsf{pre}_k("
  |> replace_all ~pattern:"pre(" ~by:"\\mathsf{pre}("

let latexify_alias (s : string) : string =
  s
  |> replace_all ~pattern:"φ₁" ~by:"\\phi_{1}"
  |> replace_all ~pattern:"φ₂" ~by:"\\phi_{2}"
  |> replace_all ~pattern:"φ₃" ~by:"\\phi_{3}"
  |> replace_all ~pattern:"φ₄" ~by:"\\phi_{4}"
  |> replace_all ~pattern:"φ₅" ~by:"\\phi_{5}"
  |> replace_all ~pattern:"φ₆" ~by:"\\phi_{6}"
  |> replace_all ~pattern:"φ₇" ~by:"\\phi_{7}"
  |> replace_all ~pattern:"φ₈" ~by:"\\phi_{8}"
  |> replace_all ~pattern:"φ₉" ~by:"\\phi_{9}"
  |> replace_all ~pattern:"τ₁" ~by:"\\tau_{1}"
  |> replace_all ~pattern:"τ₂" ~by:"\\tau_{2}"
  |> replace_all ~pattern:"τ₃" ~by:"\\tau_{3}"
  |> replace_all ~pattern:"τ₄" ~by:"\\tau_{4}"
  |> replace_all ~pattern:"τ₅" ~by:"\\tau_{5}"
  |> replace_all ~pattern:"τ₆" ~by:"\\tau_{6}"
  |> replace_all ~pattern:"τ₇" ~by:"\\tau_{7}"
  |> replace_all ~pattern:"τ₈" ~by:"\\tau_{8}"
  |> replace_all ~pattern:"τ₉" ~by:"\\tau_{9}"

let render_tex_array rows =
  "\\[\n\\begin{array}{lcl}\n" ^ String.concat "\n" rows ^ "\n\\end{array}\n\\]\n"

let render_automaton_tex grouped =
  let rows = grouped_guard_rows grouped in
  let last_row = List.length rows - 1 in
  let rendered_rows =
    rows
    |> List.mapi (fun idx (alias, formula) ->
           let alias = latexify_alias alias in
           let pieces =
             split_formula_for_tex formula
             |> List.map (fun (op, piece) -> (op, latexify_formula piece))
           in
           match pieces with
           | [] -> Printf.sprintf "%s &::=&" alias
           | (op0, first) :: rest ->
               let first_body = if op0 = "" then first else op0 ^ " " ^ first in
               String.concat "\n"
                 ((Printf.sprintf "%s &::=& %s%s" alias first_body
                     (if rest = [] && idx = last_row then "" else " \\\\"))
                 :: List.mapi
                      (fun j (op, piece) ->
                        let suffix =
                          if idx = last_row && j = List.length rest - 1 then "" else " \\\\"
                        in
                        let body = if op = "" then piece else op ^ " " ^ piece in
                        Printf.sprintf " & & %s%s" body suffix)
                      rest))
  in
  render_tex_array rendered_rows

let render_automaton_text ~prefix labels grouped =
  let state_lines = render_automaton_lines ~prefix labels in
  let guard_lines =
    grouped_guard_rows grouped
    |> List.map (fun (alias, formula) ->
           let wrapped = wrap_formula_lines formula in
           match wrapped with
           | [] -> alias ^ " ::= "
           | first :: rest ->
               String.concat "\n"
                 ((Printf.sprintf "%s ::= %s" alias first)
                 :: List.map (fun line -> String.make (String.length alias + 5) ' ' ^ line) rest))
  in
  String.concat "\n"
    (state_lines
    @
    if guard_lines = [] then []
    else [ ""; prefix ^ " transition guards:" ] @ guard_lines)

let render_product_tex (analysis : Product_analysis.analysis) =
  let details_rev = ref [] in
  let alias_of_detail =
    let tbl = Hashtbl.create 64 in
    let next = ref 1 in
    fun detail ->
      match Hashtbl.find_opt tbl detail with
      | Some alias -> alias
      | None ->
          let alias = tau_alias_unicode !next in
          incr next;
          Hashtbl.add tbl detail alias;
          details_rev := (alias, detail) :: !details_rev;
          alias
  in
  let merged_steps = merge_product_steps_for_dot analysis in
  List.iter
    (fun (step : merged_product_edge) ->
      let src_live =
        step.src.assume_state <> analysis.assume_bad_idx
        && step.src.guarantee_state <> analysis.guarantee_bad_idx
      in
      let dst_assume_bad =
        analysis.assume_bad_idx >= 0 && step.dst.assume_state = analysis.assume_bad_idx
      in
      if src_live && not dst_assume_bad then
        ignore
          (alias_of_detail
             [
               ("\\mathrm{P}:", pretty_plain_dot_formula step.prog_guard);
               ("\\mathrm{A}:", pretty_plain_dot_formula step.assume_guard);
               ("\\mathrm{G}:", pretty_plain_dot_formula step.guarantee_guard);
             ]))
    merged_steps;
  let details = List.rev !details_rev in
  let last_row = List.length details - 1 in
  let rendered_rows =
    details
    |> List.mapi (fun idx (alias, detail) ->
           let alias = latexify_alias alias in
           let body_lines =
             detail
             |> List.concat_map (fun (label, formula) ->
                    let parts = split_formula_for_tex formula in
                    match parts with
                    | [] -> [ label ]
                    | (op0, first) :: rest ->
                        let first_text =
                          let piece = latexify_formula first in
                          if op0 = "" then label ^ " " ^ piece else label ^ " " ^ op0 ^ " " ^ piece
                        in
                        first_text
                        :: List.map
                             (fun (op, piece) ->
                               let piece = latexify_formula piece in
                               if op = "" then piece else op ^ " " ^ piece)
                             rest)
           in
           match body_lines with
           | [] -> Printf.sprintf "%s &::=&" alias
           | first :: rest ->
               String.concat "\n"
                 ((Printf.sprintf "%s &::=& %s%s" alias first
                     (if rest = [] && idx = last_row then "" else " \\\\"))
                 :: List.mapi
                      (fun j piece ->
                        let suffix =
                          if idx = last_row && j = List.length rest - 1 then "" else " \\\\"
                        in
                        Printf.sprintf " & & %s%s" piece suffix)
                      rest))
  in
  render_tex_array rendered_rows

let render_product_tex_explicit (analysis : Product_analysis.analysis) =
  let details =
    analysis.exploration.steps
    |> List.filter_map (fun (step : PT.product_step) ->
           let src_live =
             step.src.assume_state <> analysis.assume_bad_idx
             && step.src.guarantee_state <> analysis.guarantee_bad_idx
           in
           let dst_assume_bad =
             analysis.assume_bad_idx >= 0 && step.dst.assume_state = analysis.assume_bad_idx
           in
           if src_live && not dst_assume_bad then
             Some
               [
                 ("\\mathrm{P}:", pretty_plain_dot_formula step.prog_guard);
                 ("\\mathrm{A}:", pretty_plain_dot_formula step.assume_guard);
                 ("\\mathrm{G}:", pretty_plain_dot_formula step.guarantee_guard);
               ]
           else None)
    |> List.mapi (fun idx detail -> (latexify_alias (tau_alias_unicode (idx + 1)), detail))
  in
  let last_row = List.length details - 1 in
  let rendered_rows =
    details
    |> List.mapi (fun idx (alias, detail) ->
           let body_lines =
             detail
             |> List.concat_map (fun (label, formula) ->
                    let parts = split_formula_for_tex formula in
                    match parts with
                    | [] -> [ label ]
                    | (op0, first) :: rest ->
                        let first_text =
                          let piece = latexify_formula first in
                          if op0 = "" then label ^ " " ^ piece else label ^ " " ^ op0 ^ " " ^ piece
                        in
                        first_text
                        :: List.map
                             (fun (op, piece) ->
                               let piece = latexify_formula piece in
                               if op = "" then piece else op ^ " " ^ piece)
                             rest)
           in
           match body_lines with
           | [] -> Printf.sprintf "%s &::=&" alias
           | first :: rest ->
               String.concat "\n"
                 ((Printf.sprintf "%s &::=& %s%s" alias first
                     (if rest = [] && idx = last_row then "" else " \\\\"))
                 :: List.mapi
                      (fun j piece ->
                        let suffix =
                          if idx = last_row && j = List.length rest - 1 then "" else " \\\\"
                        in
                        Printf.sprintf " & & %s%s" piece suffix)
                      rest))
  in
  render_tex_array rendered_rows

let render_automaton_dot ~graph_name ~prefix ~state_prefix ~labels ~grouped ~atom_map_exprs =
  let buf = Buffer.create 1024 in
  let (node_fill, node_border, title_color, edge_color) =
    if prefix = "a" then
      ("#e8f3ea", "#2f6b3b", "#2f6b3b", "#2f6b3b")
    else
      ("#f6eadf", "#8b5a2b", "#8b5a2b", "#8b5a2b")
  in
  let bad_fill = "#f6d7d7" in
  let bad_border = "#a53030" in
  let alias_of_guard =
    let tbl = Hashtbl.create 16 in
    let next = ref 1 in
    fun guard_s ->
      match Hashtbl.find_opt tbl guard_s with
      | Some alias -> alias
      | None ->
          let alias = phi_alias !next in
          incr next;
          Hashtbl.add tbl guard_s alias;
          alias
  in
  Buffer.add_string buf (Printf.sprintf "digraph %s {\n" graph_name);
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=b;\n";
  Buffer.add_string buf "  labeljust=l;\n";
  Buffer.add_string buf "  fontsize=18;\n";
  Buffer.add_string buf
    (Printf.sprintf "  fontcolor=\"%s\";\n" title_color);
  Buffer.add_string buf
    "  node [shape=circle,style=filled,penwidth=1.6,fontname=\"Helvetica\",fontsize=12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=12,penwidth=1.3,arrowsize=0.8,labeldistance=2.0,labelangle=35];\n";
  List.iteri
    (fun i lbl ->
      let is_bad = compact_display_string lbl = "false" in
      let fill = if is_bad then bad_fill else if i = 0 then "#d9e8ff" else node_fill in
      let border = if is_bad then bad_border else if i = 0 then "#3f6fb5" else node_border in
      Buffer.add_string buf
        (Printf.sprintf
           "  %s%d [label=<%s>,fillcolor=\"%s\",color=\"%s\",fontcolor=\"%s\"];\n"
           prefix i (html_state_label ~state_prefix ~idx:i ~is_bad) fill border border))
    labels;
  List.iter
    (fun (src, guard, dst) ->
      let formula =
        let _ = atom_map_exprs in
        pretty_plain_dot_formula guard
      in
      let alias = if formula = "true" then "⊤" else alias_of_guard formula in
      let dst_is_bad =
        match List.nth_opt labels dst with
        | Some lbl -> compact_display_string lbl = "false"
        | None -> false
      in
      let this_edge_color = if dst_is_bad then bad_border else edge_color in
      Buffer.add_string buf
        (Printf.sprintf
           "  %s%d -> %s%d [xlabel=\"%s\",color=\"%s\",fontcolor=\"%s\"];\n"
           prefix src prefix dst (escape_dot_label alias) this_edge_color this_edge_color))
    grouped;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let render ~(node_name : ident) ~(analysis : Product_analysis.analysis) : rendered =
  let guarantee_automaton_lines =
    render_automaton_text ~prefix:"G" analysis.guarantee_state_labels analysis.guarantee_grouped_edges
    |> String.split_on_char '\n'
    |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
  in
  let assume_automaton_lines =
    render_automaton_text ~prefix:"A" analysis.assume_state_labels analysis.assume_grouped_edges
    |> String.split_on_char '\n'
    |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
  in
  {
    guarantee_automaton_lines;
    assume_automaton_lines;
    guarantee_automaton_tex = render_automaton_tex analysis.guarantee_grouped_edges;
    assume_automaton_tex = render_automaton_tex analysis.assume_grouped_edges;
    product_tex = render_product_tex analysis;
    product_tex_explicit = render_product_tex_explicit analysis;
    product_lines = render_product_lines ~node_name analysis;
    obligations_lines = render_obligation_lines ~node_name analysis;
    prune_lines = render_prune_lines ~node_name analysis;
    guarantee_automaton_dot =
      render_automaton_dot ~graph_name:"GuaranteeAutomaton" ~prefix:"g" ~state_prefix:"G"
        ~labels:analysis.guarantee_state_labels ~grouped:analysis.guarantee_grouped_edges
        ~atom_map_exprs:analysis.guarantee_atom_map_exprs;
    assume_automaton_dot =
      render_automaton_dot ~graph_name:"AssumeAutomaton" ~prefix:"a" ~state_prefix:"A"
        ~labels:analysis.assume_state_labels ~grouped:analysis.assume_grouped_edges
        ~atom_map_exprs:analysis.assume_atom_map_exprs;
    product_dot = render_product_dot ~node_name analysis;
    product_dot_explicit = render_product_dot_explicit ~node_name analysis;
  }

let render_guarantee_automaton ~(node_name : ident) ~(analysis : Product_analysis.analysis) :
    string * string =
  let dot =
    render_automaton_dot ~graph_name:"GuaranteeAutomaton" ~prefix:"g" ~state_prefix:"G"
      ~labels:analysis.guarantee_state_labels ~grouped:analysis.guarantee_grouped_edges
      ~atom_map_exprs:analysis.guarantee_atom_map_exprs
  in
  let labels =
    render_automaton_text ~prefix:"G" analysis.guarantee_state_labels analysis.guarantee_grouped_edges
    |> String.split_on_char '\n'
    |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
    |> String.concat "\n"
  in
  (dot, labels)

let render_program_automaton ~(node_name : ident) ~(node : Abs.node) : string * string =
  let dot = render_program_dot ~node_name node in
  let labels = render_program_lines ~node_name node |> String.concat "\n" in
  (dot, labels)
