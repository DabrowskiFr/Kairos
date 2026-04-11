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

(* This module produces Graphviz DOT representations of the three automata
   involved in contract verification: the require automaton, the ensures automaton,
   and the synchronised product of the two with the program control automaton.
   Each public function returns a [graph] value containing both a DOT string
   (for rendering) and a text [labels] string (for diagnostics). *)

open Core_syntax
open Ast
open Core_syntax_builders
open Generated_names
open Temporal_support
open Logic_pretty
open Fo_specs

module PT = Product_types

(* Calls the Z3-based formula simplifier; returns the formula unchanged on failure. *)
let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

(* Public result type: a Graphviz DOT source paired with human-readable
   text labels (one line per state or transition) for diagnostic output. *)
type graph = {
  dot : string;
  labels : string;
}

(* ------------------------------------------------------------------ *)
(* DOT / HTML escaping and low-level emission primitives                *)
(* ------------------------------------------------------------------ *)

(* Escapes double-quotes and newlines so the string is safe inside a DOT plain label. *)
let escape_dot_label (s : string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\n' -> Buffer.add_string b "\\n"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

(* Escapes [& < > ] and double-quotes so the string is safe inside a Graphviz HTML label. *)
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

(* Converts newlines to [<BR ALIGN="LEFT"/>] so multi-line formulas render
   correctly inside an HTML label table cell. *)
let html_of_multiline_formula (s : string) : string =
  let escaped = escape_html_label s in
  let b = Buffer.create (String.length escaped) in
  String.iter
    (function
      | '\n' -> Buffer.add_string b "<BR ALIGN=\"LEFT\"/>"
      | c -> Buffer.add_char b c)
    escaped;
  Buffer.contents b

(* Appends HTML [<TR>] rows for a two-column alias table (alias | formula)
   headed by [title]. Does nothing when [defs] is empty. *)
let add_formula_legend_rows_html buf ~title ~defs =
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
             (escape_html_label alias) (html_of_multiline_formula formula)))
      defs)

(* Emits a [rank=sink] subgraph containing a plaintext HTML-table node that
   acts as a floating legend. An invisible edge from [anchor_id] keeps the
   legend anchored near the graph body. *)
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

(* Emits a single DOT edge with a plain-text label, colour and style. *)
let add_labeled_edge buf ~src_id ~dst_id ~label ~color ~style =
  Buffer.add_string buf
    (Printf.sprintf "  %s -> %s [label=\"%s\",color=\"%s\",fontcolor=\"%s\",style=\"%s\"];\n"
       src_id dst_id (escape_dot_label label) color color style)

(* ------------------------------------------------------------------ *)
(* Formula display pipeline                                             *)
(* ------------------------------------------------------------------ *)

(* Human-readable display of a product state: "(prog, A_i, G_j)". *)
let string_of_state (s : PT.product_state) : string =
  Printf.sprintf "(%s, A%d, G%d)" s.prog_state s.assume_state s.guarantee_state

(* Short label used in text diagnostic output to classify a product step. *)
let string_of_step_class = function
  | PT.Safe -> "safe"
  | PT.Bad_assumption -> "bad_A"
  | PT.Bad_guarantee -> "bad_G"

(* Compact "i->j" notation for an automaton edge, used in text diagnostics. *)
let string_of_edge ((src, _guard, dst) : PT.automaton_edge) : string =
  Printf.sprintf "%d->%d" src dst

let obligation_formula (step : PT.product_step) : Fo_formula.t =
  Fo_formula.FNot
    (Fo_formula.FAnd
       ( step.prog_guard,
         Fo_formula.FAnd (step.assume_guard, step.guarantee_guard) ))

(* Produces one text line per automaton state: "A0 = <formula>". *)
let render_automaton_lines ~prefix labels =
  labels |> List.mapi (fun i lbl -> Printf.sprintf "%s%d = %s" prefix i lbl)

(* Removes the curly braces that the formula printer emits around sub-terms. *)
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

(* Rewrites internal history-variable names to readable notation:
   [__pre_k1_x] → [pre(x)],  [__pre_k3_x] → [pre_k(x, 3)]. *)
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

(* Converts a formula to a clean display string: serialises, strips braces,
   and rewrites history variables. *)
let pretty_product_formula (f : Fo_formula.t) : string =
  f |> string_of_fo |> strip_braces |> rewrite_history_vars

