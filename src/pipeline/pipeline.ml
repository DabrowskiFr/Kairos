open Ast

type goal_info = string * string * float * string option * string * string option

type text_span = {
  start_offset : int;
  end_offset : int;
}

type proof_diagnostic = {
  category : string;
  summary : string;
  detail : string;
  probable_cause : string option;
  missing_elements : string list;
  goal_symbols : string list;
  analysis_method : string;
  solver_detail : string option;
  native_unsat_core_solver : string option;
  native_unsat_core_hypothesis_ids : int list;
  native_counterexample_solver : string option;
  native_counterexample_model : string option;
  kairos_core_hypotheses : string list;
  why3_noise_hypotheses : string list;
  relevant_hypotheses : string list;
  context_hypotheses : string list;
  unused_hypotheses : string list;
  suggestions : string list;
  limitations : string list;
}

type proof_trace = {
  goal_index : int;
  stable_id : string;
  goal_name : string;
  status : string;
  solver_status : string;
  time_s : float;
  source : string;
  node : string option;
  transition : string option;
  obligation_kind : string;
  obligation_family : string option;
  obligation_category : string option;
  origin_ids : int list;
  vc_id : string option;
  source_span : Ast.loc option;
  why_span : text_span option;
  vc_span : text_span option;
  smt_span : text_span option;
  dump_path : string option;
  diagnostic : proof_diagnostic;
}

type outputs = {
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  program_automaton_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  stage_meta : (string * (string * string) list) list;
  goals : goal_info list;
  proof_traces : proof_trace list;
  vc_sources : (int * string) list;
  task_sequents : (string list * string) list;
  vc_locs : (int * Ast.loc) list;
  vc_locs_ordered : Ast.loc list;
  vc_spans_ordered : (int * int) list;
  why_spans : (int * (int * int)) list;
  vc_ids_ordered : int list;
  why_time_s : float;
  automata_generation_time_s : float;
  automata_build_time_s : float;
  why3_prep_time_s : float;
  dot_png : string option;
  dot_png_error : string option;
  program_png : string option;
  program_png_error : string option;
  guarantee_automaton_png : string option;
  guarantee_automaton_png_error : string option;
  assume_automaton_png : string option;
  assume_automaton_png_error : string option;
  product_png : string option;
  product_png_error : string option;
  historical_clauses_text : string;
  eliminated_clauses_text : string;
}

type automata_outputs = {
  dot_text : string;
  labels_text : string;
  program_automaton_text : string;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  obligations_map_text : string;
  prune_reasons_text : string;
  program_dot : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  dot_png : string option;
  dot_png_error : string option;
  program_png : string option;
  program_png_error : string option;
  guarantee_automaton_png : string option;
  guarantee_automaton_png_error : string option;
  assume_automaton_png : string option;
  assume_automaton_png_error : string option;
  product_png : string option;
  product_png_error : string option;
  stage_meta : (string * (string * string) list) list;
  historical_clauses_text : string;
  eliminated_clauses_text : string;
}

type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }
type obligations_outputs = { vc_text : string; smt_text : string }

type ast_stages = {
  source : Source_file.t;
  parsed : Ast.program;
  automata_generation : Ast.program;
  automata : Middle_end_stages.automata_stage;
  contracts : Ast.program;
  instrumentation : Ast.program;
  imported_summaries : Product_kernel_ir.exported_node_summary_ir list;
}

type stage_infos = {
  parse : Stage_info.parse_info option;
  automata_generation : Stage_info.automata_info option;
  contracts : Stage_info.contracts_info option;
  instrumentation : Stage_info.instrumentation_info option;
}

type config = {
  input_file : string;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  smoke_tests : bool;
  timeout_s : int;
  max_proof_goals : int option;
  selected_goal_index : int option;
  compute_proof_diagnostics : bool;
  prefix_fields : bool;
  prove : bool;
  generate_vc_text : bool;
  generate_smt_text : bool;
  generate_monitor_text : bool;
  generate_dot_png : bool;
}

type error =
  | Parse_error of string
  | Stage_error of string
  | Why3_error of string
  | Prove_error of string
  | Io_error of string

let error_to_string = function
  | Parse_error msg -> msg
  | Stage_error msg -> msg
  | Why3_error msg -> msg
  | Prove_error msg -> msg
  | Io_error msg -> msg

let join_blocks ~sep blocks =
  let buf = Buffer.create 4096 in
  List.iteri
    (fun i block ->
      if i > 0 then Buffer.add_string buf sep;
      Buffer.add_string buf block)
    blocks;
  Buffer.contents buf

