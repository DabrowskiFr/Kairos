type goal_info =
  string * string * float * string option * string * string option


type outputs = {
  obc_text : string;
  why_text : string;
  vc_text : string;
  smt_text : string;
  dot_text : string;
  labels_text : string;
  stage_meta : (string * (string * string) list) list;
  goals : goal_info list;
  obcplus_sequents : (int * string) list;
  task_sequents : (string list * string) list;
  vc_locs : (int * Ast.loc) list;
  obcplus_spans : (int * (int * int)) list;
  vc_locs_ordered : Ast.loc list;
  obcplus_spans_ordered : (int * int) list;
  vc_spans_ordered : (int * int) list;
  why_spans : (int * (int * int)) list;
  vc_ids_ordered : int list;
  obcplus_time_s : float;
  why_time_s : float;
  automaton_time_s : float;
  automaton_build_time_s : float;
  why3_prep_time_s : float;
  dot_png : string option;
}

type monitor_outputs = {
  dot_text : string;
  labels_text : string;
  dot_png : string option;
  stage_meta : (string * (string * string) list) list;
}

type obc_outputs = { obc_text : string; stage_meta : (string * (string * string) list) list }
type why_outputs = { why_text : string; stage_meta : (string * (string * string) list) list }
type obligations_outputs = { vc_text : string; smt_text : string }

type ast_stages = {
  parsed : Ast.program;
  automaton : Ast.program;
  contracts : Ast.program;
  monitor : Ast.program;
  obc : Ast.program;
}

type config = {
  input_file : string;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  timeout_s : int;
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
        offset := !offset + String.length sep
      );
      let start_pos = !offset in
      Buffer.add_string buf block;
      let end_pos = start_pos + String.length block in
      spans := (start_pos, end_pos) :: !spans;
      offset := end_pos)
    blocks;
  (Buffer.contents buf, List.rev !spans)

let program_stats (p:Ast.program) : (string * string) list =
  let nodes = List.length p in
  let transitions =
    List.fold_left (fun acc (n:Ast.node) -> acc + List.length (Ast.node_trans n)) 0 p
  in
  let requires =
    List.fold_left
      (fun acc (n:Ast.node) ->
         acc
         + List.fold_left
             (fun a (t:Ast.transition) -> a + List.length (Ast.transition_requires t))
             0
             (Ast.node_trans n))
      0 p
  in
  let ensures =
    List.fold_left
      (fun acc (n:Ast.node) ->
         acc
         + List.fold_left
             (fun a (t:Ast.transition) -> a + List.length (Ast.transition_ensures t))
             0
             (Ast.node_trans n))
      0 p
  in
  let guards =
    List.fold_left
      (fun acc n ->
         acc +
         List.fold_left
           (fun a t -> if Ast.transition_guard t = None then a else a + 1)
          0 (Ast.node_trans n))
      0 p
  in
  let locals =
    List.fold_left (fun acc n -> acc + List.length (Ast.node_locals n)) 0 p
  in
  [("nodes", string_of_int nodes);
   ("transitions", string_of_int transitions);
   ("requires", string_of_int requires);
   ("ensures", string_of_int ensures);
   ("guards", string_of_int guards);
   ("locals", string_of_int locals)]

