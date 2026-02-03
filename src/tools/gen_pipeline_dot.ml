let stage_name s = Stage_names.to_string s
let stage_label s = Stages_info.stage_label s
let stage_items s = Stages_info.stage_items s

let label_with_items ~stage =
  let items = stage_items stage in
  let items = List.map (fun i -> "- " ^ i) items in
  let lines = (stage_label stage) :: (items @ ["- stage: " ^ stage_name stage]) in
  String.concat "\\n" lines

let () =
  let out_dot = if Array.length Sys.argv > 1 then Sys.argv.(1) else "pipeline.dot" in
  let out_png = if Array.length Sys.argv > 2 then Sys.argv.(2) else "pipeline.png" in
  let lines = [
    "digraph pipeline {";
    "  rankdir=LR;";
    "  node [shape=box, style=\"rounded\", fontsize=9];";
    "";
    "  obc [label=\"OBC source\", shape=note];";
    Printf.sprintf "  parse [label=\"%s\"];" (label_with_items ~stage:Stage_names.Parsed);
    "";
    Printf.sprintf "  automaton [label=\"%s\"];" (label_with_items ~stage:Stage_names.Automaton);
    Printf.sprintf "  coher [label=\"%s\"];" (label_with_items ~stage:Stage_names.Contracts);
    "";
    Printf.sprintf "  mon [label=\"%s\"];" (label_with_items ~stage:Stage_names.Monitor);
    "";
    Printf.sprintf "  obcgen [label=\"%s\"];" (label_with_items ~stage:Stage_names.Obc);
    "  obcplus [label=\"OBC+ code\", shape=note];";
    "  whygen [label=\"Emit Why3\"];";
    "  why [label=\"Why3 code\", shape=note];";
    "  dotout [label=\"Emit DOT\", shape=note];";
    "  prove [label=\"Why3 proof\"];";
    "";
    "  { rank=same; obc; parse; automaton; coher; mon; }";
    "  { rank=same; obcgen; whygen; dotout; }";
    "  { rank=same; obcplus; why; prove; }";
    "";
    "  obc -> parse -> automaton -> coher -> mon -> obcgen -> obcplus;";
    "  obcgen -> whygen -> why -> prove;";
    "  automaton -> dotout;";
    "}";
  ] in
  let oc = open_out out_dot in
  List.iter (fun l -> output_string oc l; output_char oc '\n') lines;
  close_out oc;
  let cmd = Printf.sprintf "dot -Tpng -Gdpi=300 %s -o %s" out_dot out_png in
  ignore (Sys.command cmd)