let join_blocks_with_spans ~sep blocks =
  let buf = Buffer.create 4096 in
  let spans = ref [] in
  let offset = ref 0 in
  List.iteri
    (fun i block ->
      if i > 0 then (
        Buffer.add_string buf sep;
        offset := !offset + String.length sep);
      let start_pos = !offset in
      Buffer.add_string buf block;
      let end_pos = start_pos + String.length block in
      spans := (start_pos, end_pos) :: !spans;
      offset := end_pos)
    blocks;
  (Buffer.contents buf, List.rev !spans)

let program_stats (p : Ast.program) : (string * string) list =
  let nodes = List.length p in
  let transitions = List.fold_left (fun acc (n : Ast.node) -> acc + List.length n.trans) 0 p in
  let requires =
    List.fold_left
      (fun acc (n : Ast.node) ->
        acc + List.fold_left (fun a (t : Ast.transition) -> a + List.length t.requires) 0 n.trans)
      0 p
  in
  let ensures =
    List.fold_left
      (fun acc (n : Ast.node) ->
        acc + List.fold_left (fun a (t : Ast.transition) -> a + List.length t.ensures) 0 n.trans)
      0 p
  in
  let guards =
    List.fold_left
      (fun acc n ->
        acc
        + List.fold_left
            (fun a (t : Ast.transition) -> if t.guard = None then a else a + 1)
            0 n.trans)
      0 p
  in
  let locals = List.fold_left (fun acc n -> acc + List.length n.locals) 0 p in
  [
    ("nodes", string_of_int nodes);
    ("transitions", string_of_int transitions);
    ("requires", string_of_int requires);
    ("ensures", string_of_int ensures);
    ("guards", string_of_int guards);
    ("locals", string_of_int locals);
  ]

let stage_meta (infos : stage_infos) : (string * (string * string) list) list =
  let parse = Option.value ~default:Stage_info.empty_parse_info infos.parse in
  let automata_info =
    Option.value ~default:Stage_info.empty_automata_info infos.automata_generation
  in
  let contracts_info = Option.value ~default:Stage_info.empty_contracts_info infos.contracts in
  let instrumentation_info = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
  let user =
    ( "parse",
      [
        ("source_path", Option.value ~default:"" parse.source_path);
        ("text_hash", Option.value ~default:"" parse.text_hash);
        ("parse_errors", string_of_int (List.length parse.parse_errors));
        ("warnings", string_of_int (List.length parse.warnings));
      ] )
  in
  let automata_generation =
    ( "automata",
      [
        ("states", string_of_int automata_info.residual_state_count);
        ("edges", string_of_int automata_info.residual_edge_count);
        ("warnings", string_of_int (List.length automata_info.warnings));
      ] )
  in
  let contracts =
    ( "contracts",
      [
        ("origins", string_of_int (List.length contracts_info.contract_origin_map));
        ("warnings", string_of_int (List.length contracts_info.warnings));
      ] )
  in
  let instrumentation =
    ( "instrumentation",
      [
        ("atoms", string_of_int instrumentation_info.atom_count);
        ("states", string_of_int (List.length instrumentation_info.state_ctors));
        ("guarantee_automaton_lines", string_of_int (List.length instrumentation_info.guarantee_automaton_lines));
        ("assume_automaton_lines", string_of_int (List.length instrumentation_info.assume_automaton_lines));
        ("product_lines", string_of_int (List.length instrumentation_info.product_lines));
        ("obligations_lines", string_of_int (List.length instrumentation_info.obligations_lines));
        ("prune_lines", string_of_int (List.length instrumentation_info.prune_lines));
        ("warnings", string_of_int (List.length instrumentation_info.warnings));
      ] )
  in
  [ user; automata_generation; contracts; instrumentation ]

let instrumentation_diag_texts (infos : stage_infos) :
    string * string * string * string * string * string * string * string =
  let instrumentation_info = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
  let join = String.concat "\n" in
  let obligations_text =
    let base = join instrumentation_info.obligations_lines in
    let kernel = join instrumentation_info.kernel_pipeline_lines in
    match (String.trim base, String.trim kernel) with
    | "", "" -> ""
    | _, "" -> base
    | "", _ -> kernel
    | _ -> base ^ "\n\n" ^ kernel
  in
  ( join instrumentation_info.guarantee_automaton_lines,
    join instrumentation_info.assume_automaton_lines,
    join instrumentation_info.product_lines,
    obligations_text,
    join instrumentation_info.prune_lines,
    instrumentation_info.guarantee_automaton_dot,
    instrumentation_info.assume_automaton_dot,
    instrumentation_info.product_dot )