(* Replaces every occurrence of [pattern] in [s] with [by].
   Unlike [String.split_on_char], works on multi-character patterns. *)
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

(* Like [replace_all] but only replaces [word] when it appears at an identifier
   boundary (not surrounded by [a-zA-Z0-9_]), preventing false matches inside
   longer identifiers such as [trueValue] or [falsehood]. *)
let replace_word ~word ~by s =
  let wlen = String.length word in
  let slen = String.length s in
  let is_ident_char c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'
  in
  let buf = Buffer.create slen in
  let rec loop i =
    if i >= slen then ()
    else if i + wlen <= slen && String.sub s i wlen = word then
      let before_ok = i = 0 || not (is_ident_char s.[i - 1]) in
      let after_ok = i + wlen >= slen || not (is_ident_char s.[i + wlen]) in
      if before_ok && after_ok then (
        Buffer.add_string buf by;
        loop (i + wlen))
      else (
        Buffer.add_char buf s.[i];
        loop (i + 1))
    else (
      Buffer.add_char buf s.[i];
      loop (i + 1))
  in
  loop 0;
  Buffer.contents buf

(* Replaces ASCII logic/arithmetic operators with Unicode equivalents for
   readability in DOT labels: [<>]→[≠], [->]→[→], [and]→[∧], [or]→[∨],
   [not]→[¬], [true]→[⊤], [false]→[⊥].  Uses word-boundary replacement for
   [true]/[false] to avoid corrupting identifiers that contain those words. *)
let mathify_formula (s : string) : string =
  s
  |> replace_all ~pattern:"<>" ~by:"≠"
  |> replace_all ~pattern:" -> " ~by:" → "
  |> replace_all ~pattern:" and " ~by:" ∧ "
  |> replace_all ~pattern:" or " ~by:" ∨ "
  |> replace_all ~pattern:"not " ~by:"¬"
  |> replace_word ~word:"true" ~by:"⊤"
  |> replace_word ~word:"false" ~by:"⊥"

(* Full formula-to-display-string pipeline for plain DOT labels:
   serialise → strip braces → rewrite history vars → replace operators with Unicode. *)
let pretty_plain_dot_formula (f : Fo_formula.t) : string =
  f |> pretty_product_formula |> mathify_formula

(* Builds the text-label lines for a program automaton: one line per state
   and one line per transition, prefixed with the node name. Used as the
   [labels] field of the returned [graph]. *)
let render_program_lines ~(node_name : ident) (node : Ast.node) =
  let sem = node.semantics in
  let states =
    sem.sem_states
    |> List.map (fun st -> Printf.sprintf "[%s] P[%s]" node_name st)
  in
  let transitions =
    sem.sem_trans
    |> List.map (fun (t : Ast.transition) ->
           let guard =
             match t.guard with
             | None -> "⊤"
             | Some g -> g |> expr_to_fo_with_atoms [] |> pretty_plain_dot_formula
           in
           Printf.sprintf "[%s] P[%s -> %s] %s" node_name t.src t.dst guard)
  in
  states @ transitions

(* Builds the text-label lines for the product automaton: one line per product
   state and one line per product step, each annotated with the three component
   guards (program, assume, guarantee).  Used as the [labels] field. *)
let render_product_lines ~(node_name : ident) (analysis : Temporal_automata.node_data) =
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

(* Generates a DOT-safe node identifier from a product state; used as the
   Graphviz node name in the product graph. *)
let node_id_of_state (s : PT.product_state) : string =
  Printf.sprintf "n_%s_a%d_g%d" s.prog_state s.assume_state s.guarantee_state

(* Builds a hashtable mapping each product state to its position index in the
   state list; used to produce compact subscripted node labels (P₀, P₁, …). *)
let product_state_index_map (states : PT.product_state list) =
  let tbl = Hashtbl.create 32 in
  List.iteri (fun i st -> Hashtbl.replace tbl st i) states;
  tbl

(* Converts a non-negative integer to its Unicode subscript representation
   (e.g. [12] → ["₁₂"]) for typographically compact node labels. *)
let subscript_digits (n : int) : string =
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

(* Returns the display label for a single automaton state: [prefix_bad] for the
   error state (when [bad_idx >= 0 && idx = bad_idx]), or [prefix] followed by
   subscript digits otherwise. *)