let stage_meta (asts:ast_stages) : (string * (string * string) list) list =
  let head_opt = function
    | [] -> None
    | x :: _ -> Some x
  in
  let user =
    match asts.parsed |> head_opt with
    | None -> ("user", [])
    | Some n ->
        let info = Ast.node_parse_info_or_empty n in
        ( "user",
          [ ("source_path", Option.value ~default:"" info.source_path);
            ("text_hash", Option.value ~default:"" info.text_hash);
            ("parse_errors", string_of_int (List.length info.parse_errors));
            ("warnings", string_of_int (List.length info.warnings)) ] )
  in
  let automaton =
    match asts.automaton |> head_opt with
    | None -> ("automaton", [])
    | Some n ->
        let info = Ast.node_automaton_info_or_empty n in
        ( "automaton",
          [ ("states", string_of_int info.residual_state_count);
            ("edges", string_of_int info.residual_edge_count);
            ("warnings", string_of_int (List.length info.warnings)) ] )
  in
  let contracts =
    match asts.contracts |> head_opt with
    | None -> ("contracts", [])
    | Some n ->
        let info = Ast.node_contracts_info_or_empty n in
        ( "contracts",
          [ ("origins", string_of_int (List.length info.contract_origin_map));
            ("warnings", string_of_int (List.length info.warnings)) ] )
  in
  let monitor =
    match asts.monitor |> head_opt with
    | None -> ("monitor", [])
    | Some n ->
        let info = Ast.node_monitor_info_or_empty n in
        ( "monitor",
          [ ("atoms", string_of_int info.atom_count);
            ("states", string_of_int (List.length info.monitor_state_ctors));
            ("warnings", string_of_int (List.length info.warnings)) ] )
  in
  let obc =
    match asts.obc |> head_opt with
    | None -> ("obc", [])
    | Some n ->
        let info = Ast.node_obc_info_or_empty n in
        ( "obc",
          [ ("ghost_locals", string_of_int (List.length info.ghost_locals_added));
            ("pre_k_infos", string_of_int (List.length info.pre_k_infos));
            ("folds", string_of_int (List.length info.fold_infos));
            ("warnings", string_of_int (List.length info.warnings)) ] )
  in
  [ user; automaton; contracts; monitor; obc ]

let emit_automaton_debug_stats (p:Ast.program) =
  let nodes = List.length p in
  let edges =
    List.fold_left (fun acc n -> acc + List.length (Ast.node_trans n)) 0 p
  in
  Log.stage_info
    (Some Stage_names.Automaton)
    "automaton stats"
    [
      "nodes", string_of_int nodes;
      "edges", string_of_int edges;
    ]