let emit_monitor_generation_debug_stats (p : Ast.program) =
  let nodes = List.length p in
  let edges = List.fold_left (fun acc n -> acc + List.length n.trans) 0 p in
  Log.stage_info (Some Stage_names.Automaton) "instrumentation generation stats"
    [ ("nodes", string_of_int nodes); ("edges", string_of_int edges) ]

let reid_with_origin (x : Ast.fo_o) : Ast.fo_o =
  let new_id = Provenance.fresh_id () in
  Provenance.add_parents ~child:new_id ~parents:[ x.oid ];
  { x with oid = new_id }

let reid_program (p : Ast.program) : Ast.program =
  let reid_fo = reid_with_origin in
  let reid_trans (t : Ast.transition) =
    { t with requires = List.map reid_fo t.requires; ensures = List.map reid_fo t.ensures }
  in
  let reid_node (n : Ast.node) =
    {
      n with
      attrs = { n.attrs with coherency_goals = List.map reid_fo n.attrs.coherency_goals };
      trans = List.map reid_trans n.trans;
    }
  in
  List.map reid_node p |> Ast_builders.ensure_program_uids

let with_smoke_tests (p : Ast.program) : Ast.program =
  let has_false_ensure (t : Ast.transition) =
    List.exists (fun (f : Ast.fo_o) -> f.value = Ast.FFalse) t.ensures
  in
  let add_transition_smoke (t : Ast.transition) : Ast.transition =
    if has_false_ensure t then t
    else { t with ensures = t.ensures @ [ Ast_provenance.with_origin Ast.Internal Ast.FFalse ] }
  in
  List.map (fun (n : Ast.node) -> { n with trans = List.map add_transition_smoke n.trans }) p

let strip_contracts_in_program (p : Ast.program) : Ast.program =
  let strip_t (t : Ast.transition) = { t with requires = []; ensures = [] } in
  List.map
    (fun (n : Ast.node) ->
      {
        n with
        trans = List.map strip_t n.trans;
        attrs = { n.attrs with coherency_goals = [] };
      })
    p

let build_ast_with_info ?(log = false) ~input_file () : (ast_stages * stage_infos, error) result =
  let parse () =
    try
      if log then Log.stage_start Stage_names.Parsed;
      let t0 = Unix.gettimeofday () in
      let p_parsed, parse_info = Frontend.parse_file_with_info input_file in
      if log then
        Log.stage_end Stage_names.Parsed
          (int_of_float ((Unix.gettimeofday () -. t0) *. 1000.))
          (program_stats p_parsed);
      Ok (p_parsed, parse_info)
    with exn -> Error (Parse_error (Printexc.to_string exn))
  in
  match parse () with
  | Error _ as err -> err
  | Ok (p_parsed, parse_info) -> (
      try
        let t1 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Automaton;
        let p_automaton, automata, automata_info =
          p_parsed |> Middle_end.stage_automata_generation_with_info |> fun (p, stage, info) ->
          (reid_program p, stage, info)
        in
        emit_monitor_generation_debug_stats p_automaton;
        if log then
          Log.stage_end Stage_names.Automaton
            (int_of_float ((Unix.gettimeofday () -. t1) *. 1000.))
            (program_stats p_automaton);
        let t2 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Instrumentation;
        let p_monitor, automata, instrumentation_info =
          (p_automaton, automata) |> Middle_end.stage_instrumentation_with_info
          |> fun (p, stage, info) -> (reid_program p, stage, info)
        in
        if log then
          Log.stage_end Stage_names.Instrumentation
            (int_of_float ((Unix.gettimeofday () -. t2) *. 1000.))
            (program_stats p_monitor);
        let t3 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Contracts;
        let p_contracts, automata, contracts_info =
          (p_monitor, automata) |> Middle_end.stage_contracts_with_info |> fun (p, stage, info) ->
          (reid_program p, stage, info)
        in
        if log then
          Log.stage_end Stage_names.Contracts
            (int_of_float ((Unix.gettimeofday () -. t3) *. 1000.))
            (program_stats p_contracts);
        let asts =
          {
            source = { Source_file.imports = []; nodes = p_parsed };
            parsed = p_parsed;
            automata_generation = p_automaton;
            automata;
            contracts = p_contracts;
            instrumentation = p_monitor;
            imported_summaries = [];
          }
        in
        let infos =
          {
            parse = Some parse_info;
            automata_generation = Some automata_info;
            contracts = Some contracts_info;
            instrumentation = Some instrumentation_info;
          }
        in
        Ok (asts, infos)
      with exn -> Error (Stage_error (Printexc.to_string exn)))