let pretty_aut_state ~prefix ~idx ~bad_idx =
  if bad_idx >= 0 && idx = bad_idx then Printf.sprintf "%s_bad" prefix
  else prefix ^ subscript_digits idx

(* Formats a product state as a human-readable triple "(prog, Aᵢ, Gⱼ)", with
   the bad-state suffix applied where relevant. *)
let pretty_product_state (s : PT.product_state) ~(analysis : Temporal_automata.node_data) : string =
  Printf.sprintf "(%s, %s, %s)" s.prog_state
    (pretty_aut_state ~prefix:"A" ~idx:s.assume_state ~bad_idx:analysis.assume_bad_idx)
    (pretty_aut_state ~prefix:"G" ~idx:s.guarantee_state ~bad_idx:analysis.guarantee_bad_idx)

(* Edge colours shared between [product_edge_visual] (DOT output) and the
   category legend rows in [emit_product_dot]. *)
let clr_live_to_live = "#222222"
let clr_to_gbad      = "#c0392b"
let clr_to_abad      = "#c78a2c"
let clr_from_bad     = "#b8b8b8"

(* Returns [(fill_color, border_color)] for a product-state node: blue for the
   initial state, red for a G_bad state, orange for an A_bad state, and grey
   otherwise. *)
let product_node_fill (s : PT.product_state) ~(analysis : Temporal_automata.node_data) =
  if PT.compare_state s analysis.exploration.initial_state = 0 then ("#d9e8ff", "#3f6fb5")
  else if analysis.guarantee_bad_idx >= 0 && s.guarantee_state = analysis.guarantee_bad_idx then
    ("#f6d7d7", "#a53030")
  else if analysis.assume_bad_idx >= 0 && s.assume_state = analysis.assume_bad_idx then
    ("#f9ead7", "#b26a1f")
  else ("white", "#6b7280")

(* Returns the i-th transition alias symbol: τ₁, τ₂, … Used to abbreviate
   long product-edge formulas in the legend. *)
let tau_alias (i : int) : string = "τ" ^ subscript_digits i

(* Splits [s] on every occurrence of the multi-character separator [sep],
   returning the list of pieces (analogous to [String.split_on_char] but for
   arbitrary separators). *)
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

(* Soft-wraps a formula string into a list of lines no wider than [max_width]
   characters.  Prefers splitting on [∨] over [∧] so that conjuncts are kept
   together when possible.  Returns a singleton list when the string is short
   enough or contains no splittable operators. *)
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

(* Intermediate representation for a product-graph edge after merging parallel
   steps: steps that share the same (src, dst, class, assume-edge, guarantee-edge,
   assume-guard, guarantee-guard) are collapsed into one entry whose [prog_guard]
   is the disjunction of all individual program guards. *)
type merged_product_edge = {
  src : PT.product_state;
  dst : PT.product_state;
  step_class : PT.step_class;
  prog_guard : Fo_formula.t;
  assume_guard : Fo_formula.t;
  guarantee_guard : Fo_formula.t;
}

(* Visual attributes for a product-graph edge (colour, stroke style, and a
   human-readable category string for the legend). *)
type product_edge_visual = {
  color : string;
  style : string;
  category : string;
}

(* Groups product steps by (src, dst, class, assume-edge, guarantee-edge,
   assume-guard, guarantee-guard), merging their program guards into a
   disjunction so that parallel program transitions appear as a single DOT edge.
   The result is sorted for deterministic DOT output. *)
let merge_product_steps_for_dot (analysis : Temporal_automata.node_data) : merged_product_edge list =
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
            { merged with prog_guard = simplify_fo (FOr (merged.prog_guard, step.prog_guard)) })
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

(* Determines the visual style of a product edge based on the liveness of its
   endpoints: edges leaving a bad state are grey/dashed; edges to A_bad are
   orange/dashed; edges to G_bad are red/solid; live-to-live edges are
   dark/solid. *)
let product_edge_visual ~(analysis : Temporal_automata.node_data) (step : merged_product_edge) :
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
    { color = clr_from_bad; style = "dashed"; category = "from bad state" }
  else if dst_assume_bad then
    { color = clr_to_abad; style = "dashed"; category = "to A_bad" }
  else if dst_guarantee_bad then
    { color = clr_to_gbad; style = "solid"; category = "to G_bad" }
  else
    { color = clr_live_to_live; style = "solid"; category = "live to live" }

