open Cmdliner

let docs_general = Manpage.s_common_options
let docs_proof = "PROOF"
let docs_graph = "GRAPH DUMPS"
let docs_text = "TEXT EXPORTS"
let why3_proof = "WHY3"
let docs_kobj = "KOBJ"

(* Parsed CLI arguments *)
type cli_args = {
  file : string;
  prove : bool;
  prover : string;
  prover_cmd : string option;
  timeout_s : int;
  dump_dot_explicit : string option;
  dump_automata : string option;
  dump_automata_short : string option;
  dump_product : string option;
  dump_product_short : string option;
  dump_canonical : string option;
  dump_canonical_short : string option;
  dump_obligations_map : string option;
  dump_normalized_program : string option;
  dump_why : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  dump_kobj_summary : string option;
  dump_kobj_clauses : string option;
  dump_kobj_product : string option;
  dump_kobj_contracts : string option;
}

(* Mutually exclusive dump modes. Each one corresponds to a single "artifact export"
   branch and bypasses the general run/prove flow. *)
type dump_mode =
  | Dump_product_explicit of { out : string }
  | Dump_automata of { out : string; short : bool }
  | Dump_product_merge of { out : string; short : bool }
  | Dump_canonical of { out : string; short : bool }
  | Dump_obligations_map of { out : string }
  | Dump_normalized_program of { out : string }
  | Dump_kobj_summary of { out : string }
  | Dump_kobj_clauses of { out : string }
  | Dump_kobj_product of { out : string }
  | Dump_kobj_contracts of { out : string }

(* Resolved action chosen after validation. This keeps execution code small and
   avoids mixing parsing concerns with backend dispatch. *)
type action =
  | Dump of dump_mode
  | Dump_why of { out : string }
  | Dump_why3_vc of { out : string }
  | Dump_smt2 of { out : string }
  | Run of { prove : bool }

let write_target out text =
  match out with
  | "-" -> print_string text
  | path -> Artifact_io.write_text path text

let dot_dump_base (path : string) : string =
  if Filename.check_suffix path ".dot" then Filename.chop_suffix path ".dot" else path

let ensure_dot_path (path : string) : string =
  if Filename.check_suffix path ".dot" then path else path ^ ".dot"

let labels_path_of_dot (dot_path : string) : string = dot_dump_base dot_path ^ ".labels"

let strip_dot_legend ~(legend_id : string) (dot_text : string) : string =
  let lines = String.split_on_char '\n' dot_text in
  let rec drop_legend_block acc = function
    | [] -> List.rev acc
    | line :: rest ->
        if String.contains line '[' && String.contains line '<'
           && String.starts_with ~prefix:("  " ^ legend_id ^ " [") line
        then drop_until_block_end acc rest
        else if
          String.contains line '>'
          && String.ends_with ~suffix:("-> " ^ legend_id ^ " [style=invis,weight=0];")
               (String.trim line)
        then drop_legend_block acc rest
        else drop_legend_block (line :: acc) rest
  and drop_until_block_end acc = function
    | [] -> List.rev acc
    | line :: rest ->
        if String.trim line = "</TABLE>>];" || String.trim line = "    </TABLE>>];" then
          drop_legend_block acc rest
        else drop_until_block_end acc rest
  in
  String.concat "\n" (drop_legend_block [] lines)

let report_failed_goals (goals : Lsp_protocol.goal_info list) : string list =
  let total = List.length goals in
  let failure_info (_, status, _, dump_path, source, vcid) =
    let status = String.lowercase_ascii status in
    if status <> "valid" && status <> "proved" && status <> "unknown" then
      Some (status, dump_path, source, vcid)
    else None
  in
  List.mapi
    (fun idx ((goal, _, time_s, _, _, _) as info) ->
      match failure_info info with
      | None -> None
      | Some (status, dump_path, source, vcid) ->
          Some
            (Printf.sprintf "goal %d/%d failed: %s (source=%s%s%s, time=%.3fs)" (idx + 1)
               total goal source
               (match vcid with None -> "" | Some id -> ", vcid=" ^ id)
               (match dump_path with None -> "" | Some p -> ", dump=" ^ p)
               time_s))
    goals
  |> List.filter_map Fun.id

