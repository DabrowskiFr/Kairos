open Ast
open Ast_builders
open Support
open Automaton_core
open Automata_atoms
open Fo_specs

module PT = Product_types

type rendered = {
  guarantee_automaton_lines : string list;
  assume_automaton_lines : string list;
  product_lines : string list;
  obligations_lines : string list;
  prune_lines : string list;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
}

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

let obligation_formula (step : PT.product_step) : fo =
  FNot (FAnd (step.prog_guard, FAnd (step.assume_guard, step.guarantee_guard)))

let render_automaton_lines ~prefix labels =
  labels |> List.mapi (fun i lbl -> Printf.sprintf "%s%d = %s" prefix i lbl)

let render_product_lines ~(node_name : ident) (analysis : Product_build.analysis) =
  let states =
    analysis.exploration.states
    |> List.map (fun st -> Printf.sprintf "[%s] state %s" node_name (string_of_state st))
  in
  let steps =
    analysis.exploration.steps
    |> List.map (fun (step : PT.product_step) ->
           Printf.sprintf "[%s] %s -- %s / A[%s]:%s / G[%s]:%s --> %s [%s]" node_name
             (string_of_state step.src)
             step.prog_transition.src
             (string_of_edge step.assume_edge)
             (string_of_fo step.assume_guard)
             (string_of_edge step.guarantee_edge)
             (string_of_fo step.guarantee_guard)
             (string_of_state step.dst)
             (string_of_step_class step.step_class))
  in
  states @ steps

let render_obligation_lines ~(node_name : ident) (analysis : Product_build.analysis) =
  analysis.exploration.steps
  |> List.filter_map (fun (step : PT.product_step) ->
         match step.step_class with
         | PT.Bad_guarantee ->
             Some
               (Printf.sprintf "[%s] obligation %s -> %s: %s" node_name
                  (string_of_state step.src)
                  (string_of_state step.dst)
                  (string_of_fo (obligation_formula step)))
         | _ -> None)

let render_prune_lines ~(node_name : ident) (analysis : Product_build.analysis) =
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

let render_product_dot ~(node_name : ident) (analysis : Product_build.analysis) =
  let buf = Buffer.create 4096 in
  Buffer.add_string buf "digraph Product {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  List.iter
    (fun st ->
      let color =
        if PT.compare_state st analysis.exploration.initial_state = 0 then "lightblue"
        else "white"
      in
      Buffer.add_string buf
        (Printf.sprintf "  %s [style=filled,fillcolor=%s,label=\"%s\"];\n"
           (node_id_of_state st) color
           (escape_dot_label (Printf.sprintf "%s\\n%s" node_name (string_of_state st)))))
    analysis.exploration.states;
  List.iter
    (fun (step : PT.product_step) ->
      let edge_color =
        match step.step_class with
        | PT.Safe -> "black"
        | PT.Bad_assumption -> "orange"
        | PT.Bad_guarantee -> "red"
      in
      Buffer.add_string buf
        (Printf.sprintf "  %s -> %s [color=%s,label=\"%s\"];\n"
           (node_id_of_state step.src) (node_id_of_state step.dst) edge_color
           (escape_dot_label
              (Printf.sprintf "%s\\nA[%s]\\nG[%s]" (string_of_step_class step.step_class)
                 (string_of_edge step.assume_edge) (string_of_edge step.guarantee_edge)))))
    analysis.exploration.steps;
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

let html_state_label ~state_prefix ~idx ~is_bad =
  if is_bad then Printf.sprintf "<I>%s</I><SUB>bad</SUB>" state_prefix
  else Printf.sprintf "<I>%s</I><SUB>%d</SUB>" state_prefix idx

let mathify_formula (s : string) : string =
  s
  |> replace_all ~pattern:"<>" ~by:"≠"
  |> replace_all ~pattern:" and " ~by:" ∧ "
  |> replace_all ~pattern:" or " ~by:" ∨ "
  |> replace_all ~pattern:"not " ~by:"¬"
  |> replace_all ~pattern:"true" ~by:"⊤"
  |> replace_all ~pattern:"false" ~by:"⊥"

let render_automaton_dot ~graph_name ~prefix ~state_prefix ~labels ~grouped ~atom_map_exprs =
  let buf = Buffer.create 1024 in
  let (node_fill, node_border, title_color, legend_fill, edge_color) =
    if prefix = "a" then
      ("#e8f3ea", "#2f6b3b", "#2f6b3b", "#f4fbf5", "#2f6b3b")
    else
      ("#f6eadf", "#8b5a2b", "#8b5a2b", "#fdf6f0", "#8b5a2b")
  in
  let bad_fill = "#f6d7d7" in
  let bad_border = "#a53030" in
  let guard_strings =
    grouped
    |> List.map (fun (_src, guard, _dst) ->
           guard
           |> recover_guard_iexpr atom_map_exprs
           |> iexpr_to_fo_with_atoms []
           |> string_of_fo
           |> compact_display_string)
  in
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
  Buffer.add_string buf "  labelloc=t;\n";
  Buffer.add_string buf
    (Printf.sprintf "  label=\"%s automaton\";\n" (String.uppercase_ascii state_prefix));
  Buffer.add_string buf "  fontsize=18;\n";
  Buffer.add_string buf
    (Printf.sprintf "  fontcolor=\"%s\";\n" title_color);
  Buffer.add_string buf
    "  node [shape=circle,style=filled,penwidth=1.6,fontname=\"Helvetica\",fontsize=12];\n";
  Buffer.add_string buf
    "  edge [fontname=\"Helvetica\",fontsize=12,penwidth=1.3,arrowsize=0.8,labeldistance=1.4,labelangle=28];\n";
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
        guard
        |> recover_guard_iexpr atom_map_exprs
        |> iexpr_to_fo_with_atoms []
        |> string_of_fo
        |> compact_display_string
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
           "  %s%d -> %s%d [label=\"%s\",color=\"%s\",fontcolor=\"%s\"];\n"
           prefix src prefix dst (escape_dot_label alias) this_edge_color this_edge_color))
    grouped;
  begin
    let unique_guards =
      let seen = Hashtbl.create 16 in
      List.filter_map
        (fun formula ->
          if formula = "true" || Hashtbl.mem seen formula then None
          else (
            Hashtbl.add seen formula ();
            Some (alias_of_guard formula, formula)))
        guard_strings
    in
    match unique_guards with
    | [] -> ()
    | _ ->
        let legend =
          Printf.sprintf "%s transition guards\\l%s\\l" state_prefix
            (unique_guards
            |> List.map (fun (alias, formula) -> Printf.sprintf "%s := %s" alias (mathify_formula formula))
            |> String.concat "\\l")
        in
        Buffer.add_string buf "  { rank=sink;\n";
        Buffer.add_string buf
          (Printf.sprintf
             "    legend_%s [shape=note,label=\"%s\",style=\"filled,rounded\",fillcolor=\"%s\",color=\"%s\",fontcolor=\"%s\",fontname=\"Helvetica\",fontsize=10];\n"
             prefix (escape_dot_label legend) legend_fill node_border node_border);
        Buffer.add_string buf "  }\n"
  end;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let render ~(node_name : ident) ~(analysis : Product_build.analysis) : rendered =
  let guarantee_automaton_lines =
    render_automaton_lines ~prefix:"G" analysis.guarantee_state_labels
    |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
  in
  let assume_automaton_lines =
    render_automaton_lines ~prefix:"A" analysis.assume_state_labels
    |> List.map (fun line -> Printf.sprintf "[%s] %s" node_name line)
  in
  {
    guarantee_automaton_lines;
    assume_automaton_lines;
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
  }
