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
  timeout_s : int;
  trace_level : string;
  dump_automata : string option;
  dump_automata_short : string option;
  dump_product : string option;
  dump_canonical : string option;
  dump_canonical_short : string option;
  dump_obligations_map : string option;
  dump_normalized_program : string option;
  dump_ir_pretty : string option;
  dump_timings : string option;
  dump_why : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  dump_kobj_summary : string option;
  dump_kobj_clauses : string option;
  dump_kobj_product : string option;
  dump_kobj_contracts : string option;
}

let collect_traceability_of_level = function
  | "off" -> false
  | "minimal" | "full" -> true
  | _ -> true

(* Mutually exclusive dump modes. Each one corresponds to a single "artifact export"
   branch and bypasses the general run/prove flow. *)
type dump_mode =
  | Dump_product of { out : string }
  | Dump_automata of { out : string; short : bool }
  | Dump_canonical of { out : string; short : bool }
  | Dump_obligations_map of { out : string }
  | Dump_normalized_program of { out : string }
  | Dump_ir_pretty of { out : string }
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

module Usecases = Verification_flow_usecases.Make (Kairos_usecase_wiring.Ports)

module Pipeline_service = struct
  type goal_info = string * string * float * string option * string option
  type flow_meta = (string * (string * string) list) list

  type automata_dump_data = {
    guarantee_automaton_text : string;
    assume_automaton_text : string;
    guarantee_automaton_dot : string;
    assume_automaton_dot : string;
    product_text : string;
    product_dot : string;
    canonical_text : string;
    canonical_dot : string;
    obligations_map_text : string;
  }

  type obligations_dump_data = {
    vc_text : string;
    smt_text : string;
  }

  type run_dump_data = {
    why_text : string;
    vc_text : string;
    smt_text : string;
    flow_meta : flow_meta;
    goals : goal_info list;
  }

  let instrumentation_pass = Usecases.instrumentation_pass
  let why_pass = Usecases.why_pass
  let obligations_pass = Usecases.obligations_pass

  let automata_dump_data ~input_file =
    match instrumentation_pass ~generate_png:false ~input_file with
    | Error _ as e -> e
    | Ok out ->
        Ok
          {
            guarantee_automaton_text = out.guarantee_automaton_text;
            assume_automaton_text = out.assume_automaton_text;
            guarantee_automaton_dot = out.guarantee_automaton_dot;
            assume_automaton_dot = out.assume_automaton_dot;
            product_text = out.product_text;
            product_dot = out.product_dot;
            canonical_text = out.canonical_text;
            canonical_dot = out.canonical_dot;
            obligations_map_text = out.obligations_map_text;
          }

  let why_text_dump ~input_file =
    match why_pass ~input_file with
    | Error _ as e -> e
    | Ok out -> Ok out.why_text

  let obligations_dump_data ~input_file =
    match obligations_pass ~input_file with
    | Error _ as e -> e
    | Ok out -> Ok { vc_text = out.vc_text; smt_text = out.smt_text }

  let read_or_compile_kobj ~(input_file : string) =
    if Filename.check_suffix input_file ".kobj" then
      match Kairos_object.read_file ~path:input_file with
      | Ok obj -> Ok obj
      | Error msg -> Error (Pipeline_types.Flow_error msg)
    else Kairos_usecase_wiring.compile_object ~input_file

  let kobj_summary ~input_file =
    match read_or_compile_kobj ~input_file with
    | Error _ as e -> e
    | Ok obj -> Ok (Kairos_object.render_summary obj)

  let kobj_clauses ~input_file =
    match read_or_compile_kobj ~input_file with
    | Error _ as e -> e
    | Ok obj -> Ok (Kairos_object.render_clauses obj)

  let kobj_product ~input_file =
    match read_or_compile_kobj ~input_file with
    | Error _ as e -> e
    | Ok obj -> Ok (Kairos_object.render_product obj)

  let kobj_contracts ~input_file =
    match read_or_compile_kobj ~input_file with
    | Error _ as e -> e
    | Ok obj -> Ok (Kairos_object.render_product_summaries obj)

  let normalized_program = Usecases.normalized_program
  let ir_pretty_dump = Usecases.ir_pretty_dump
  let run = Usecases.run

  let run_dump_data ~input_file ~timeout_s ~prove ~collect_traceability ~generate_vc_text
      ~generate_smt_text =
    let cfg =
      {
        Pipeline_types.input_file;
        wp_only = false;
        smoke_tests = false;
        timeout_s;
        collect_traceability;
        compute_proof_diagnostics = false;
        prove;
        generate_vc_text;
        generate_smt_text;
        generate_dot_png = false;
      }
    in
    match run cfg with
    | Error _ as e -> e
    | Ok out ->
        Ok
          {
            why_text = out.why_text;
            vc_text = out.vc_text;
            smt_text = out.smt_text;
            flow_meta = out.flow_meta;
            goals = out.goals;
          }