let engine = Engine_service.string_of_engine Engine_service.Default

(* Request builders centralize the common engine/input setup expected by each
   backend entrypoint. *)
let instrumentation_req args =
  { Lsp_protocol.input_file = args.file; generate_png = false; engine }

let why_req args =
  { Lsp_protocol.input_file = args.file; prefix_fields = false; engine }

let obligations_req args =
  { Lsp_protocol.input_file = args.file; prover = args.prover; prefix_fields = false; engine }

let kobj_req args = { Lsp_protocol.input_file = args.file; engine }

let run_req args =
  {
    Lsp_protocol.input_file = args.file;
    engine;
    prover = args.prover;
    prover_cmd = args.prover_cmd;
    wp_only = false;
    smoke_tests = false;
    timeout_s = args.timeout_s;
    selected_goal_index = None;
    compute_proof_diagnostics = false;
    prefix_fields = false;
    prove = args.prove;
    generate_vc_text = Option.is_some args.dump_why3_vc;
    generate_smt_text = Option.is_some args.dump_smt2;
    generate_dot_png = false;
  }

(* Thin wrappers around backend passes so the execution layer can focus on the
   selected action instead of repeating result/error plumbing. *)
let with_instrumentation_pass args f =
  match Lsp_backend.instrumentation_pass (instrumentation_req args) with
  | Error msg -> `Error (false, msg)
  | Ok out -> f out

let with_why_pass args f =
  match Lsp_backend.why_pass (why_req args) with
  | Error msg -> `Error (false, msg)
  | Ok out -> f out

let with_obligations_pass args f =
  match Lsp_backend.obligations_pass (obligations_req args) with
  | Error msg -> `Error (false, msg)
  | Ok out -> f out

let with_kobj_summary args f =
  match Lsp_backend.kobj_summary (kobj_req args) with
  | Error msg -> `Error (false, msg)
  | Ok text -> f text

let with_kobj_clauses args f =
  match Lsp_backend.kobj_clauses (kobj_req args) with
  | Error msg -> `Error (false, msg)
  | Ok text -> f text

let with_kobj_product args f =
  match Lsp_backend.kobj_product (kobj_req args) with
  | Error msg -> `Error (false, msg)
  | Ok text -> f text

let with_kobj_contracts args f =
  match Lsp_backend.kobj_contracts (kobj_req args) with
  | Error msg -> `Error (false, msg)
  | Ok text -> f text

let with_normalized_program args f =
  match Lsp_backend.normalized_program (kobj_req args) with
  | Error msg -> `Error (false, msg)
  | Ok text -> f text

let write_text_output out text =
  write_target out text;
  `Ok ()

let impossible_missing_option name = failwith ("internal error: missing CLI option for " ^ name)

let get_some name = function Some x -> x | None -> impossible_missing_option name

(* Shared file-emission helpers. They preserve the current on-disk bundle layout
   and filename conventions while keeping the execution branches short. *)
let write_automata_bundle ~out ~short (artifacts : Lsp_protocol.automata_outputs) =
  let dot_base = dot_dump_base out in
  write_target out (artifacts.guarantee_automaton_text ^ "\n\n" ^ artifacts.assume_automaton_text);
  write_target
    (dot_base ^ ".assume.dot")
    (if short then strip_dot_legend ~legend_id:"legend_a" artifacts.assume_automaton_dot
     else artifacts.assume_automaton_dot);
  write_target
    (dot_base ^ ".guarantee.dot")
    (if short then strip_dot_legend ~legend_id:"legend_g" artifacts.guarantee_automaton_dot
     else artifacts.guarantee_automaton_dot);
  write_target (dot_base ^ ".assume.tex") artifacts.assume_automaton_tex;
  write_target (dot_base ^ ".guarantee.tex") artifacts.guarantee_automaton_tex;
  `Ok ()

