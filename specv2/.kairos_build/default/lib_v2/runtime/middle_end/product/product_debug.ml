open Ast
open Support
open Automaton_core

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

let render_automaton_dot ~graph_name ~prefix labels =
  let buf = Buffer.create 1024 in
  Buffer.add_string buf (Printf.sprintf "digraph %s {\n  rankdir=LR;\n" graph_name);
  List.iteri
    (fun i lbl ->
      Buffer.add_string buf
        (Printf.sprintf "  %s%d [label=\"%s\"];\n" prefix i (escape_dot_label lbl)))
    labels;
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
      render_automaton_dot ~graph_name:"GuaranteeAutomaton" ~prefix:"g"
        analysis.guarantee_state_labels;
    assume_automaton_dot =
      render_automaton_dot ~graph_name:"AssumeAutomaton" ~prefix:"a"
        analysis.assume_state_labels;
    product_dot = render_product_dot ~node_name analysis;
  }