let build_ast ?(log = false) ~input_file () : (ast_stages, error) result =
  match build_ast_with_info ~log ~input_file () with
  | Ok (asts, _infos) -> Ok asts
  | Error _ as err -> err

let build_vc_sources_from_formula_sources ~(formula_sources : (int * string) list)
    ~(vc_ids_ordered : int list) : (int * string) list =
  let src_tbl = Hashtbl.create (List.length formula_sources * 2) in
  List.iter (fun (k, v) -> Hashtbl.replace src_tbl k v) formula_sources;
  let unique_preserve_order xs =
    let seen = Hashtbl.create 8 in
    List.filter
      (fun x ->
        if x = "" || Hashtbl.mem seen x then false
        else (
          Hashtbl.add seen x ();
          true))
      xs
  in
  List.map
    (fun vcid ->
      let ids = vcid :: Provenance.ancestors vcid in
      let labels =
        ids
        |> List.filter_map (fun id -> Hashtbl.find_opt src_tbl id)
        |> unique_preserve_order
      in
      let source =
        match labels with
        | [] -> ""
        | [ one ] -> one
        | many -> String.concat " | " many
      in
      (vcid, source))
    vc_ids_ordered

let build_vcid_locs (p_parsed : Ast.program) : (int * Ast.loc) list * Ast.loc list =
  let p_parsed = p_parsed in
  let acc = ref [] in
  let ordered = ref [] in
  let add_formula (f : Ast.fo_o) =
    match f.loc with
    | None -> ()
    | Some loc ->
        acc := (f.oid, loc) :: !acc;
        ordered := loc :: !ordered
  in
  let add_node (node : Ast.node) =
    List.iter add_formula node.attrs.coherency_goals;
    List.iter
      (fun (t : Ast.transition) ->
        List.iter add_formula t.requires;
        List.iter
          (fun (ens : Ast.fo_o) -> add_formula ens)
          t.ensures)
      node.trans
  in
  List.iter add_node p_parsed;
  (List.rev !acc, List.rev !ordered)

let dot_png_from_text_diagnostic (dot_text : string) : string option * string option =
  let open Bos in
  match OS.File.tmp "kairos_ide_%s.dot" with
  | Error (`Msg msg) -> (None, Some ("Unable to allocate DOT temp file: " ^ msg))
  | Ok dot_file ->
      let png_file = Fpath.set_ext "png" dot_file in
      begin match OS.File.write dot_file dot_text with
      | Error (`Msg msg) ->
          ignore (OS.File.delete dot_file);
          (None, Some ("Unable to write DOT temp file: " ^ msg))
      | Ok () ->
          let command =
            String.concat " "
              [
                "dot";
                "-Tpng";
                Filename.quote (Fpath.to_string dot_file);
                "-o";
                Filename.quote (Fpath.to_string png_file);
              ]
          in
          let env = Unix.environment () in
          let in_chan, out_chan, err_chan = Unix.open_process_full command env in
          close_out_noerr out_chan;
          let stdout_text = In_channel.input_all in_chan |> String.trim in
          let stderr_text = In_channel.input_all err_chan |> String.trim in
          let status = Unix.close_process_full (in_chan, out_chan, err_chan) in
          ignore (OS.File.delete dot_file);
          begin
            match status with
            | Unix.WEXITED 0 -> (Some (Fpath.to_string png_file), None)
            | Unix.WEXITED code ->
                ignore (OS.File.delete png_file);
                let detail =
                  if stderr_text <> "" then stderr_text
                  else if stdout_text <> "" then stdout_text
                  else Printf.sprintf "dot exited with status %d" code
                in
                (None, Some detail)
            | Unix.WSIGNALED signal ->
                ignore (OS.File.delete png_file);
                (None, Some (Printf.sprintf "dot terminated by signal %d" signal))
            | Unix.WSTOPPED signal ->
                ignore (OS.File.delete png_file);
                (None, Some (Printf.sprintf "dot stopped by signal %d" signal))
          end
      end

let dot_png_from_text (dot_text : string) : string option =
  fst (dot_png_from_text_diagnostic dot_text)

let graph_pngs ~program_dot ~guarantee_automaton_dot ~assume_automaton_dot ~product_dot =
  let render_if_non_empty dot = if String.trim dot = "" then None else dot_png_from_text dot in
  ( render_if_non_empty program_dot,
    render_if_non_empty guarantee_automaton_dot,
    render_if_non_empty assume_automaton_dot,
    render_if_non_empty product_dot )