(* ------------------------------------------------------------------ *)
(* Ready-to-emit data types                                             *)
(* ------------------------------------------------------------------ *)

(* A fully-resolved node descriptor ready for emission to a DOT buffer.
   [node_label] is either a plain string or an HTML label fragment. *)
type ready_node = {
  node_id       : string;
  node_label    : [ `Plain of string | `Html of string ];
  node_fill     : string;
  node_border   : string;
  node_fontcolor: string option;
}

(* A fully-resolved edge descriptor ready for emission to a DOT buffer. *)
type ready_edge = {
  edge_src   : string;
  edge_dst   : string;
  edge_label : string;
  edge_color : string;
  edge_style : string;
}

(* Appends a single DOT node statement to [buf], handling both plain and HTML
   label variants and the optional font-colour attribute. *)
let emit_node buf (n : ready_node) =
  let label_attr = match n.node_label with
    | `Plain s -> Printf.sprintf "label=\"%s\"" (escape_dot_label s)
    | `Html s  -> Printf.sprintf "label=<%s>" s
  in
  let fontcolor_attr = match n.node_fontcolor with
    | None   -> ""
    | Some c -> Printf.sprintf ",fontcolor=\"%s\"" c
  in
  Buffer.add_string buf
    (Printf.sprintf "  %s [fillcolor=\"%s\",color=\"%s\"%s,%s];\n"
       n.node_id n.node_fill n.node_border fontcolor_attr label_attr)

(* Appends a single DOT edge statement to [buf].  Omits the label attribute
   entirely when [edge_label] is empty so that Graphviz does not reserve space
   for it. *)
let emit_edge buf (e : ready_edge) =
  if e.edge_label = "" then
    Buffer.add_string buf
      (Printf.sprintf "  %s -> %s [color=\"%s\",style=\"%s\"];\n"
         e.edge_src e.edge_dst e.edge_color e.edge_style)
  else
    add_labeled_edge buf ~src_id:e.edge_src ~dst_id:e.edge_dst
      ~label:e.edge_label ~color:e.edge_color ~style:e.edge_style

(* Appends a floating legend subgraph (rank=sink) to [buf] listing [defs] as an
   alias table under [title].  Does nothing when [defs] is empty or [anchor]
   is [None]. *)
let emit_formula_legend buf ~legend_id ~title ~defs ~anchor =
  if defs <> [] then
    Option.iter (fun anchor_id ->
      let rows_buf = Buffer.create 256 in
      add_formula_legend_rows_html rows_buf ~title ~defs;
      add_sink_legend_block_html buf ~legend_id ~title
        ~rows_html:(Buffer.contents rows_buf) ~anchor_id)
    anchor

(* ------------------------------------------------------------------ *)
(* Product automaton                                                    *)
(* ------------------------------------------------------------------ *)

(* Pure computation phase for the product graph: derives lists of [ready_node]
   and [ready_edge] values plus a legend definition list [(alias, formula)] and
   an optional anchor node id.  No DOT is emitted here. *)
