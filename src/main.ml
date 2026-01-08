
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
  if Array.length Sys.argv < 2 then (
    prerr_endline "Usage: obc2why3 <file.obc>";
    exit 1
  );
  let p = parse_file Sys.argv.(1) in
  print_string (Whygen.compile_program p)
