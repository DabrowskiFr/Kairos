let get_param_string (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`String s) -> Some s
      | _ -> None)
  | _ -> None

let get_param_bool (params : Yojson.Safe.t) key default =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`Bool b) -> b
      | _ -> default)
  | _ -> default

let get_param_int (params : Yojson.Safe.t) key default =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`Int n) -> n
      | _ -> default)
  | _ -> default

let get_param_obj (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`Assoc ys) -> Some ys
      | _ -> None)
  | _ -> None

let get_param_list (params : Yojson.Safe.t) key =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt key xs with
      | Some (`List ys) -> Some ys
      | _ -> None)
  | _ -> None

let get_text_document_uri (params : Yojson.Safe.t) =
  match get_param_obj params "textDocument" with
  | Some td -> (match List.assoc_opt "uri" td with Some (`String s) -> Some s | _ -> None)
  | None -> None

let get_did_open_text (params : Yojson.Safe.t) =
  match get_param_obj params "textDocument" with
  | Some td -> (match List.assoc_opt "text" td with Some (`String s) -> Some s | _ -> None)
  | None -> None

let get_did_change_text (params : Yojson.Safe.t) =
  match get_param_list params "contentChanges" with
  | Some changes ->
      let rec last_text acc = function
        | [] -> acc
        | (`Assoc c) :: tl ->
            let next = match List.assoc_opt "text" c with Some (`String s) -> Some s | _ -> acc in
            last_text next tl
        | _ :: tl -> last_text acc tl
      in
      last_text None changes
  | None -> None

let position_from_params (params : Yojson.Safe.t) : (int * int) option =
  match params with
  | `Assoc xs -> (
      match List.assoc_opt "position" xs with
      | Some (`Assoc p) -> (
          match (List.assoc_opt "line" p, List.assoc_opt "character" p) with
          | Some (`Int l), Some (`Int c) -> Some (l, c)
          | _ -> None)
      | _ -> None)
  | _ -> None

let client_supports_work_done_progress (params : Yojson.Safe.t) : bool =
  match get_param_obj params "capabilities" with
  | Some caps -> (
      match List.assoc_opt "window" caps with
      | Some (`Assoc win) ->
          (match List.assoc_opt "workDoneProgress" win with Some (`Bool b) -> b | _ -> false)
      | _ -> false)
  | None -> false

let loc_of_ast (l : Ast.loc) : Lsp_protocol.loc =
  { line = l.line; col = l.col; line_end = l.line_end; col_end = l.col_end }

let map_outputs (o : Pipeline.outputs) : Lsp_protocol.outputs =
  {
    obc_text = o.obc_text;
    why_text = o.why_text;
    vc_text = o.vc_text;
    smt_text = o.smt_text;
    dot_text = o.dot_text;
    labels_text = o.labels_text;
    program_automaton_text = o.program_automaton_text;
    guarantee_automaton_text = o.guarantee_automaton_text;
    assume_automaton_text = o.assume_automaton_text;
    product_text = o.product_text;
    obligations_map_text = o.obligations_map_text;
    prune_reasons_text = o.prune_reasons_text;
    program_dot = o.program_dot;
    guarantee_automaton_dot = o.guarantee_automaton_dot;
    assume_automaton_dot = o.assume_automaton_dot;
    product_dot = o.product_dot;
    stage_meta = o.stage_meta;
    goals = o.goals;
    obcplus_sequents = o.obcplus_sequents;
    vc_sources = o.vc_sources;
    task_sequents = o.task_sequents;
    vc_locs = List.map (fun (i, l) -> (i, loc_of_ast l)) o.vc_locs;
    obcplus_spans = o.obcplus_spans;
    vc_locs_ordered = List.map loc_of_ast o.vc_locs_ordered;
    obcplus_spans_ordered = o.obcplus_spans_ordered;
    vc_spans_ordered = o.vc_spans_ordered;
    why_spans = o.why_spans;
    vc_ids_ordered = o.vc_ids_ordered;
    obcplus_time_s = o.obcplus_time_s;
    why_time_s = o.why_time_s;
    automata_generation_time_s = o.automata_generation_time_s;
    automata_build_time_s = o.automata_build_time_s;
    why3_prep_time_s = o.why3_prep_time_s;
    dot_png = o.dot_png;
  }

let map_automata (o : Pipeline.automata_outputs) : Lsp_protocol.automata_outputs =
  {
    dot_text = o.dot_text;
    labels_text = o.labels_text;
    program_automaton_text = o.program_automaton_text;
    guarantee_automaton_text = o.guarantee_automaton_text;
    assume_automaton_text = o.assume_automaton_text;
    product_text = o.product_text;
    obligations_map_text = o.obligations_map_text;
    prune_reasons_text = o.prune_reasons_text;
    program_dot = o.program_dot;
    guarantee_automaton_dot = o.guarantee_automaton_dot;
    assume_automaton_dot = o.assume_automaton_dot;
    product_dot = o.product_dot;
    dot_png = o.dot_png;
    stage_meta = o.stage_meta;
  }

let map_obc (o : Pipeline.obc_outputs) : Lsp_protocol.obc_outputs =
  { obc_text = o.obc_text; stage_meta = o.stage_meta }

let map_why (o : Pipeline.why_outputs) : Lsp_protocol.why_outputs =
  { why_text = o.why_text; stage_meta = o.stage_meta }

let map_oblig (o : Pipeline.obligations_outputs) : Lsp_protocol.obligations_outputs =
  { vc_text = o.vc_text; smt_text = o.smt_text }
