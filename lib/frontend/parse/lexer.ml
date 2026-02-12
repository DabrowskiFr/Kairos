open Parser

exception Lexing_error of string

let kw_table = Hashtbl.create 64

let () =
  List.iter
    (fun (k, t) -> Hashtbl.add kw_table k t)
    [
      ("node", NODE);
      ("returns", RETURNS);
      ("locals", LOCALS);
      ("states", STATES);
      ("init", INIT);
      ("trans", TRANS);
      ("end", END);
      ("requires", REQUIRES);
      ("ensures", ENSURES);
      ("assume", ASSUME);
      ("guarantee", GUARANTEE);
      ("invariant", INVARIANT);
      ("invariants", INVARIANTS);
      ("in", IN);
      ("contracts", CONTRACTS);
      ("instance", INSTANCE);
      ("instances", INSTANCES);
      ("call", CALL);
      ("if", IF);
      ("then", THEN);
      ("else", ELSE);
      ("when", WHEN);
      ("skip", SKIP);
      ("true", TRUE);
      ("false", FALSE);
      ("int", TINT);
      ("bool", TBOOL);
      ("real", TREAL);
      ("pre", PRE);
      ("pre_k", PREK);
      ("and", AND);
      ("or", OR);
      ("not", NOT);
      ("G", G);
      ("X", X);
    ]

let last_lexeme_ref = ref ""
let last_lexeme () = !last_lexeme_ref

let set_lexeme lexbuf =
  let s = Sedlexing.Utf8.lexeme lexbuf in
  last_lexeme_ref := s;
  s

let tok lexbuf t =
  ignore (set_lexeme lexbuf);
  t

let expected_tokens : (string * Parser.token) list =
  [
    ("node", NODE);
    ("returns", RETURNS);
    ("locals", LOCALS);
    ("states", STATES);
    ("init", INIT);
    ("trans", TRANS);
    ("end", END);
    ("requires", REQUIRES);
    ("ensures", ENSURES);
    ("assume", ASSUME);
    ("guarantee", GUARANTEE);
    ("invariant", INVARIANT);
    ("invariants", INVARIANTS);
    ("in", IN);
    ("contracts", CONTRACTS);
    ("instance", INSTANCE);
    ("instances", INSTANCES);
    ("call", CALL);
    ("if", IF);
    ("then", THEN);
    ("else", ELSE);
    ("when", WHEN);
    ("skip", SKIP);
    ("true", TRUE);
    ("false", FALSE);
    ("int", TINT);
    ("bool", TBOOL);
    ("real", TREAL);
    ("pre", PRE);
    ("pre_k", PREK);
    ("and", AND);
    ("or", OR);
    ("not", NOT);
    ("G", G);
    ("X", X);
    (":=", ASSIGN);
    ("->", ARROW);
    ("=>", IMPL);
    (">=", GE);
    ("<=", LE);
    ("!=", NEQ);
    ("=", EQ);
    (">", GT);
    ("<", LT);
    ("+", PLUS);
    ("-", MINUS);
    ("*", STAR);
    ("/", SLASH);
    ("(", LPAREN);
    (")", RPAREN);
    ("{", LBRACE);
    ("}", RBRACE);
    ("[", LBRACK);
    ("]", RBRACK);
    (",", COMMA);
    (";", SEMI);
    (":", COLON);
    ("int-literal", INT 0);
    ("identifier", IDENT "");
    ("<eof>", EOF);
  ]

let rec token lexbuf =
  match%sedlex lexbuf with
  | Plus (Chars " \t\r\n") ->
      let s = Sedlexing.Utf8.lexeme lexbuf in
      String.iter (fun c -> if c = '\n' then Sedlexing.new_line lexbuf) s;
      token lexbuf
  | "//", Star (Compl '\n') ->
      ignore (set_lexeme lexbuf);
      token lexbuf
  | "(*" ->
      comment lexbuf;
      token lexbuf
  | ":=" -> tok lexbuf ASSIGN
  | "->" -> tok lexbuf ARROW
  | "=>" -> tok lexbuf IMPL
  | ">=" -> tok lexbuf GE
  | "<=" -> tok lexbuf LE
  | "!=" -> tok lexbuf NEQ
  | "=" -> tok lexbuf EQ
  | ">" -> tok lexbuf GT
  | "<" -> tok lexbuf LT
  | "+" -> tok lexbuf PLUS
  | "-" -> tok lexbuf MINUS
  | "*" -> tok lexbuf STAR
  | "/" -> tok lexbuf SLASH
  | "(" -> tok lexbuf LPAREN
  | ")" -> tok lexbuf RPAREN
  | "{" -> tok lexbuf LBRACE
  | "}" -> tok lexbuf RBRACE
  | "[" -> tok lexbuf LBRACK
  | "]" -> tok lexbuf RBRACK
  | "," -> tok lexbuf COMMA
  | ";" -> tok lexbuf SEMI
  | ":" -> tok lexbuf COLON
  | Plus '0' .. '9' ->
      let s = set_lexeme lexbuf in
      INT (int_of_string s)
  | ('A' .. 'Z' | 'a' .. 'z' | '_'), Star ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '\'') -> (
      let s = set_lexeme lexbuf in
      try Hashtbl.find kw_table s with Not_found -> IDENT s)
  | eof -> tok lexbuf EOF
  | _ ->
      let s = set_lexeme lexbuf in
      raise (Lexing_error (Printf.sprintf "Unexpected char: %s" s))

and comment lexbuf =
  match%sedlex lexbuf with
  | "*)" -> ()
  | eof -> raise (Lexing_error "Unterminated comment")
  | _ -> comment lexbuf