let prepare_product_graph (analysis : Temporal_automata.node_data) =
  let state_indices = product_state_index_map analysis.exploration.states in
  let is_live (st : PT.product_state) =
    st.assume_state <> analysis.assume_bad_idx
    && st.guarantee_state <> analysis.guarantee_bad_idx
  in
  let nodes =
    List.map (fun st ->
      let fill, border = product_node_fill st ~analysis in
      let idx = Hashtbl.find state_indices st in
      let label =
        Printf.sprintf "P%s\n%s" (subscript_digits idx) (pretty_product_state st ~analysis)
      in
      { node_id = node_id_of_state st; node_label = `Plain label;
        node_fill = fill; node_border = border; node_fontcolor = None })
    analysis.exploration.states
  in
  let detail_tbl = Hashtbl.create 64 in
  let detail_rev = ref [] in
  let next_alias = ref 1 in
  let alias_of_detail detail =
    match Hashtbl.find_opt detail_tbl detail with
    | Some alias -> alias
    | None ->
        let alias = tau_alias !next_alias in
        incr next_alias;
        Hashtbl.add detail_tbl detail alias;
        detail_rev := (alias, detail) :: !detail_rev;
        alias
  in
  let seen = Hashtbl.create 64 in
  let edges =
    merge_product_steps_for_dot analysis
    |> List.filter_map (fun (step : merged_product_edge) ->
         let visual = product_edge_visual ~analysis step in
         let label =
           if is_live step.src
             && (analysis.assume_bad_idx < 0
                || step.dst.assume_state <> analysis.assume_bad_idx)
           then
             alias_of_detail
               (Printf.sprintf "P: %s\nA: %s\nG: %s"
                  (pretty_plain_dot_formula step.prog_guard)
                  (pretty_plain_dot_formula step.assume_guard)
                  (pretty_plain_dot_formula step.guarantee_guard))
           else ""
         in
         let key =
           Printf.sprintf "%s|%s|%s|%s|%s"
             (node_id_of_state step.src) (node_id_of_state step.dst)
             visual.color visual.style label
         in
         if Hashtbl.mem seen key then None
         else (
           Hashtbl.add seen key ();
           Some { edge_src = node_id_of_state step.src; edge_dst = node_id_of_state step.dst;
                  edge_label = label; edge_color = visual.color; edge_style = visual.style }))
  in
  let anchor =
    match List.rev analysis.exploration.states with
    | last :: _ -> Some (node_id_of_state last)
    | [] -> None
  in
  (nodes, edges, List.rev !detail_rev, anchor)

(* Emission phase for the product graph: calls [prepare_product_graph] and
   assembles the full DOT source string, including the edge-category legend. *)
let emit_product_dot (analysis : Temporal_automata.node_data) =
  let nodes, edges, transition_defs, anchor = prepare_product_graph analysis in
  let buf = Buffer.create 2048 in
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
  List.iter (emit_node buf) nodes;
  List.iter (emit_edge buf) edges;
  let category_rows =
    let b = Buffer.create 256 in
    Buffer.add_string b (Printf.sprintf "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">live to live</FONT></TD></TR>\n" clr_live_to_live);
    Buffer.add_string b (Printf.sprintf "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">━━</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to G_bad</FONT></TD></TR>\n" clr_to_gbad);
    Buffer.add_string b (Printf.sprintf "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">to A_bad</FONT></TD></TR>\n" clr_to_abad);
    Buffer.add_string b (Printf.sprintf "        <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"%s\">┄┄</FONT></TD><TD ALIGN=\"LEFT\"><FONT POINT-SIZE=\"10\">from bad state</FONT></TD></TR>\n" clr_from_bad);
    Buffer.contents b
  in
  Option.iter (fun anchor_id ->
    let rows_buf = Buffer.create 512 in
    Buffer.add_string rows_buf category_rows;
    add_formula_legend_rows_html rows_buf ~title:"Transition formulas" ~defs:transition_defs;
    add_sink_legend_block_html buf ~legend_id:"legend_product" ~title:"Edge categories"
      ~rows_html:(Buffer.contents rows_buf) ~anchor_id)
  anchor;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

(* ------------------------------------------------------------------ *)
(* Program automaton                                                    *)
(* ------------------------------------------------------------------ *)

(* Pure computation phase for the program automaton: one [ready_node] per
   control state and one [ready_edge] per transition. No DOT is emitted here. *)
let prepare_program_graph (node : Ast.node) =
  let sem = node.semantics in
  let transitions_from_state = Ast_queries.transitions_from_state_fn node in
  let nodes =
    List.map (fun st ->
      let fill, border =
        if st = sem.sem_init_state then ("#dff3e4", "#2f7a4c") else ("#eef8f0", "#5e8f6b")
      in
      { node_id = Printf.sprintf "p_%s" (escape_dot_label st);
        node_label = `Plain st; node_fill = fill; node_border = border;
        node_fontcolor = Some border })
    sem.sem_states
  in
  let edges =
    List.concat_map (fun st ->
      transitions_from_state st
      |> List.map (fun (t : Ast.transition) ->
           let guard = match t.guard with
             | None -> "⊤"
             | Some g -> g |> expr_to_fo_with_atoms [] |> pretty_plain_dot_formula
           in
           { edge_src = Printf.sprintf "p_%s" (escape_dot_label t.src);
             edge_dst = Printf.sprintf "p_%s" (escape_dot_label t.dst);
             edge_label = guard; edge_color = "#5e8f6b"; edge_style = "solid" }))
    sem.sem_states
  in
  (nodes, edges)

(* Emission phase for the program automaton: calls [prepare_program_graph] and
   assembles the full DOT source string. *)