let instrumentation_pass ~generate_png ~input_file : (automata_outputs, error) result =
  let _ = (generate_png, input_file) in
  Error
    (Stage_error
       "Legacy Pipeline.instrumentation_pass is removed. Use Pipeline_v2_indep.instrumentation_pass.")

let why_pass ~prefix_fields ~input_file : (why_outputs, error) result =
  let _ = (prefix_fields, input_file) in
  Error (Stage_error "Legacy Pipeline.why_pass is removed. Use Pipeline_v2_indep.why_pass.")

let obligations_pass ~prefix_fields ~prover ~input_file : (obligations_outputs, error) result =
  let _ = (prefix_fields, prover, input_file) in
  Error
    (Stage_error
       "Legacy Pipeline.obligations_pass is removed. Use Pipeline_v2_indep.obligations_pass.")

type eval_value =
  | VInt of int
  | VBool of bool
  | VReal of float
  | VCustom of string

let string_of_eval_value = function
  | VInt i -> string_of_int i
  | VBool b -> if b then "true" else "false"
  | VReal f -> string_of_float f
  | VCustom s -> s

let eval_error msg = Error (Stage_error ("eval: " ^ msg))

let default_value_of_ty = function
  | Ast.TInt -> VInt 0
  | Ast.TBool -> VBool false
  | Ast.TReal -> VReal 0.0
  | Ast.TCustom c -> VCustom c

let split_assignments (s : string) : string list =
  s |> String.split_on_char ',' |> List.map String.trim |> List.filter (fun x -> x <> "")

let strip_optional_quotes (s : string) : string =
  let s = String.trim s in
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then String.sub s 1 (n - 2) else s

let parse_typed_value ~(name : string) ~(ty : Ast.ty) (raw : string) :
    (eval_value, error) result =
  match ty with
  | Ast.TInt -> (
      match int_of_string_opt raw with
      | Some i -> Ok (VInt i)
      | None -> eval_error (Printf.sprintf "invalid int for '%s': %s" name raw))
  | Ast.TBool -> (
      match String.lowercase_ascii raw with
      | "true" | "1" -> Ok (VBool true)
      | "false" | "0" -> Ok (VBool false)
      | _ -> eval_error (Printf.sprintf "invalid bool for '%s': %s" name raw))
  | Ast.TReal -> (
      match float_of_string_opt raw with
      | Some f -> Ok (VReal f)
      | None -> eval_error (Printf.sprintf "invalid real for '%s': %s" name raw))
  | Ast.TCustom _ -> Ok (VCustom raw)

let eval_bool_of_value ~(ctx : string) = function
  | VBool b -> Ok b
  | v -> eval_error (Printf.sprintf "expected bool in %s, got '%s'" ctx (string_of_eval_value v))

let eval_int_of_value ~(ctx : string) = function
  | VInt i -> Ok i
  | v -> eval_error (Printf.sprintf "expected int in %s, got '%s'" ctx (string_of_eval_value v))

let eval_iexpr (env : (string, eval_value) Hashtbl.t) (e : Ast.iexpr) :
    (eval_value, error) result =
  let rec go (e : Ast.iexpr) : (eval_value, error) result =
    match e.iexpr with
    | ILitInt i -> Ok (VInt i)
    | ILitBool b -> Ok (VBool b)
    | IVar v -> (
        match Hashtbl.find_opt env v with
        | Some value -> Ok value
        | None -> eval_error (Printf.sprintf "unbound variable '%s'" v))
    | IPar e -> go e
    | IUn (Neg, e) -> (
        match go e with
        | Error _ as err -> err
        | Ok v -> (
            match eval_int_of_value ~ctx:"unary '-'" v with
            | Error _ as err -> err
            | Ok i -> Ok (VInt (-i))))
    | IUn (Not, e) -> (
        match go e with
        | Error _ as err -> err
        | Ok v -> (
            match eval_bool_of_value ~ctx:"unary 'not'" v with
            | Error _ as err -> err
            | Ok b -> Ok (VBool (not b))))
    | IBin (op, l, r) -> (
        match (go l, go r) with
        | (Error _ as err), _ -> err
        | _, (Error _ as err) -> err
        | Ok vl, Ok vr -> (
            match op with
            | Add | Sub | Mul | Div -> (
                match (eval_int_of_value ~ctx:"arithmetic lhs" vl, eval_int_of_value ~ctx:"arithmetic rhs" vr) with
                | (Error _ as err), _ -> err
                | _, (Error _ as err) -> err
                | Ok li, Ok ri ->
                    if op = Div && ri = 0 then eval_error "division by zero"
                    else
                      let v =
                        match op with
                        | Add -> li + ri
                        | Sub -> li - ri
                        | Mul -> li * ri
                        | Div -> li / ri
                        | _ -> assert false
                      in
                      Ok (VInt v))
            | Eq -> Ok (VBool (vl = vr))
            | Neq -> Ok (VBool (vl <> vr))
            | Lt | Le | Gt | Ge -> (
                match (eval_int_of_value ~ctx:"comparison lhs" vl, eval_int_of_value ~ctx:"comparison rhs" vr) with
                | (Error _ as err), _ -> err
                | _, (Error _ as err) -> err
                | Ok li, Ok ri ->
                    let b =
                      match op with
                      | Lt -> li < ri
                      | Le -> li <= ri
                      | Gt -> li > ri
                      | Ge -> li >= ri
                      | _ -> assert false
                    in
                    Ok (VBool b))
            | And | Or -> (
                match (eval_bool_of_value ~ctx:"logical lhs" vl, eval_bool_of_value ~ctx:"logical rhs" vr) with
                | (Error _ as err), _ -> err
                | _, (Error _ as err) -> err
                | Ok lb, Ok rb ->
                    Ok (VBool (if op = And then lb && rb else lb || rb)))))
  in
  go e

