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
      ("transitions", TRANS);
      ("end", END);
      ("requires", REQUIRES);
      ("ensures", ENSURES);
      ("invariant", INVARIANT);
      ("invariants", INVARIANTS);
      ("in", IN);
      ("contracts", CONTRACTS);
      ("import", IMPORT);
      ("let", LET);
      ("instance", INSTANCE);
      ("instances", INSTANCES);
      ("call", CALL);
      ("if", IF);
      ("then", THEN);
      ("else", ELSE);
      ("match", MATCH);
      ("with", WITH);
      ("when", WHEN);
      ("from", FROM);
      ("to", TO);
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
      ("always", G);
      ("next", X);
      ("weakuntil", W);
      ("release", R);
      ("G", G);
      ("X", X);
      ("W", W);
      ("R", R);
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
    ("transitions", TRANS);
    ("end", END);
    ("requires", REQUIRES);
    ("ensures", ENSURES);
    ("invariant", INVARIANT);
    ("invariants", INVARIANTS);
    ("in", IN);
    ("contracts", CONTRACTS);
    ("import", IMPORT);
    ("let", LET);
    ("instance", INSTANCE);
    ("instances", INSTANCES);
    ("call", CALL);
    ("if", IF);
    ("then", THEN);
    ("else", ELSE);
    ("match", MATCH);
    ("with", WITH);
    ("when", WHEN);
    ("from", FROM);
    ("to", TO);
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
    ("always", G);
    ("next", X);
    ("weakuntil", W);
    ("release", R);
    ("G", G);
    ("X", X);
    ("W", W);
    ("R", R);
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
    ("string-literal", STRING "");
    ("<eof>", EOF);
  ]

let read_string_literal lexbuf =
  let buf = Buffer.create 32 in
  let rec loop () =
    match%sedlex lexbuf with
    | '"' ->
        last_lexeme_ref := "\"" ^ Buffer.contents buf ^ "\"";
        STRING (Buffer.contents buf)
    | '\\', '"' ->
        Buffer.add_char buf '"';
        loop ()
    | '\\', '\\' ->
        Buffer.add_char buf '\\';
        loop ()
    | '\\', 'n' ->
        Buffer.add_char buf '\n';
        loop ()
    | '\\', 't' ->
        Buffer.add_char buf '\t';
        loop ()
    | '\\', any ->
        raise (Lexing_error "Unsupported string escape")
    | eof -> raise (Lexing_error "Unterminated string literal")
    | '\n' ->
        Sedlexing.new_line lexbuf;
        Buffer.add_char buf '\n';
        loop ()
    | any ->
        Buffer.add_string buf (Sedlexing.Utf8.lexeme lexbuf);
        loop ()
    | _ ->
        raise (Lexing_error "Invalid string literal")
  in
  loop ()

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
  | "|" -> tok lexbuf BAR
  | Plus '0' .. '9' ->
      let s = set_lexeme lexbuf in
      INT (int_of_string s)
  | '"' ->
      ignore (set_lexeme lexbuf);
      read_string_literal lexbuf
  | ('A' .. 'Z' | 'a' .. 'z' | '_'), Star ('A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' | '\'') -> (
      let s = set_lexeme lexbuf in
      match Hashtbl.find_opt kw_table s with
      | Some t -> t
      | None -> IDENT s)
  | eof -> tok lexbuf EOF
  | _ ->
      let s = set_lexeme lexbuf in
      raise (Lexing_error (Printf.sprintf "Unexpected char: %s" s))

and comment lexbuf =
  match%sedlex lexbuf with
  | "*)" -> ()
  | eof -> raise (Lexing_error "Unterminated comment")
  | _ -> comment lexbuf