let write_product_bundle ~out ~short ~explicit (artifacts : Lsp_protocol.automata_outputs) =
  let dot_base = dot_dump_base out in
  write_target out artifacts.product_text;
  write_target
    (dot_base ^ ".dot")
    (let dot = if explicit then artifacts.product_dot_explicit else artifacts.product_dot in
     if short then strip_dot_legend ~legend_id:"legend_product" dot else dot);
  write_target (dot_base ^ ".tex") (if explicit then artifacts.product_tex_explicit else artifacts.product_tex);
  `Ok ()

let write_canonical_bundle ~out ~short (artifacts : Lsp_protocol.automata_outputs) =
  let dot_path = ensure_dot_path out in
  let dot_base = dot_dump_base dot_path in
  write_target
    dot_path
    (if short then strip_dot_legend ~legend_id:"legend_canonical" artifacts.canonical_dot
     else artifacts.canonical_dot);
  write_target (dot_base ^ ".tex") artifacts.canonical_tex;
  write_target (dot_base ^ ".txt") artifacts.canonical_text;
  `Ok ()

let write_dot_bundle ~out ~explicit_product (artifacts : Lsp_protocol.automata_outputs) =
  let dot_path = ensure_dot_path out in
  let dot_base = dot_dump_base dot_path in
  write_target dot_path artifacts.dot_text;
  write_target (labels_path_of_dot dot_path) artifacts.labels_text;
  write_target (dot_base ^ ".assume.dot") artifacts.assume_automaton_dot;
  write_target (dot_base ^ ".guarantee.dot") artifacts.guarantee_automaton_dot;
  write_target (dot_base ^ ".assume.tex") artifacts.assume_automaton_tex;
  write_target (dot_base ^ ".guarantee.tex") artifacts.guarantee_automaton_tex;
  write_target
    (dot_base ^ ".product.dot")
    (if explicit_product then artifacts.product_dot_explicit else artifacts.product_dot);
  write_target
    (dot_base ^ ".product.tex")
    (if explicit_product then artifacts.product_tex_explicit else artifacts.product_tex);
  `Ok ()

let dump_mode_count args =
  List.fold_left
    (fun acc opt -> if Option.is_some opt then acc + 1 else acc)
    0
    [
      args.dump_dot_explicit;
      args.dump_automata;
      args.dump_automata_short;
      args.dump_product;
      args.dump_product_short;
      args.dump_canonical;
      args.dump_canonical_short;
      args.dump_obligations_map;
      args.dump_normalized_program;
      args.dump_kobj_summary;
      args.dump_kobj_clauses;
      args.dump_kobj_product;
      args.dump_kobj_contracts;
    ]

let has_dump_mode args = dump_mode_count args > 0

let has_why_mode args =
  args.prove || Option.is_some args.dump_why || Option.is_some args.dump_why3_vc
  || Option.is_some args.dump_smt2

(* Validation only checks user-facing CLI consistency rules: incompatible dump vs
   proof modes, and the "at most one dump mode" constraint. *)
let validate_args args =
  if has_dump_mode args && has_why_mode args then
    Error
      "--dump-product/--dump-automata/--dump-automata-short/--dump-product-merge/--dump-product-merge-short/--dump-canonical/--dump-canonical-short/--dump-obligations-map/--dump-normalized-program/--dump-kobj-* cannot be combined with --prove or Why3 dump options"
  else if dump_mode_count args > 1 then
    Error
      "Only one dump mode can be selected among --dump-product/--dump-automata/--dump-automata-short/--dump-product-merge/--dump-product-merge-short/--dump-canonical/--dump-canonical-short/--dump-obligations-map/--dump-normalized-program/--dump-kobj-*"
  else Ok ()

(* Preserve the previous precedence between dump options while converting the raw
   record into a single resolved dump mode. *)
let resolve_dump_mode args =
  match () with
  | _ when Option.is_some args.dump_automata ->
      Ok (Some (Dump_automata { out = get_some "dump-automata" args.dump_automata; short = false }))
  | _ when Option.is_some args.dump_automata_short ->
      Ok
        (Some
           (Dump_automata { out = get_some "dump-automata-short" args.dump_automata_short; short = true }))
  | _ when Option.is_some args.dump_product ->
      Ok (Some (Dump_product_explicit { out = get_some "dump-product" args.dump_product }))
  | _ when Option.is_some args.dump_dot_explicit ->
      Ok
        (Some
           (Dump_product_merge
              { out = get_some "dump-product-merge" args.dump_dot_explicit; short = false }))
  | _ when Option.is_some args.dump_product_short ->
      Ok
        (Some
           (Dump_product_merge
              {
                out = get_some "dump-product-merge-short" args.dump_product_short;
                short = true;
              }))
  | _ when Option.is_some args.dump_canonical ->
      Ok (Some (Dump_canonical { out = get_some "dump-canonical" args.dump_canonical; short = false }))
  | _ when Option.is_some args.dump_canonical_short ->
      Ok
        (Some
           (Dump_canonical { out = get_some "dump-canonical-short" args.dump_canonical_short; short = true }))
  | _ when Option.is_some args.dump_obligations_map ->
      Ok
        (Some (Dump_obligations_map { out = get_some "dump-obligations-map" args.dump_obligations_map }))
  | _ when Option.is_some args.dump_normalized_program ->
      Ok
        (Some
           (Dump_normalized_program
              { out = get_some "dump-normalized-program" args.dump_normalized_program }))
  | _ when Option.is_some args.dump_kobj_summary ->
      Ok (Some (Dump_kobj_summary { out = get_some "dump-kobj-summary" args.dump_kobj_summary }))
  | _ when Option.is_some args.dump_kobj_clauses ->
      Ok (Some (Dump_kobj_clauses { out = get_some "dump-kobj-clauses" args.dump_kobj_clauses }))
  | _ when Option.is_some args.dump_kobj_product ->
      Ok (Some (Dump_kobj_product { out = get_some "dump-kobj-product" args.dump_kobj_product }))
  | _ when Option.is_some args.dump_kobj_contracts ->
      Ok
        (Some (Dump_kobj_contracts { out = get_some "dump-kobj-contracts" args.dump_kobj_contracts }))
  | _ -> Ok None

(* Non-dump actions preserve the current special cases:
   standalone Why dump, standalone VC dump, standalone SMT dump, else full run. *)
let resolve_action args =
  match resolve_dump_mode args with
  | Error _ as e -> e
  | Ok (Some mode) -> Ok (Dump mode)
  | Ok None -> (
      match (args.dump_why, args.prove, args.dump_why3_vc, args.dump_smt2) with
      | Some out, false, None, None -> Ok (Dump_why { out })
      | None, false, Some out, None -> Ok (Dump_why3_vc { out })
      | None, false, None, Some out -> Ok (Dump_smt2 { out })
      | _ -> Ok (Run { prove = args.prove }))

(* Dump execution is deliberately shallow: one resolved mode, one backend family,
   one bundle/text writer. *)
let exec_dump_mode args = function
  | Dump_product_explicit { out } ->
      with_instrumentation_pass args (write_product_bundle ~out ~short:false ~explicit:true)
  | Dump_automata { out; short } ->
      with_instrumentation_pass args (write_automata_bundle ~out ~short)
  | Dump_product_merge { out; short } ->
      with_instrumentation_pass args (write_product_bundle ~out ~short ~explicit:false)
  | Dump_canonical { out; short } ->
      with_instrumentation_pass args (write_canonical_bundle ~out ~short)
  | Dump_obligations_map { out } ->
      with_instrumentation_pass args (fun artifacts -> write_text_output out artifacts.obligations_map_text)
  | Dump_normalized_program { out } -> with_normalized_program args (write_text_output out)
  | Dump_kobj_summary { out } -> with_kobj_summary args (write_text_output out)
  | Dump_kobj_clauses { out } -> with_kobj_clauses args (write_text_output out)
  | Dump_kobj_product { out } -> with_kobj_product args (write_text_output out)
  | Dump_kobj_contracts { out } -> with_kobj_contracts args (write_text_output out)

(* The generic run path remains the only branch that calls [Lsp_backend.run].
   It still handles optional side dumps and proof failure reporting. *)
let exec_action args = function
  | Dump mode -> exec_dump_mode args mode
  | Dump_why { out } ->
      with_why_pass args (fun why_out ->
          write_target out why_out.why_text;
          `Ok ())
  | Dump_why3_vc { out } ->
      with_obligations_pass args (fun obligations_out ->
          write_target out obligations_out.vc_text;
          `Ok ())
  | Dump_smt2 { out } ->
      with_obligations_pass args (fun obligations_out ->
          write_target out obligations_out.smt_text;
          `Ok ())
  | Run { prove } -> (
      match Lsp_backend.run ~engine:Engine_service.Default (run_req args) with
      | Error msg -> `Error (false, msg)
      | Ok out ->
          Option.iter (fun path -> write_target path out.why_text) args.dump_why;
          Option.iter (fun path -> write_target path out.vc_text) args.dump_why3_vc;
          Option.iter (fun path -> write_target path out.smt_text) args.dump_smt2;
          if prove then
            let failures = report_failed_goals out.goals in
            if failures <> [] then `Error (false, String.concat "\n" failures) else `Ok ()
          else `Ok ())