let eval_guard env (g : Ast.iexpr option) : (bool, error) result =
  match g with
  | None -> Ok true
  | Some e -> (
      match eval_iexpr env e with
      | Error _ as err -> err
      | Ok v -> eval_bool_of_value ~ctx:"transition guard" v)

let rec eval_stmt_list (env : (string, eval_value) Hashtbl.t) (stmts : Ast.stmt list) :
    (unit, error) result =
  match stmts with
  | [] -> Ok ()
  | s :: rest -> (
      match s.stmt with
      | SSkip -> eval_stmt_list env rest
      | SAssign (v, e) -> (
          match eval_iexpr env e with
          | Error _ as err -> err
          | Ok value ->
              Hashtbl.replace env v value;
              eval_stmt_list env rest)
      | SIf (c, tbr, fbr) -> (
          match eval_iexpr env c with
          | Error _ as err -> err
          | Ok cv -> (
              match eval_bool_of_value ~ctx:"if condition" cv with
              | Error _ as err -> err
              | Ok true -> (
                  match eval_stmt_list env tbr with
                  | Error _ as err -> err
                  | Ok () -> eval_stmt_list env rest)
              | Ok false -> (
                  match eval_stmt_list env fbr with
                  | Error _ as err -> err
                  | Ok () -> eval_stmt_list env rest)))
      | SMatch (e, branches, default) -> (
          match eval_iexpr env e with
          | Error _ as err -> err
          | Ok v ->
              let key = string_of_eval_value v in
              let selected =
                List.find_opt (fun (pat, _body) -> pat = key) branches
                |> Option.map snd
                |> Option.value ~default:default
              in
              (match eval_stmt_list env selected with
              | Error _ as err -> err
              | Ok () -> eval_stmt_list env rest))
      | SCall (inst, _args, _outs) ->
          eval_error
            (Printf.sprintf "calls not supported in evaluator yet (instance '%s')" inst))