let reid_with_origin (x:'a Ast.with_origin) : 'a Ast.with_origin =
  let new_id = Provenance.fresh_id () in
  Provenance.add_parents ~child:new_id ~parents:[x.oid];
  { x with oid = new_id }

let reid_program (p:Ast.program) : Ast.program =
  let reid_fo = reid_with_origin in
  let reid_ltl = reid_with_origin in
  let reid_trans (t:Ast.transition) =
    let t =
      Ast.with_transition_lemmas
        (List.map reid_fo (Ast.transition_lemmas t))
        t
    in
    t
    |> Ast.with_transition_requires (List.map reid_fo (Ast.transition_requires t))
    |> Ast.with_transition_ensures (List.map reid_fo (Ast.transition_ensures t))
  in
  let reid_node (n:Ast.node) =
    {
      n with
      contracts =
        { assumes = List.map reid_ltl (Ast.node_assumes n);
          guarantees = List.map reid_ltl (Ast.node_guarantees n); };
      body = { (Ast.node_body n) with trans = List.map reid_trans (Ast.node_trans n); };
    }
  in
  List.map reid_node p |> Ast.ensure_program_uids

let build_ast ?(log=false) ~input_file () : (ast_stages, error) result =
  let parse () =
    try
      if log then Log.stage_start Stage_names.Parsed;
      let t0 = Unix.gettimeofday () in
      let p_parsed = Frontend.parse_file input_file in
      if log then
        Log.stage_end Stage_names.Parsed
          (int_of_float ((Unix.gettimeofday () -. t0) *. 1000.))
          (program_stats p_parsed);
      Ok p_parsed
    with exn -> Error (Parse_error (Printexc.to_string exn))
  in
  match parse () with
  | Error _ as err -> err
  | Ok p_parsed ->
      try
        let t1 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Automaton;
        let p_automaton =
          p_parsed
          |> Middle_end.stage_automaton
          |> reid_program
        in
        emit_automaton_debug_stats p_automaton;
        if log then
          Log.stage_end Stage_names.Automaton
            (int_of_float ((Unix.gettimeofday () -. t1) *. 1000.))
            (program_stats p_automaton);
        let t2 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Contracts;
        let p_contracts =
          p_automaton
          |> Middle_end.stage_contracts
          |> reid_program
        in
        if log then
          Log.stage_end Stage_names.Contracts
            (int_of_float ((Unix.gettimeofday () -. t2) *. 1000.))
            (program_stats p_contracts);
        let t3 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Monitor;
        let p_monitor =
          p_contracts
          |> Middle_end.stage_monitor_injection
          |> reid_program
        in
        if log then
          Log.stage_end Stage_names.Monitor
            (int_of_float ((Unix.gettimeofday () -. t3) *. 1000.))
            (program_stats p_monitor);
        let t4 = Unix.gettimeofday () in
        if log then Log.stage_start Stage_names.Obc;
        let p_obc =
          p_monitor
          |> Obc_stage.run
          |> reid_program
        in
        if log then
          Log.stage_end Stage_names.Obc
            (int_of_float ((Unix.gettimeofday () -. t4) *. 1000.))
            (program_stats p_obc);
        Ok { parsed = p_parsed; automaton = p_automaton; contracts = p_contracts; monitor = p_monitor; obc = p_obc }
      with exn ->
        Error (Stage_error (Printexc.to_string exn))

let build_obcplus_sequents (p_obc:Ast.program) : (int * string) list =
  let p_obc = p_obc in
  let acc = ref [] in
  let add_node (node:Ast.node) =
    List.iter
      (fun (t:Ast.transition) ->
         List.iter
           (fun (ens:Ast.fo_o) ->
                let vcid = ens.oid in
              let reqs =
                List.map (fun (r:Ast.fo_o) -> Support.string_of_fo r.value)
                  (Ast.transition_requires t)
              in
              let ensure = Support.string_of_fo ens.value in
              let buf = Buffer.create 256 in
              List.iter (fun r -> Buffer.add_string buf (r ^ "\n")) reqs;
              Buffer.add_string buf "--------------------\n";
              Buffer.add_string buf ensure;
                acc := (vcid, Buffer.contents buf) :: !acc)
           (Ast.transition_ensures t))
      (Ast.node_trans node)
  in
  List.iter add_node p_obc;
  List.rev !acc

let build_vcid_locs (p_parsed:Ast.program)
  : (int * Ast.loc) list * Ast.loc list =
  let p_parsed = p_parsed in
  let acc = ref [] in
  let ordered = ref [] in
  let add_node (node:Ast.node) =
    List.iter
      (fun (t:Ast.transition) ->
         List.iter
           (fun (ens:Ast.fo_o) ->
              match ens.loc with
              | None -> ()
              | Some loc ->
                  acc := (ens.oid, loc) :: !acc;
                  ordered := loc :: !ordered)
           (Ast.transition_ensures t))
      (Ast.node_trans node)
  in
  List.iter add_node p_parsed;
  (List.rev !acc, List.rev !ordered)


let dot_png_from_text (dot_text:string) : string option =
  let open Bos in
  match OS.File.tmp "kairos_ide_%s.dot" with
  | Error _ -> None
  | Ok dot_file ->
      let png_file = Fpath.set_ext "png" dot_file in
      begin
        match OS.File.write dot_file dot_text with
        | Error _ ->
            ignore (OS.File.delete dot_file);
            None
        | Ok () ->
            let cmd = Cmd.(v "dot" % "-Tpng" % p dot_file % "-o" % p png_file) in
            match OS.Cmd.run cmd with
            | Ok () ->
                ignore (OS.File.delete dot_file);
                Some (Fpath.to_string png_file)
            | Error _ ->
                ignore (OS.File.delete dot_file);
                ignore (OS.File.delete png_file);
                None
      end

let monitor_pass ~generate_png ~input_file : (monitor_outputs, error) result =
  Provenance.reset ();
  match build_ast ~input_file () with
  | Error _ as err -> err
  | Ok asts ->
      try
        let dot_text, labels_text =
          Dot_emit.dot_monitor_program ~show_labels:false asts.automaton
        in
        let dot_png = if generate_png then dot_png_from_text dot_text else None in
        Ok { dot_text; labels_text; dot_png; stage_meta = stage_meta asts }
      with exn ->
        Error (Io_error (Printexc.to_string exn))

let obc_pass ~input_file : (obc_outputs, error) result =
  Provenance.reset ();
  match build_ast ~input_file () with
  | Error _ as err -> err
  | Ok asts ->
      try
        let obc_text = Backend.emit_obc asts.obc in
        Ok { obc_text; stage_meta = stage_meta asts }
      with exn ->
        Error (Stage_error (Printexc.to_string exn))

let why_pass ~prefix_fields ~input_file : (why_outputs, error) result =
  Provenance.reset ();
  match build_ast ~input_file () with
  | Error _ as err -> err
  | Ok asts ->
      try
        let why_text = Stage_io.emit_why ~prefix_fields ~output_file:None asts.obc in
        Ok { why_text; stage_meta = stage_meta asts }
      with exn ->
        Error (Why3_error (Printexc.to_string exn))

let obligations_pass ~prefix_fields ~prover ~input_file : (obligations_outputs, error) result =
  Provenance.reset ();
  match build_ast ~input_file () with
  | Error _ as err -> err
  | Ok asts ->
      try
        let why_text = Stage_io.emit_why ~prefix_fields ~output_file:None asts.obc in
        let vc_tasks = Why_prove.dump_why3_tasks_with_attrs ~text:why_text in
        let smt_tasks = Why_prove.dump_smt2_tasks ~prover ~text:why_text in
        let vc_text, _vc_spans =
          join_blocks_with_spans ~sep:"\n(* ---- goal ---- *)\n" vc_tasks
        in
        let smt_text = join_blocks ~sep:"\n; ---- goal ----\n" smt_tasks in
        Ok { vc_text; smt_text }
      with exn ->
        Error (Why3_error (Printexc.to_string exn))

let run (cfg:config) : (outputs, error) result =
  Provenance.reset ();
  let t_build0 = Unix.gettimeofday () in
  match build_ast ~input_file:cfg.input_file () with
  | Error _ as err -> err
  | Ok asts ->
      try
        let automaton_build_time_s = Unix.gettimeofday () -. t_build0 in
        let t_obc0 = Unix.gettimeofday () in
        let obc_text, obcplus_spans = Obc_emit.compile_program_with_spans asts.obc in
        let obcplus_sequents = build_obcplus_sequents asts.obc in
        let obcplus_time_s = Unix.gettimeofday () -. t_obc0 in
        let vc_locs, vc_locs_ordered = build_vcid_locs asts.parsed in
        let obcplus_spans_ordered = List.map snd obcplus_spans in
        let t_why0 = Unix.gettimeofday () in
        let why_ast = Backend.build_why_ast ~prefix_fields:cfg.prefix_fields asts.obc in
        let why_text, why_spans = Emit.emit_program_ast_with_spans why_ast in
        let why_time_s = Unix.gettimeofday () -. t_why0 in
        let t_prep0 = Unix.gettimeofday () in
        let task_sequents = Why_prove.task_sequents ~text:why_text in
        let why3_prep_time_s = Unix.gettimeofday () -. t_prep0 in
        let vc_tasks =
          if cfg.generate_vc_text then
            Why_prove.dump_why3_tasks_with_attrs ~text:why_text
          else
            []
        in
        let why_ids_per_task = Why_prove.task_goal_wids ~text:why_text in
        let vc_ids_ordered =
          List.map
            (fun wids ->
               let vc_id = Provenance.fresh_id () in
               Provenance.add_parents ~child:vc_id ~parents:wids;
               vc_id)
            why_ids_per_task
        in
        let smt_tasks =
          if cfg.generate_smt_text then
            Why_prove.dump_smt2_tasks ~prover:cfg.prover ~text:why_text
          else
            []
        in
        let vc_text, vc_spans_ordered =
          if cfg.generate_vc_text then
            join_blocks_with_spans ~sep:"\n(* ---- goal ---- *)\n" vc_tasks
          else
            ("", [])
        in
        let smt_text =
          if cfg.generate_smt_text then
            join_blocks ~sep:"\n; ---- goal ----\n" smt_tasks
          else
            ""
        in
        let automaton_time_s, dot_text, labels_text =
          if cfg.generate_monitor_text then
            let t0 = Unix.gettimeofday () in
            let dot_text, labels_text =
              Dot_emit.dot_monitor_program ~show_labels:false asts.automaton
            in
            (Unix.gettimeofday () -. t0, dot_text, labels_text)
          else
            (0.0, "", "")
        in
        let should_prove = cfg.prove && not cfg.wp_only in
        let goals =
          if should_prove then
            let summary, goals =
              Why_prove.prove_text_detailed_with_callbacks
                ~timeout:cfg.timeout_s
                ~prover:cfg.prover
                ?prover_cmd:cfg.prover_cmd
                ~text:why_text
                ~vc_ids_ordered:(Some vc_ids_ordered)
                ~on_goal_start:(fun _ _ -> ())
                ~on_goal_done:(fun _ _ _ _ _ _ _ -> ())
                ()
            in
            let _ = summary in
            goals
          else
            []
        in
        let dot_png =
          if cfg.generate_dot_png && dot_text <> "" then dot_png_from_text dot_text else None
        in
        let meta = stage_meta asts in
        Ok {
          obc_text;
          why_text;
          vc_text;
          smt_text;
          dot_text;
          labels_text;
          stage_meta = meta;
          goals;
          obcplus_sequents;
          task_sequents;
          vc_locs;
          obcplus_spans;
          vc_locs_ordered;
          obcplus_spans_ordered;
          vc_spans_ordered;
          why_spans;
          vc_ids_ordered;
          obcplus_time_s;
          why_time_s;
          automaton_time_s;
          automaton_build_time_s;
          why3_prep_time_s;
          dot_png;
        }
      with exn ->
        Error (Stage_error (Printexc.to_string exn))

let run_with_callbacks
  (cfg:config)
  ~(on_outputs_ready:outputs -> unit)
  ~(on_goals_ready:string list * int list -> unit)
  ~(on_goal_done:int -> string -> string -> float -> string option -> string -> string option -> unit)
  : (outputs, error) result =
  Provenance.reset ();
  let t_build0 = Unix.gettimeofday () in
  match build_ast ~input_file:cfg.input_file () with
  | Error _ as err -> err
  | Ok asts ->
      try
        let automaton_build_time_s = Unix.gettimeofday () -. t_build0 in
        let t_obc0 = Unix.gettimeofday () in
        let obc_text, obcplus_spans = Obc_emit.compile_program_with_spans asts.obc in
        let obcplus_sequents = build_obcplus_sequents asts.obc in
        let obcplus_time_s = Unix.gettimeofday () -. t_obc0 in
        let vc_locs, vc_locs_ordered = build_vcid_locs asts.parsed in
        let obcplus_spans_ordered = List.map snd obcplus_spans in
        let t_why0 = Unix.gettimeofday () in
        let why_ast = Backend.build_why_ast ~prefix_fields:cfg.prefix_fields asts.obc in
        let why_text, why_spans = Emit.emit_program_ast_with_spans why_ast in
        let why_time_s = Unix.gettimeofday () -. t_why0 in
        let vc_tasks =
          if cfg.generate_vc_text then
            Why_prove.dump_why3_tasks_with_attrs ~text:why_text
          else
            []
        in
        let why_ids_per_task = Why_prove.task_goal_wids ~text:why_text in
        let vc_ids_ordered =
          List.map
            (fun wids ->
               let vc_id = Provenance.fresh_id () in
               Provenance.add_parents ~child:vc_id ~parents:wids;
               vc_id)
            why_ids_per_task
        in
        let t_prep0 = Unix.gettimeofday () in
        let task_sequents = Why_prove.task_sequents ~text:why_text in
        let why3_prep_time_s = Unix.gettimeofday () -. t_prep0 in
        let smt_tasks =
          if cfg.generate_smt_text then
            Why_prove.dump_smt2_tasks ~prover:cfg.prover ~text:why_text
          else
            []
        in
        let vc_text, vc_spans_ordered =
          if cfg.generate_vc_text then
            join_blocks_with_spans ~sep:"\n(* ---- goal ---- *)\n" vc_tasks
          else
            ("", [])
        in
        let smt_text =
          if cfg.generate_smt_text then
            join_blocks ~sep:"\n; ---- goal ----\n" smt_tasks
          else
            ""
        in
        let automaton_time_s, dot_text, labels_text =
          if cfg.generate_monitor_text then
            let t0 = Unix.gettimeofday () in
            let dot_text, labels_text =
              Dot_emit.dot_monitor_program ~show_labels:false asts.automaton
            in
            (Unix.gettimeofday () -. t0, dot_text, labels_text)
          else
            (0.0, "", "")
        in
        let dot_png =
          if cfg.generate_dot_png && dot_text <> "" then dot_png_from_text dot_text else None
        in
        let meta = stage_meta asts in
        let goal_names =
          if cfg.generate_vc_text then (
            let goal_re = Str.regexp "^\\s*goal[ \t]+\\([A-Za-z0-9_]+\\)\\b" in
            let extract_goal_name task =
              let lines = String.split_on_char '\n' task in
              match List.find_opt (fun line -> Str.string_match goal_re line 0) lines with
              | None -> "goal"
              | Some line ->
                  ignore (Str.string_match goal_re line 0);
                  Str.matched_group 1 line
            in
            List.map extract_goal_name vc_tasks
          ) else
            List.mapi (fun i _ -> Printf.sprintf "goal%d" (i + 1)) vc_ids_ordered
        in
        on_outputs_ready {
          obc_text;
          why_text;
          vc_text;
          smt_text;
          dot_text;
          labels_text;
          stage_meta = meta;
          goals = [];
          obcplus_sequents;
          task_sequents;
          vc_locs;
          obcplus_spans;
          vc_locs_ordered;
          obcplus_spans_ordered;
          vc_spans_ordered;
          why_spans;
          vc_ids_ordered;
          obcplus_time_s;
          why_time_s;
          automaton_time_s;
          automaton_build_time_s;
          why3_prep_time_s;
          dot_png;
        };
        on_goals_ready (goal_names, vc_ids_ordered);
        let should_prove = cfg.prove && not cfg.wp_only in
        let goals =
          if should_prove then
            let summary, goals =
              Why_prove.prove_text_detailed_with_callbacks
                ~timeout:cfg.timeout_s
                ~prover:cfg.prover
                ?prover_cmd:cfg.prover_cmd
                ~text:why_text
                ~vc_ids_ordered:(Some vc_ids_ordered)
                ~on_goal_start:(fun _ _ -> ())
                ~on_goal_done
                ()
            in
            let _ = summary in
            goals
          else
            []
        in
        Ok {
          obc_text;
          why_text;
          vc_text;
          smt_text;
          dot_text;
          labels_text;
          stage_meta = meta;
          goals;
          obcplus_sequents;
          task_sequents;
          vc_locs;
          obcplus_spans;
          vc_locs_ordered;
          obcplus_spans_ordered;
          vc_spans_ordered;
          why_spans;
          vc_ids_ordered;
          obcplus_time_s;
          why_time_s;
          automaton_time_s;
          automaton_build_time_s;
          why3_prep_time_s;
          dot_png;
        }
      with exn ->
        Error (Stage_error (Printexc.to_string exn))
