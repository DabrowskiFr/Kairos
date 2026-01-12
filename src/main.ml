
open Ast

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
  let use_automaton = ref false in
  let automaton_dot = ref None in
  let show_help = ref false in
  let k_induction = ref false in
  let prove = ref false in
  let prover = ref "alt-ergo" in
  let files = ref [] in
  let usage =
    "Usage: obc2why3 [--direct | --automaton] [--k-induction] [--automaton-dot <file.dot>]\n" ^
    "                [--prove --prover <name>] <file.obc>\n" ^
    "Options:\n" ^
    "  --help                 Show this help message\n" ^
    "  --direct               Generate Why3 using the direct translation (default)\n" ^
    "  --automaton            Generate Why3 using the automaton-based translation\n" ^
    "  --automaton-dot        Generate DOT (atoms/residual/product) files\n" ^
    "  --k-induction          Generate k-induction proof obligations for X^k under G\n" ^
    "  --prove                Run why3 prove on the generated output\n" ^
    "  --prover <name>        Prover for --prove (default: alt-ergo)\n"
  in
  let i = ref 1 in
  while !i < Array.length Sys.argv do
    match Sys.argv.(!i) with
    | "--help" ->
        show_help := true;
        incr i
    | "--direct" ->
        use_automaton := false;
        incr i
    | "--automaton" ->
        use_automaton := true;
        incr i
    | "--automaton-dot" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --automaton-dot";
          exit 1
        ) else (
          automaton_dot := Some Sys.argv.(!i + 1);
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
  match List.rev !files with
  | [file] ->
      let p = parse_file file in
      begin match !automaton_dot with
      | Some out_file ->
          let base =
            if Filename.check_suffix out_file ".dot"
            then Filename.chop_suffix out_file ".dot"
            else out_file
          in
          let atoms_file = base ^ "_atoms.dot" in
          let residual_file = base ^ "_residual.dot" in
          let product_file = base ^ "_product.dot" in
          let write path content =
            let oc = open_out path in
            output_string oc content;
            close_out oc
          in
          write atoms_file (Whygen_automaton.dot_program p);
          write residual_file (Whygen_automaton.dot_residual_program p);
          write product_file (Whygen_automaton.dot_product_program p)
      | None ->
          let out =
            if !use_automaton then
              Whygen_automaton.compile_program ~k_induction:!k_induction p
            else
              Whygen.compile_program ~k_induction:!k_induction p
          in
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
      end
  | _ ->
      prerr_endline usage;
      exit 1