let parse_trace_for_node ~(n : Ast.node) (trace_text : string) :
    ((string * eval_value) list list, error) result =
  let input_types =
    List.fold_left (fun m vd -> Hashtbl.replace m vd.vname vd.vty; m) (Hashtbl.create 16) n.inputs
  in
  let lines =
    String.split_on_char '\n' trace_text
    |> List.map String.trim
    |> List.filter (fun l -> l <> "" && not (String.length l > 0 && l.[0] = '#'))
  in
  let parse_pairs idx pairs =
    let rec loop seen acc = function
      | [] -> Ok (List.rev acc)
      | (name, raw) :: rest ->
          let name = String.trim name in
          let raw = strip_optional_quotes raw in
          if name = "" then eval_error (Printf.sprintf "empty variable name at step %d" idx)
          else if Hashtbl.mem seen name then
            eval_error (Printf.sprintf "duplicate assignment for '%s' at step %d" name idx)
          else
            let () = Hashtbl.replace seen name true in
            let ty_opt = Hashtbl.find_opt input_types name in
            (match ty_opt with
            | None ->
                eval_error
                  (Printf.sprintf "unknown input '%s' at step %d (expected node inputs only)" name idx)
            | Some ty -> (
                match parse_typed_value ~name ~ty raw with
                | Error _ as err -> err
                | Ok v -> loop seen ((name, v) :: acc) rest))
    in
    match loop (Hashtbl.create 16) [] pairs with
    | Error _ as err -> err
    | Ok assigns ->
        let missing =
          n.inputs
          |> List.filter_map (fun vd ->
                 if List.exists (fun (k, _) -> k = vd.vname) assigns then None else Some vd.vname)
        in
        if missing <> [] then
          eval_error
            (Printf.sprintf "missing input(s) at step %d: %s" idx (String.concat ", " missing))
        else Ok assigns
  in
  let parse_assign_line idx line =
    let chunks = split_assignments line in
    let rec to_pairs acc = function
      | [] -> Ok (List.rev acc)
      | chunk :: rest -> (
          match String.split_on_char '=' chunk with
          | [ lhs; rhs ] -> to_pairs ((lhs, rhs) :: acc) rest
          | _ ->
              eval_error
                (Printf.sprintf "invalid assignment '%s' at step %d (expected x=v)" chunk idx))
    in
    match to_pairs [] chunks with
    | Error _ as err -> err
    | Ok pairs -> parse_pairs idx pairs
  in
  let split_csv_by sep (line : string) : string list =
    line |> String.split_on_char sep |> List.map String.trim
  in
  let parse_csv_lines sep lines =
    match lines with
    | [] -> Ok []
    | header :: rows ->
        let headers = split_csv_by sep header in
        if headers = [] then eval_error "empty CSV header"
        else
          let parse_row idx row =
            let cells = split_csv_by sep row in
            if List.length cells <> List.length headers then
              eval_error
                (Printf.sprintf "CSV row %d has %d values, expected %d" idx (List.length cells)
                   (List.length headers))
            else parse_pairs idx (List.combine headers cells)
          in
          let rec loop idx acc = function
            | [] -> Ok (List.rev acc)
            | row :: rest -> (
                match parse_row idx row with
                | Error _ as err -> err
                | Ok parsed -> loop (idx + 1) (parsed :: acc) rest)
          in
          loop 0 [] rows
  in
  let parse_json_object_line idx (line : string) =
    let l = String.trim line in
    let n = String.length l in
    if n < 2 || l.[0] <> '{' || l.[n - 1] <> '}' then
      eval_error (Printf.sprintf "invalid JSON object at step %d" idx)
    else
      let content = String.sub l 1 (n - 2) |> String.trim in
      let parts =
        if content = "" then []
        else content |> String.split_on_char ',' |> List.map String.trim |> List.filter (( <> ) "")
      in
      let rec parse_parts acc = function
        | [] -> Ok (List.rev acc)
        | p :: rest ->
            let colon = String.index_opt p ':' in
            (match colon with
            | None -> eval_error (Printf.sprintf "invalid JSON field '%s' at step %d" p idx)
            | Some k ->
                let key = String.sub p 0 k |> String.trim |> strip_optional_quotes in
                let value = String.sub p (k + 1) (String.length p - k - 1) |> String.trim in
                parse_parts ((key, value) :: acc) rest)
      in
      match parse_parts [] parts with
      | Error _ as err -> err
      | Ok pairs -> parse_pairs idx pairs
  in
  let rec parse_all i acc = function
    | [] -> Ok (List.rev acc)
    | line :: rest -> (
        match parse_assign_line i line with
        | Error _ as err -> err
        | Ok step -> parse_all (i + 1) (step :: acc) rest)
  in
  match lines with
  | [] -> Ok []
  | first :: _ ->
      let is_jsonl = String.length first > 0 && first.[0] = '{' in
      let no_equals = List.for_all (fun l -> not (String.contains l '=')) lines in
      let is_csv =
        not is_jsonl && no_equals
        && (String.contains first ',' || String.contains first ';' || List.length lines >= 2)
      in
      if is_jsonl then
        let rec loop i acc = function
          | [] -> Ok (List.rev acc)
          | line :: rest -> (
              match parse_json_object_line i line with
              | Error _ as err -> err
              | Ok parsed -> loop (i + 1) (parsed :: acc) rest)
        in
        loop 0 [] lines
      else if is_csv then
        let comma = String.fold_left (fun c ch -> if ch = ',' then c + 1 else c) 0 first in
        let semi = String.fold_left (fun c ch -> if ch = ';' then c + 1 else c) 0 first in
        let sep = if semi > comma then ';' else ',' in
        parse_csv_lines sep lines
      else parse_all 0 [] lines

