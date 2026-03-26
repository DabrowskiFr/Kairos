(*---------------------------------------------------------------------------
 * Kairos — DOT graph renderer for the three IR layers.
 *
 * Produces Graphviz DOT representations of:
 *   annotated_node (Pass 4 output)
 *   verified_node  (Pass 5 output)
 *   node_ir        (kernel product)
 *---------------------------------------------------------------------------*)

let max_label_len = 60

(* Escape special HTML/DOT characters in node labels. *)
let html_escape (s : string) : string =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      match c with
      | '<' -> Buffer.add_string buf "&lt;"
      | '>' -> Buffer.add_string buf "&gt;"
      | '&' -> Buffer.add_string buf "&amp;"
      | '"' -> Buffer.add_string buf "&quot;"
      | c -> Buffer.add_char buf c)
    s;
  Buffer.contents buf

let truncate (s : string) : string =
  if String.length s <= max_label_len then s
  else String.sub s 0 max_label_len ^ "..."

(* ------------------------------------------------------------------ *)
(* annotated_node                                                       *)
(* ------------------------------------------------------------------ *)

let dot_of_annotated_transition (t : Proof_obligation_ir.annotated_transition) : string =
  let raw = t.raw in
  let guard_str = truncate (Ast_pretty.string_of_fo raw.guard) |> html_escape in
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf
       "  %s -> %s [label=<\n    <TABLE BORDER=\"0\" CELLPADDING=\"2\" CELLSPACING=\"0\">\n"
       raw.src_state raw.dst_state);
  Buffer.add_string buf
    (Printf.sprintf "      <TR><TD ALIGN=\"LEFT\"><B>guard:</B> %s</TD></TR>\n" guard_str);
  List.iter
    (fun (f : Ir.contract_formula) ->
      let s = truncate (Ast_pretty.string_of_ltl f.value) |> html_escape in
      Buffer.add_string buf
        (Printf.sprintf
           "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#cc0000\"><B>req:</B></FONT> %s</TD></TR>\n"
           s))
    t.requires;
  List.iter
    (fun (f : Ir.contract_formula) ->
      let s = truncate (Ast_pretty.string_of_ltl f.value) |> html_escape in
      Buffer.add_string buf
        (Printf.sprintf
           "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#006600\"><B>ens:</B></FONT> %s</TD></TR>\n"
           s))
    t.ensures;
  Buffer.add_string buf "    </TABLE>\n  >];\n";
  Buffer.contents buf

let dot_of_annotated_node (n : Proof_obligation_ir.annotated_node) : string =
  let raw = n.raw in
  let buf = Buffer.create 1024 in
  Buffer.add_string buf
    (Printf.sprintf
       "digraph \"%s\" {\n  rankdir=LR;\n  node [shape=circle fontname=\"Courier\" fontsize=10];\n  edge [fontname=\"Courier\" fontsize=9];\n  // States\n"
       raw.node_name);
  List.iter
    (fun state ->
      if state = raw.init_state then
        Buffer.add_string buf
          (Printf.sprintf "  %s [shape=doublecircle label=\"%s\"];\n" state state)
      else Buffer.add_string buf (Printf.sprintf "  %s [label=\"%s\"];\n" state state))
    raw.control_states;
  Buffer.add_string buf "  // Transitions\n";
  List.iter (fun t -> Buffer.add_string buf (dot_of_annotated_transition t)) n.transitions;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

(* ------------------------------------------------------------------ *)
(* verified_node                                                        *)
(* ------------------------------------------------------------------ *)