let emit_program_dot ~(node_name : ident) (node : Ast.node) =
  let nodes, edges = prepare_program_graph node in
  let buf = Buffer.create 1024 in
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
  List.iter (emit_node buf) nodes;
  List.iter (emit_edge buf) edges;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

(* ------------------------------------------------------------------ *)
(* Assume / Guarantee automaton                                         *)
(* ------------------------------------------------------------------ *)

(* Lightweight display string for automaton state labels (used to detect the
   "false" / bad state): strip braces and rewrite history variables, but skip
   the operator-mathification step that is only needed for DOT output. *)
let compact_display_string (s : string) : string = s |> strip_braces |> rewrite_history_vars

(* Returns the i-th guard alias symbol: φ₁, φ₂, … Used to abbreviate repeated
   transition guards in the assume/guarantee automaton legend. *)
let phi_alias (i : int) : string = "φ" ^ subscript_digits i

(* Produces an HTML fragment for an automaton state node label: italic prefix
   with a numeric subscript normally, or [prefix_bad] in italic for the bad state. *)
let html_state_label ~state_prefix ~idx ~is_bad =
  if is_bad then Printf.sprintf "<I>%s</I><SUB>bad</SUB>" state_prefix
  else Printf.sprintf "<I>%s</I><SUB>%d</SUB>" state_prefix idx

(* Assigns a unique φᵢ alias to each distinct non-trivial guard formula found in
   [grouped], returning the list of [(alias, formula)] pairs in assignment order.
   Guards that simplify to [⊤] and duplicates are silently skipped. *)
let grouped_guard_rows grouped =
  let tbl = Hashtbl.create 16 in
  let next = ref 1 in
  grouped
  |> List.filter_map (fun (_src, guard, _dst) ->
       let formula = pretty_plain_dot_formula guard in
       if formula = "⊤" || Hashtbl.mem tbl formula then None
       else (
         let alias = phi_alias !next in
         incr next;
         Hashtbl.add tbl formula alias;
         Some (alias, formula)))

(* Produces the text-label string for an assume or guarantee automaton: state
   names on the first lines, followed by a block of "φᵢ ::= formula" aliases
   for the non-trivial transition guards. *)
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
    @ if guard_lines = [] then []
      else [ ""; prefix ^ " transition guards:" ] @ guard_lines)

(* Distinguishes the two contract automata so that [prepare_automaton_graph] and
   [emit_automaton_dot] can select the right colours, prefix letters, and graph
   name without relying on magic string comparisons. *)
type automaton_kind = Assume | Guarantee

(* Pure computation phase for an assume/guarantee automaton: resolves all colours,
   node labels, edge alias strings, and the legend anchor from [kind], [labels],
   and [grouped].  Returns
   [(graph_name, title_color, prefix, nodes, edges, guard_rows, anchor)].
   No DOT is emitted here. *)
