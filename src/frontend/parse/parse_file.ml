module A = Ast

let parse_file (fn:string) : A.program =
  let ic = open_in fn in
  let lb = Sedlexing.Utf8.from_channel ic in
  Sedlexing.set_filename lb fn;
  try
    let start_pos = {
      Lexing.pos_fname = fn;
      pos_lnum = 1;
      pos_bol = 0;
      pos_cnum = 0;
    } in
    let module I = Parser.MenhirInterpreter in
    let rec loop checkpoint =
      match checkpoint with
      | I.InputNeeded _env ->
          let tok = Lexer.token lb in
          let startp, endp = Sedlexing.lexing_positions lb in
          let checkpoint = I.offer checkpoint (tok, startp, endp) in
          loop checkpoint
      | I.Shifting _ | I.AboutToReduce _ ->
          loop (I.resume checkpoint)
      | I.Accepted v -> v
      | I.HandlingError _ ->
          let pos, _ = Sedlexing.lexing_positions lb in
          let col = pos.pos_cnum - pos.pos_bol + 1 in
          let lexeme =
            let s = Lexer.last_lexeme () in
            if s = "" then "<eof>" else s
          in
          raise (Failure (Printf.sprintf "Parse error at %s:%d:%d near '%s'"
                            pos.pos_fname pos.pos_lnum col lexeme))
      | I.Rejected ->
          raise (Failure "Parse error")
    in
    let checkpoint = Parser.Incremental.program start_pos in
    let p = loop checkpoint in
    close_in ic;
    p
  with
  | Lexer.Lexing_error msg ->
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      close_in_noerr ic;
      raise (Failure (Printf.sprintf "Lexing error at %s:%d:%d: %s"
                        pos.pos_fname pos.pos_lnum col msg))
  | e ->
      let pos, _ = Sedlexing.lexing_positions lb in
      Printf.eprintf "Parse error at %s:%d:%d\n"
        pos.pos_fname pos.pos_lnum (pos.pos_cnum - pos.pos_bol);
      close_in_noerr ic;
      raise e