(* Main CLI flow: validate, resolve to a single action, then execute it. *)
let eval_cli args =
  match validate_args args with
  | Error msg -> `Error (false, msg)
  | Ok () -> (
      match resolve_action args with
      | Error msg -> `Error (false, msg)
      | Ok action -> exec_action args action)

let cmd =
  let file =
    let doc = "Input Kairos file." in
    Arg.(required & pos 0 (some string) None & info [] ~docs:docs_general ~docv:"FILE" ~doc)
  in
  let prove =
    Arg.(value & flag & info [ "prove" ] ~docs:docs_proof ~doc:"Run prover on generated Why3 obligations.")
  in
  let prover =
    Arg.(
      value & opt string "z3"
      & info [ "prover" ] ~docs:docs_proof ~docv:"NAME" ~doc:"Prover for --prove (default: z3).")
  in
  let prover_cmd =
    Arg.(
      value & opt (some string) None
      & info [ "prover-cmd" ] ~docs:docs_proof ~docv:"CMD" ~doc:"Override prover command.")
  in
  let dump_automata =
    Arg.(
      value & opt (some string) None
      & info [ "dump-automata" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump guarantee+assume automata text.")
  in
  let dump_product =
    Arg.(
      value & opt (some string) None
      & info [ "dump-product" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump product automaton text with the explicit product graph.")
  in
  let dump_canonical =
    Arg.(
      value & opt (some string) None
      & info [ "dump-canonical" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:
            "Dump the canonical proof-step structure as FILE.dot plus FILE.tex and FILE.txt side artifacts.")
  in
  let dump_automata_short =
    Arg.(
      value & opt (some string) None
      & info [ "dump-automata-short" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump guarantee+assume automata text, plus short DOT side files without embedded formula legends.")
  in
  let dump_product_short =
    Arg.(
      value & opt (some string) None
      & info [ "dump-product-merge-short" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump product automaton text, plus a short DOT side file without embedded formula legend.")
  in
  let dump_canonical_short =
    Arg.(
      value & opt (some string) None
      & info [ "dump-canonical-short" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:
            "Dump the canonical proof-step structure as a short FILE.dot plus FILE.tex and FILE.txt side artifacts.")
  in
  let dump_dot_explicit =
    Arg.(
      value & opt (some string) None
      & info [ "dump-product-merge" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:
            "Dump product automaton text with the merged product graph.")
  in
  let dump_obligations_map =
    Arg.(
      value & opt (some string) None
      & info [ "dump-obligations-map" ] ~docs:docs_text ~docv:"FILE"
          ~doc:"Dump mapping from transitions to generated clauses.")
  in
  let dump_normalized_program =
    Arg.(
      value & opt (some string) None
      & info [ "dump-normalized-program" ] ~docs:docs_text ~docv:"FILE"
          ~doc:"Dump the normalized program used by the pipeline.")
  in
  let dump_why =
    Arg.(
      value & opt (some string) None
      & info [ "dump-why" ] ~docs:why3_proof ~docv:"FILE"
          ~doc:"Dump Why3 program to FILE (or '-' for stdout).")
  in
  let dump_why3_vc =
    Arg.(
      value & opt (some string) None
      & info [ "dump-why3-vc" ] ~docs:why3_proof ~docv:"FILE" ~doc:"Dump Why3 VC tasks to FILE.")
  in
  let dump_smt2 =
    Arg.(
      value & opt (some string) None
      & info [ "dump-smt2" ] ~docs:why3_proof ~docv:"FILE" ~doc:"Dump SMT-LIB tasks to FILE.")
  in
  let dump_kobj_summary =
    Arg.(
      value & opt (some string) None
      & info [ "dump-kobj-summary" ] ~docs:docs_kobj ~docv:"FILE" ~doc:"Dump kobj summary text.")
  in
  let dump_kobj_clauses =
    Arg.(
      value & opt (some string) None
      & info [ "dump-kobj-clauses" ] ~docs:docs_kobj ~docv:"FILE" ~doc:"Dump kobj clauses text.")
  in
  let dump_kobj_product =
    Arg.(
      value & opt (some string) None
      & info [ "dump-kobj-product" ] ~docs:docs_kobj ~docv:"FILE" ~doc:"Dump kobj product text.")
  in
  let dump_kobj_contracts =
    Arg.(
      value & opt (some string) None
      & info [ "dump-kobj-contracts" ] ~docs:docs_kobj ~docv:"FILE"
          ~doc:"Dump kobj product contracts text.")
  in
  let timeout_s =
    Arg.(
      value & opt int 10
      & info [ "timeout-s" ] ~docs:docs_proof ~docv:"SECONDS"
          ~doc:"Per-goal prover timeout in seconds for --prove and Why3 obligation dumps.")
  in
  let cli_args_term =
    (* Cmdliner still declares options one by one, but we now assemble them into
       a record before entering the operational logic. *)
    let make_cli_args file prove prover prover_cmd timeout_s dump_automata dump_product
        dump_canonical dump_automata_short dump_product_short dump_canonical_short dump_dot_explicit
        dump_obligations_map dump_normalized_program dump_why dump_why3_vc dump_smt2
        dump_kobj_summary dump_kobj_clauses dump_kobj_product dump_kobj_contracts =
      {
        file;
        prove;
        prover;
        prover_cmd;
        timeout_s;
        dump_automata;
        dump_product;
        dump_canonical;
        dump_automata_short;
        dump_product_short;
        dump_canonical_short;
        dump_dot_explicit;
        dump_obligations_map;
        dump_normalized_program;
        dump_why;
        dump_why3_vc;
        dump_smt2;
        dump_kobj_summary;
        dump_kobj_clauses;
        dump_kobj_product;
        dump_kobj_contracts;
      }
    in
    Term.(
      const make_cli_args $ file $ prove $ prover $ prover_cmd $ timeout_s $ dump_automata
      $ dump_product $ dump_canonical $ dump_automata_short $ dump_product_short
      $ dump_canonical_short $ dump_dot_explicit $ dump_obligations_map $ dump_normalized_program
      $ dump_why $ dump_why3_vc $ dump_smt2 $ dump_kobj_summary $ dump_kobj_clauses
      $ dump_kobj_product $ dump_kobj_contracts)
  in
  let term = Term.(ret (const eval_cli $ cli_args_term)) in
  let man = [
  `S Manpage.s_description;
  `P "Kairos command line interface.";
  `S docs_proof;
  `S docs_graph;
  `S docs_text;
  `S docs_kobj;
  `S Manpage.s_common_options;
]in
  let info = Cmd.info "kairos" ~doc:"CLI backed by the Kairos LSP service layer" ~man:man in
  Cmd.v info term

let run () = exit (Cmd.eval cmd)
