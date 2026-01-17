
open Ast

let add_post_for_next_pre (n:node) : node =
  let requires_by_state : (ident, ltl list) Hashtbl.t = Hashtbl.create 16 in
  let add_req st f =
    let existing = Hashtbl.find_opt requires_by_state st |> Option.value ~default:[] in
    Hashtbl.replace requires_by_state st (f :: existing)
  in
  List.iter
    (fun (t:transition) ->
      List.iter
        (function
          | Requires f -> add_req t.src f
          | _ -> ())
        t.contracts)
    n.trans;
  let uniq lst =
    List.sort_uniq compare lst
  in
  let trans =
    List.map
      (fun (t:transition) ->
        let reqs = Hashtbl.find_opt requires_by_state t.dst |> Option.value ~default:[] in
        let reqs = uniq reqs in
        let has_ensure f =
          List.exists
            (function
              | Ensures f' -> f' = f
              | _ -> false)
            t.contracts
        in
        let new_ensures =
          List.filter (fun f -> not (has_ensure f)) reqs
          |> List.map (fun f -> Ensures f)
        in
        if new_ensures = [] then t
        else { t with contracts = t.contracts @ new_ensures })
      n.trans
  in
  { n with trans }

let add_post_for_next_pre_program (p:program) : program =
  List.map add_post_for_next_pre p

let parse_file (fn:string) : program =
  let ic = open_in fn in
  let lb = Lexing.from_channel ic in
  try
    let p = Parser.program Lexer.token lb in
    close_in ic; p
  with e ->
    let pos = lb.lex_curr_p in
    Printf.eprintf "Parse error at %s:%d:%d\n"
      pos.pos_fname pos.pos_lnum (pos.pos_cnum - pos.pos_bol);
    close_in_noerr ic;
    raise e

let () =
  let use_monitor = ref true in
  let monitor_dot = ref None in
  let monitor_no_prefix = ref false in
  let no_prefix = ref false in
  let show_help = ref false in
  let k_induction = ref false in
  let prove = ref false in
  let prover = ref "alt-ergo" in
  let files = ref [] in
  let usage =
    "Usage: obc2why3 [--monitor] [--k-induction]\n" ^
    "                [--monitor-dot <file.dot>]\n" ^
    "                [--prove --prover <name>] <file.obc>\n" ^
    "Options:\n" ^
    "  --help               Show this help message\n" ^
    "  --monitor            Generate Why3 using a monitor state for residuals (default)\n" ^
    "  --monitor-no-prefix  Do not prefix vars fields with the module name (monitor mode)\n" ^
    "  --no-prefix          Do not prefix vars fields with the module name (monitor mode)\n" ^
    "  --monitor-dot        Generate DOT for the monitor residual graph and print Why3\n" ^
    "  --k-induction        Generate k-induction proof obligations for X^k under G\n" ^
    "  --prove              Run why3 prove on the generated output\n" ^
    "  --prover <name>      Prover for --prove (default: alt-ergo)\n"
  in
  let i = ref 1 in
  while !i < Array.length Sys.argv do
    match Sys.argv.(!i) with
    | "--help" ->
        show_help := true;
        incr i
    | "--monitor-no-prefix" ->
        monitor_no_prefix := true;
        incr i
    | "--no-prefix" ->
        no_prefix := true;
        incr i
    | "--monitor" ->
        use_monitor := true;
        incr i
    | "--monitor-dot" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --monitor-dot";
          exit 1
        ) else (
          monitor_dot := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--k-induction" ->
        k_induction := true;
        incr i
    | "--prove" ->
        prove := true;
        incr i
    | "--prover" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --prover";
          exit 1
        ) else (
          prover := Sys.argv.(!i + 1);
          i := !i + 2
        )
    | arg when String.length arg > 0 && arg.[0] = '-' ->
        prerr_endline ("Unknown option: " ^ arg);
        exit 1
    | arg ->
        files := arg :: !files;
        incr i
  done;
  if !show_help then (
    print_string usage;
    exit 0
  );
  if !no_prefix then (
    monitor_no_prefix := true
  );
  match List.rev !files with
  | [file] ->
      let p = parse_file file |> add_post_for_next_pre_program in
      let output_and_maybe_prove out =
        if !prove then (
          let tmp = Filename.temp_file "obc2why3_" ".why" in
          let oc = open_out tmp in
          output_string oc out;
          close_out oc;
          let cmd =
            Printf.sprintf "why3 prove -P %s -t 30 -a split_vc %s"
              !prover (Filename.quote tmp)
          in
          let status = Sys.command cmd in
          Sys.remove tmp;
          if status <> 0 then exit status
        );
        print_string out
      in
      begin match !monitor_dot with
      | Some out_file ->
          let residual_file =
            if Filename.check_suffix out_file ".dot"
            then out_file
            else out_file ^ ".dot"
          in
          let write path content =
            let oc = open_out path in
            output_string oc content;
            close_out oc
          in
          write residual_file (Whygen_automaton.dot_monitor_program p);
          let out =
            Whygen_automaton.compile_program_monitor
              ~k_induction:!k_induction
              ~prefix_fields:(not !monitor_no_prefix)
              p
          in
          output_and_maybe_prove out
      | None ->
          let out =
            if !use_monitor then
              Whygen_automaton.compile_program_monitor
                ~k_induction:!k_induction
                ~prefix_fields:(not !monitor_no_prefix)
                p
            else
              Whygen_automaton.compile_program_monitor
                ~k_induction:!k_induction
                ~prefix_fields:(not !monitor_no_prefix)
                p
          in
          output_and_maybe_prove out
      end
  | _ ->
      prerr_endline usage;
      exit 1
