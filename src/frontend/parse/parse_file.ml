module A = Ast

let parse_file (fn:string) : A.program =
  let ic = open_in fn in
  let lb = Lexing.from_channel ic in
  try
    let p = Parser.program Lexer.token lb in
    close_in ic;
    p
  with
  | Lexer.Lexing_error msg ->
      let pos = lb.lex_curr_p in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      close_in_noerr ic;
      raise (Failure (Printf.sprintf "Lexing error at %s:%d:%d: %s"
                        pos.pos_fname pos.pos_lnum col msg))
  | Parser.Error ->
      let pos = lb.lex_curr_p in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      let lexeme =
        let s = Lexing.lexeme lb in
        if s = "" then "<eof>" else s
      in
      close_in_noerr ic;
      raise (Failure (Printf.sprintf "Parse error at %s:%d:%d near '%s'"
                        pos.pos_fname pos.pos_lnum col lexeme))
  | e ->
      let pos = lb.lex_curr_p in
      Printf.eprintf "Parse error at %s:%d:%d\n"
        pos.pos_fname pos.pos_lnum (pos.pos_cnum - pos.pos_bol);
      close_in_noerr ic;
      raise e