let prepare_automaton_graph ~kind ~labels ~grouped =
  let prefix, state_prefix, graph_name, node_fill, node_border, title_color, edge_color =
    match kind with
    | Assume    -> ("a", "A", "AssumeAutomaton",    "#e8f3ea", "#2f6b3b", "#2f6b3b", "#2f6b3b")
    | Guarantee -> ("g", "G", "GuaranteeAutomaton", "#f6eadf", "#8b5a2b", "#8b5a2b", "#8b5a2b")
  in
  let bad_fill = "#f6d7d7" in
  let bad_border = "#a53030" in
  let guard_rows = grouped_guard_rows grouped in
  let alias_tbl = Hashtbl.create 16 in
  List.iter (fun (alias, formula) -> Hashtbl.replace alias_tbl formula alias) guard_rows;
  let alias_of_guard s =
    match Hashtbl.find_opt alias_tbl s with Some a -> a | None -> s
  in
  let nodes =
    List.mapi (fun i lbl ->
      let is_bad = compact_display_string lbl = "false" in
      let fill = if is_bad then bad_fill else if i = 0 then "#d9e8ff" else node_fill in
      let border = if is_bad then bad_border else if i = 0 then "#3f6fb5" else node_border in
      { node_id = Printf.sprintf "%s%d" prefix i;
        node_label = `Html (html_state_label ~state_prefix ~idx:i ~is_bad);
        node_fill = fill; node_border = border; node_fontcolor = Some border })
    labels
  in
  let edges =
    List.map (fun (src, guard, dst) ->
      let formula = pretty_plain_dot_formula guard in
      let dst_is_bad = match List.nth_opt labels dst with
        | Some lbl -> compact_display_string lbl = "false"
        | None -> false
      in
      { edge_src = Printf.sprintf "%s%d" prefix src;
        edge_dst = Printf.sprintf "%s%d" prefix dst;
        edge_label = alias_of_guard formula;
        edge_color = (if dst_is_bad then bad_border else edge_color);
        edge_style = "solid" })
    grouped
  in
  let anchor = match List.length labels with
    | 0 -> None
    | n -> Some (Printf.sprintf "%s%d" prefix (n - 1))
  in
  (graph_name, title_color, prefix, nodes, edges, guard_rows, anchor)

(* Emission phase for an assume/guarantee automaton: calls
   [prepare_automaton_graph] and assembles the full DOT source string, appending
   the formula-alias legend when aliases were generated. *)
let emit_automaton_dot ~kind ~labels ~grouped =
  let graph_name, title_color, prefix, nodes, edges, guard_rows, anchor =
    prepare_automaton_graph ~kind ~labels ~grouped
  in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf (Printf.sprintf "digraph %s {\n" graph_name);
  Buffer.add_string buf "  rankdir=LR;\n";
  Buffer.add_string buf "  forcelabels=true;\n";
  Buffer.add_string buf "  labelloc=b;\n";
  Buffer.add_string buf "  labeljust=l;\n";
  Buffer.add_string buf "  fontsize=18;\n";
  Buffer.add_string buf (Printf.sprintf "  fontcolor=\"%s\";\n" title_color);
  Buffer.add_string buf
    "  node [shape=circle,style=filled,penwidth=1.6,fontname=\"Helvetica\",fontsize=12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=12,penwidth=1.3,arrowsize=0.8,labeldistance=2.0,labelangle=35];\n";
  List.iter (emit_node buf) nodes;
  List.iter (emit_edge buf) edges;
  emit_formula_legend buf ~legend_id:("legend_" ^ prefix) ~title:"Formula aliases"
    ~defs:guard_rows ~anchor;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

(* ------------------------------------------------------------------ *)
(* Public API                                                           *)
(* ------------------------------------------------------------------ *)

(* Renders the guarantee (ensures) automaton for [node_name]: a DOT graph
   showing guarantee states and their transitions, plus a text label listing
   the state invariants and guard aliases. *)
let render_ensures_automaton ~(node_name : ident) ~(analysis : Temporal_automata.node_data) : graph =
  let dot =
    emit_automaton_dot ~kind:Guarantee
      ~labels:analysis.guarantee_state_labels ~grouped:analysis.guarantee_grouped_edges
  in
  let labels =
    render_automaton_text ~prefix:"G" analysis.guarantee_state_labels analysis.guarantee_grouped_edges
    |> String.split_on_char '\n'
    |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
    |> String.concat "\n"
  in
  { dot; labels }

(* Renders the assume (require) automaton for [node_name]: same structure as
   [render_ensures_automaton] but driven by the assume-automaton data. *)
let render_require_automaton ~(node_name : ident) ~(analysis : Temporal_automata.node_data) : graph =
  let dot =
    emit_automaton_dot ~kind:Assume
      ~labels:analysis.assume_state_labels ~grouped:analysis.assume_grouped_edges
  in
  let labels =
    render_automaton_text ~prefix:"A" analysis.assume_state_labels analysis.assume_grouped_edges
    |> String.split_on_char '\n'
    |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
    |> String.concat "\n"
  in
  { dot; labels }

(* Renders the synchronised product of the program, assume, and guarantee
   automata, colour-coded by step class (live-to-live, to-G_bad, to-A_bad,
   from-bad), with a legend listing edge categories and transition formulas. *)
let render_product ~(node_name : ident) ~(analysis : Temporal_automata.node_data) : graph =
  let dot = emit_product_dot analysis in
  let labels = render_product_lines ~node_name analysis |> String.concat "\n" in
  { dot; labels }

(* Renders the program control automaton: one node per control state, one edge
   per transition with its guard as a label. *)
let render_program_automaton ~(node_name : ident) ~(node : Ast.node) : graph =
  let dot = emit_program_dot ~node_name node in
  let labels = render_program_lines ~node_name node |> String.concat "\n" in
  { dot; labels }