let dot_of_verified_transition (t : Proof_obligation_ir.verified_transition) : string =
  let guard_str = truncate (Ast_pretty.string_of_fo t.guard) |> html_escape in
  let buf = Buffer.create 256 in
  Buffer.add_string buf
    (Printf.sprintf
       "  %s -> %s [label=<\n    <TABLE BORDER=\"0\" CELLPADDING=\"2\" CELLSPACING=\"0\">\n"
       t.src_state t.dst_state);
  Buffer.add_string buf
    (Printf.sprintf "      <TR><TD ALIGN=\"LEFT\"><B>guard:</B> %s</TD></TR>\n" guard_str);
  if t.pre_k_updates <> [] then begin
    let upd_strs =
      List.map
        (fun (s : Ast.stmt) ->
          match s.stmt with
          | SAssign (v, e) -> truncate (v ^ " := " ^ Ast_pretty.string_of_iexpr e) |> html_escape
          | _ -> "...")
        t.pre_k_updates
    in
    List.iter
      (fun s ->
        Buffer.add_string buf
          (Printf.sprintf
             "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#8800aa\"><B>upd:</B></FONT> %s</TD></TR>\n"
             s))
      upd_strs
  end;
  List.iter
    (fun (f : Ir.contract_formula) ->
      let s = truncate (Ast_pretty.string_of_ltl f.value) |> html_escape in
      Buffer.add_string buf
        (Printf.sprintf
           "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#cc0000\"><B>req:</B></FONT> %s</TD></TR>\n"
           s))
    t.requires;
  List.iter
    (fun (f : Ir.contract_formula) ->
      let s = truncate (Ast_pretty.string_of_ltl f.value) |> html_escape in
      Buffer.add_string buf
        (Printf.sprintf
           "      <TR><TD ALIGN=\"LEFT\"><FONT COLOR=\"#006600\"><B>ens:</B></FONT> %s</TD></TR>\n"
           s))
    t.ensures;
  Buffer.add_string buf "    </TABLE>\n  >];\n";
  Buffer.contents buf

let dot_of_verified_node (n : Proof_obligation_ir.verified_node) : string =
  let buf = Buffer.create 1024 in
  Buffer.add_string buf
    (Printf.sprintf
       "digraph \"%s\" {\n  rankdir=LR;\n  node [shape=circle fontname=\"Courier\" fontsize=10];\n  edge [fontname=\"Courier\" fontsize=9];\n  // States\n"
       n.node_name);
  List.iter
    (fun state ->
      if state = n.init_state then
        Buffer.add_string buf
          (Printf.sprintf "  %s [shape=doublecircle label=\"%s\"];\n" state state)
      else Buffer.add_string buf (Printf.sprintf "  %s [label=\"%s\"];\n" state state))
    n.control_states;
  Buffer.add_string buf "  // Transitions\n";
  List.iter (fun t -> Buffer.add_string buf (dot_of_verified_transition t)) n.transitions;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

(* ------------------------------------------------------------------ *)
(* kernel node_ir (Proof_kernel_types.node_ir)                          *)
(* ------------------------------------------------------------------ *)

let product_state_label (ps : Proof_kernel_types.product_state_ir) : string =
  Printf.sprintf "%s_A%d_G%d" ps.prog_state ps.assume_state_index ps.guarantee_state_index

let dot_of_kernel_node_ir (n : Proof_kernel_types.node_ir) : string =
  let node_name = n.reactive_program.node_name in
  let buf = Buffer.create 2048 in
  Buffer.add_string buf
    (Printf.sprintf
       "digraph \"%s_kernel\" {\n  rankdir=LR;\n  node [shape=box fontname=\"Courier\" fontsize=9];\n  edge [fontname=\"Courier\" fontsize=9];\n  // Product states\n"
       node_name);
  let init_label = product_state_label n.initial_product_state in
  List.iter
    (fun (ps : Proof_kernel_types.product_state_ir) ->
      let lbl = product_state_label ps in
      let node_label =
        Printf.sprintf "prog:%s\\nasm:%d guar:%d" ps.prog_state ps.assume_state_index
          ps.guarantee_state_index
      in
      let style = if lbl = init_label then " style=filled fillcolor=lightblue" else "" in
      Buffer.add_string buf
        (Printf.sprintf "  \"%s\" [label=\"%s\"%s];\n" lbl node_label style))
    n.product_states;
  Buffer.add_string buf "  // Product steps\n";
  List.iter
    (fun (step : Proof_kernel_types.product_step_ir) ->
      let src_lbl = product_state_label step.src in
      let dst_lbl = product_state_label step.dst in
      let src_prog, dst_prog = step.program_transition in
      let guard_str =
        truncate (Ast_pretty.string_of_fo step.program_guard) |> String.escaped
      in
      let color =
        match step.step_kind with
        | StepSafe -> "black"
        | StepBadAssumption -> "blue"
        | StepBadGuarantee -> "red"
      in
      Buffer.add_string buf
        (Printf.sprintf "  \"%s\" -> \"%s\" [label=\"%s->%s\\nguard:%s\" color=%s];\n"
           src_lbl dst_lbl src_prog dst_prog guard_str color))
    n.product_steps;
  Buffer.add_string buf "}\n";
  Buffer.contents buf