let eval_pass ~input_file ~trace_text ~with_state ~with_locals : (string, error) result =
  try
    let p = Frontend.parse_file input_file in
    let n =
      match p with
      | [ n ] -> Ok n
      | [] -> eval_error "empty program"
      | nodes ->
          eval_error
            (Printf.sprintf "evaluator currently supports a single top-level node, got %d"
               (List.length nodes))
    in
    match n with
    | Error _ as err -> err
    | Ok n ->
        match parse_trace_for_node ~n trace_text with
        | Error _ as err -> err
        | Ok steps ->
            let env : (string, eval_value) Hashtbl.t = Hashtbl.create 128 in
            List.iter (fun vd -> Hashtbl.replace env vd.vname (default_value_of_ty vd.vty)) n.locals;
            List.iter (fun vd -> Hashtbl.replace env vd.vname (default_value_of_ty vd.vty)) n.outputs;
            List.iter (fun vd -> Hashtbl.replace env vd.vname (default_value_of_ty vd.vty)) n.inputs;
            let current_state = ref n.init_state in
            let transitions_from_state = Ast_utils.transitions_from_state_fn n in
            let lines = ref [] in
            let append_line parts = lines := (String.concat ", " parts) :: !lines in
            let run_step idx assigns =
              List.iter (fun (k, v) -> Hashtbl.replace env k v) assigns;
              let candidates = transitions_from_state !current_state in
              let rec filter_enabled acc = function
                | [] -> Ok (List.rev acc)
                | t :: rest -> (
                    match eval_guard env t.guard with
                    | Error _ as err -> err
                    | Ok true -> filter_enabled (t :: acc) rest
                    | Ok false -> filter_enabled acc rest)
              in
              match filter_enabled [] candidates with
              | Error _ as err -> err
              | Ok [] ->
                  eval_error
                    (Printf.sprintf "no enabled transition from state '%s' at step %d"
                       !current_state idx)
              | Ok [ t ] -> (
                  match eval_stmt_list env t.body with
                  | Error _ as err -> err
                  | Ok () ->
                      current_state := t.dst;
                      let inputs =
                        List.map
                          (fun vd ->
                            let v =
                              Hashtbl.find_opt env vd.vname
                              |> Option.value ~default:(default_value_of_ty vd.vty)
                            in
                            vd.vname ^ "=" ^ string_of_eval_value v)
                          n.inputs
                      in
                      let outputs =
                        List.map
                          (fun vd ->
                            let v =
                              Hashtbl.find_opt env vd.vname
                              |> Option.value ~default:(default_value_of_ty vd.vty)
                            in
                            vd.vname ^ "=" ^ string_of_eval_value v)
                          n.outputs
                      in
                      let state = if with_state then [ "state=" ^ !current_state ] else [] in
                      let locals =
                        if with_locals then
                          List.map
                            (fun vd ->
                              let v =
                                Hashtbl.find_opt env vd.vname
                                |> Option.value ~default:(default_value_of_ty vd.vty)
                              in
                              vd.vname ^ "=" ^ string_of_eval_value v)
                            n.locals
                        else []
                      in
                      append_line (("step=" ^ string_of_int idx) :: state @ inputs @ outputs @ locals);
                      Ok ())
              | Ok enabled ->
                  let dsts = enabled |> List.map (fun t -> t.dst) |> String.concat ", " in
                  eval_error
                    (Printf.sprintf
                       "non-deterministic execution from state '%s' at step %d (enabled dst: %s)"
                       !current_state idx dsts)
            in
            let rec loop i = function
              | [] -> Ok ()
              | step :: rest -> (
                  match run_step i step with
                  | Error _ as err -> err
                  | Ok () -> loop (i + 1) rest)
            in
            match loop 0 steps with
            | Error _ as err -> err
            | Ok () -> Ok (String.concat "\n" (List.rev !lines))
  with exn -> Error (Stage_error ("eval: " ^ Printexc.to_string exn))

let run (cfg : config) : (outputs, error) result =
  let _ = cfg in
  Error (Stage_error "Legacy Pipeline.run is removed. Use Pipeline_v2_indep.run.")

let run_with_callbacks ?(should_cancel = fun () -> false) (cfg : config)
    ~(on_outputs_ready : outputs -> unit)
    ~(on_goals_ready : string list * int list -> unit)
    ~(on_goal_done :
       int -> string -> string -> float -> string option -> string -> string option -> unit) :
    (outputs, error) result =
  let _ = (should_cancel, cfg, on_outputs_ready, on_goals_ready, on_goal_done) in
  Error
    (Stage_error
       "Legacy Pipeline.run_with_callbacks is removed. Use Pipeline_v2_indep.run_with_callbacks.")