end

let write_target out text =
  match out with
  | "-" -> print_string text
  | path -> (
      match Bos.OS.File.write (Fpath.v path) text with
      | Ok () -> ()
      | Error (`Msg msg) -> failwith msg)

let dot_dump_base (path : string) : string =
  if Filename.check_suffix path ".dot" then Filename.chop_suffix path ".dot" else path

let ensure_dot_path (path : string) : string =
  if Filename.check_suffix path ".dot" then path else path ^ ".dot"

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

let report_failed_goals goals =
  let total = List.length goals in
  let failure_info (_, status, _, dump_path, vcid) =
    let status = String.lowercase_ascii status in
    if status <> "valid" && status <> "proved" && status <> "unknown" then
      Some (status, dump_path, vcid)
    else None
  in
  List.mapi
    (fun idx ((goal, _, time_s, _, _) as info) ->
      match failure_info info with
      | None -> None
      | Some (status, dump_path, vcid) ->
          let details =
            List.filter_map Fun.id
              [
                Option.map (fun id -> "vcid=" ^ id) vcid;
                Option.map (fun p -> "dump=" ^ p) dump_path;
              ]
            |> String.concat ", "
          in
          Some
            (Printf.sprintf "goal %d/%d failed: %s (%sstatus=%s, time=%.3fs)" (idx + 1)
               total goal
               (if details = "" then "" else details ^ ", ")
               status time_s))
    goals
  |> List.filter_map Fun.id

let map_error e = Pipeline_types.error_to_string e

(* Thin wrappers around backend passes so the execution layer can focus on the
   selected action instead of repeating result/error plumbing. *)
let with_instrumentation_pass args f =
  match Pipeline_service.automata_dump_data ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok out -> f out

let with_why_text_dump args f =
  match Pipeline_service.why_text_dump ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_obligations_pass args f =
  match Pipeline_service.obligations_dump_data ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok out -> f out

let with_kobj_summary args f =
  match Pipeline_service.kobj_summary ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_kobj_clauses args f =
  match Pipeline_service.kobj_clauses ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_kobj_product args f =
  match Pipeline_service.kobj_product ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_kobj_contracts args f =
  match Pipeline_service.kobj_contracts ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_normalized_program args f =
  match Pipeline_service.normalized_program ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let with_ir_pretty args f =
  match Pipeline_service.ir_pretty_dump ~input_file:args.file with
  | Error e -> `Error (false, map_error e)
  | Ok text -> f text

let write_text_output out text =
  write_target out text;
  `Ok ()

let write_timing_dump out (flow_meta : (string * (string * string) list) list) =
  let section_lines name =
    match List.assoc_opt name flow_meta with
    | None -> []
    | Some kv -> List.map (fun (k, v) -> k ^ "," ^ v) kv
  in
  let timing_lines =
    match List.assoc_opt "timings" flow_meta with
    | None -> [ "error,no_timing_data" ]
    | Some _ -> section_lines "timings"
  in
  let graph_lines = section_lines "graph_metrics" in
  let canonical_lines = section_lines "canonical_metrics" in
  let out_lines = timing_lines @ graph_lines @ canonical_lines in
  write_target out (String.concat "\n" out_lines ^ "\n")

let impossible_missing_option name = failwith ("internal error: missing CLI option for " ^ name)

let get_some name = function Some x -> x | None -> impossible_missing_option name

(* Shared file-emission helpers. They preserve the current on-disk bundle layout
   and filename conventions while keeping the execution branches short. *)
let write_automata_bundle ~out ~short artifacts =
  let dot_base = dot_dump_base out in
  write_target out
    (artifacts.Pipeline_service.guarantee_automaton_text ^ "\n\n"
   ^ artifacts.Pipeline_service.assume_automaton_text);
  write_target
    (dot_base ^ ".assume.dot")
    (if short then
       strip_dot_legend ~legend_id:"legend_a" artifacts.Pipeline_service.assume_automaton_dot
     else artifacts.Pipeline_service.assume_automaton_dot);
  write_target
    (dot_base ^ ".guarantee.dot")
    (if short then
       strip_dot_legend ~legend_id:"legend_g"
         artifacts.Pipeline_service.guarantee_automaton_dot
     else artifacts.Pipeline_service.guarantee_automaton_dot);
  `Ok ()

let write_product_bundle ~out artifacts =
  let dot_base = dot_dump_base out in
  write_target out artifacts.Pipeline_service.product_text;
  write_target (dot_base ^ ".dot") artifacts.Pipeline_service.product_dot;
  `Ok ()

let write_canonical_bundle ~out ~short artifacts =
  let dot_path = ensure_dot_path out in
  let dot_base = dot_dump_base dot_path in
  write_target
    dot_path
    (if short then
       strip_dot_legend ~legend_id:"legend_canonical" artifacts.Pipeline_service.canonical_dot
     else artifacts.Pipeline_service.canonical_dot);
  write_target (dot_base ^ ".txt") artifacts.Pipeline_service.canonical_text;
  `Ok ()

let dump_mode_count args =
  List.fold_left
    (fun acc opt -> if Option.is_some opt then acc + 1 else acc)
    0
    [
      args.dump_automata;
      args.dump_automata_short;
      args.dump_product;
      args.dump_canonical;
      args.dump_canonical_short;
      args.dump_obligations_map;
      args.dump_normalized_program;
      args.dump_ir_pretty;
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
      "--dump-product/--dump-automata/--dump-automata-short/--dump-canonical/--dump-canonical-short/--dump-obligations-map/--dump-normalized-program/--dump-ir-pretty/--dump-kobj-* cannot be combined with --prove or Why3 dump options"
  else if dump_mode_count args > 1 then
    Error
      "Only one dump mode can be selected among --dump-product/--dump-automata/--dump-automata-short/--dump-canonical/--dump-canonical-short/--dump-obligations-map/--dump-normalized-program/--dump-ir-pretty/--dump-kobj-*"
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
      Ok (Some (Dump_product { out = get_some "dump-product" args.dump_product }))
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
  | _ when Option.is_some args.dump_ir_pretty ->
      Ok (Some (Dump_ir_pretty { out = get_some "dump-ir-pretty" args.dump_ir_pretty }))
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
  | Dump_product { out } ->
      with_instrumentation_pass args (write_product_bundle ~out)
  | Dump_automata { out; short } ->
      with_instrumentation_pass args (write_automata_bundle ~out ~short)
  | Dump_canonical { out; short } ->
      with_instrumentation_pass args (write_canonical_bundle ~out ~short)
  | Dump_obligations_map { out } ->
      with_instrumentation_pass args (fun artifacts ->
          write_text_output out artifacts.Pipeline_service.obligations_map_text)
  | Dump_normalized_program { out } -> with_normalized_program args (write_text_output out)
  | Dump_ir_pretty { out } -> with_ir_pretty args (write_text_output out)
  | Dump_kobj_summary { out } -> with_kobj_summary args (write_text_output out)
  | Dump_kobj_clauses { out } -> with_kobj_clauses args (write_text_output out)
  | Dump_kobj_product { out } -> with_kobj_product args (write_text_output out)
  | Dump_kobj_contracts { out } -> with_kobj_contracts args (write_text_output out)

(* The generic run path remains the only branch that calls the full run use-case.
   It still handles optional side dumps and proof failure reporting. *)
let exec_action args = function
  | Dump mode -> exec_dump_mode args mode
  | Dump_why { out } ->
      with_why_text_dump args (fun why_text ->
          write_target out why_text;
          `Ok ())
  | Dump_why3_vc { out } ->
      with_obligations_pass args (fun obligations_out ->
          write_target out obligations_out.Pipeline_service.vc_text;
          `Ok ())
  | Dump_smt2 { out } ->
      with_obligations_pass args (fun obligations_out ->
          write_target out obligations_out.Pipeline_service.smt_text;
          `Ok ())
  | Run { prove } -> (
      match
        Pipeline_service.run_dump_data ~input_file:args.file ~timeout_s:args.timeout_s ~prove
          ~collect_traceability:(collect_traceability_of_level args.trace_level)
          ~generate_vc_text:(Option.is_some args.dump_why3_vc)
          ~generate_smt_text:(Option.is_some args.dump_smt2)
      with
      | Error e -> `Error (false, map_error e)
      | Ok out ->
          Option.iter (fun path -> write_target path out.Pipeline_service.why_text) args.dump_why;
          Option.iter (fun path -> write_target path out.Pipeline_service.vc_text) args.dump_why3_vc;
          Option.iter (fun path -> write_target path out.Pipeline_service.smt_text) args.dump_smt2;
          Option.iter (fun path -> write_timing_dump path out.Pipeline_service.flow_meta) args.dump_timings;
          if prove then
            let failures = report_failed_goals out.Pipeline_service.goals in
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
          ~doc:"Dump product automaton text.")
  in
  let dump_canonical =
    Arg.(
      value & opt (some string) None
      & info [ "dump-canonical" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:
            "Dump the canonical proof-step structure as FILE.dot plus FILE.txt side artifacts.")
  in
  let dump_automata_short =
    Arg.(
      value & opt (some string) None
      & info [ "dump-automata-short" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump guarantee+assume automata text, plus short DOT side files without embedded formula legends.")
  in
  let dump_canonical_short =
    Arg.(
      value & opt (some string) None
      & info [ "dump-canonical-short" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:
            "Dump the canonical proof-step structure as a short FILE.dot plus FILE.txt side artifacts.")
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
  let dump_ir_pretty =
    Arg.(
      value & opt (some string) None
      & info [ "dump-ir-pretty" ] ~docs:docs_text ~docv:"FILE"
          ~doc:"Dump the full IR in canonical readable format.")
  in
  let dump_timings =
    Arg.(
      value & opt (some string) None
      & info [ "dump-timings" ] ~docs:docs_text ~docv:"FILE"
          ~doc:
            "Dump per-run metrics as CSV key/value lines (timings, graph/canonical counts, obligation taxonomy).")
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
  let trace_level =
    Arg.(
      value & opt (enum [ ("full", "full"); ("minimal", "minimal"); ("off", "off") ]) "full"
      & info [ "trace-level" ] ~docs:docs_proof ~docv:"LEVEL"
          ~doc:
            "Traceability level for proof runs: full|minimal|off. 'off' disables trace artifact collection.")
  in
  let cli_args_term =
    (* Cmdliner still declares options one by one, but we now assemble them into
       a record before entering the operational logic. *)
    let make_cli_args file prove timeout_s trace_level dump_automata dump_product
        dump_canonical dump_automata_short dump_canonical_short
        dump_obligations_map dump_normalized_program dump_ir_pretty dump_timings dump_why
        dump_why3_vc dump_smt2 dump_kobj_summary dump_kobj_clauses dump_kobj_product
        dump_kobj_contracts =
      {
        file;
        prove;
        timeout_s;
        trace_level;
        dump_automata;
        dump_product;
        dump_canonical;
        dump_automata_short;
        dump_canonical_short;
        dump_obligations_map;
        dump_normalized_program;
        dump_ir_pretty;
        dump_timings;
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
      const make_cli_args $ file $ prove $ timeout_s $ trace_level $ dump_automata $ dump_product
      $ dump_canonical $ dump_automata_short
      $ dump_canonical_short $ dump_obligations_map $ dump_normalized_program
      $ dump_ir_pretty $ dump_timings $ dump_why $ dump_why3_vc $ dump_smt2 $ dump_kobj_summary
      $ dump_kobj_clauses $ dump_kobj_product $ dump_kobj_contracts)
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

let () = run ()
