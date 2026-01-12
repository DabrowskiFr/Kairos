
{
open Parser
exception Lexing_error of string
let kw_table = Hashtbl.create 64
let () =
  List.iter (fun (k,t) -> Hashtbl.add kw_table k t)
  [
    "node", NODE; "returns", RETURNS; "locals", LOCALS; "states", STATES;
    "init", INIT; "trans", TRANS; "end", END;
    "requires", REQUIRES; "ensures", ENSURES; "assume", ASSUME; "guarantee", GUARANTEE; "invariant", INVARIANT; "invariants", INVARIANTS;
    "instance", INSTANCE; "instances", INSTANCES; "call", CALL;
    "if", IF; "then", THEN; "else", ELSE; "skip", SKIP; "assert", ASSERT;
    "true", TRUE; "false", FALSE;
    "int", TINT; "bool", TBOOL; "real", TREAL;
    "pre", PRE;
    "min", MIN; "max", MAX; "add", ADD; "mul", MUL; "and", AND; "or", OR; "not", NOT;
    "first", FIRST;
    "G", G; "X", X;
    "let", LET; "in", IN;
    "state", STATE;
  ]
}

let digit = ['0'-'9']
let idstart = ['A'-'Z''a'-'z''_']
let idchar = ['A'-'Z''a'-'z''0'-'9''_''\'']
rule token = parse
  | [' ' '\t' '\r' '\n'] { token lexbuf }
  | "(*" { comment lexbuf; token lexbuf }
  | ":=" { ASSIGN }
  | "->" { ARROW }
  | "=>" { IMPL }
  | ">=" { GE }
  | "<=" { LE }
  | "!=" { NEQ }
  | "="  { EQ }
  | ">"  { GT }
  | "<"  { LT }
  | "+"  { PLUS }
  | "-"  { MINUS }
  | "*"  { STAR }
  | "/"  { SLASH }
  | "("  { LPAREN }
  | ")"  { RPAREN }
  | "{"  { LBRACE }
  | "}"  { RBRACE }
  | "["  { LBRACK }
  | "]"  { RBRACK }
  | ","  { COMMA }
  | ";"  { SEMI }
  | ":"  { COLON }
  | "."  { DOT }
  | digit+ as s { INT (int_of_string s) }
  | idstart idchar* as s {
      try Hashtbl.find kw_table s with Not_found -> IDENT s
    }
  | eof { EOF }
  | _ as c { raise (Lexing_error (Printf.sprintf "Unexpected char: %c" c)) }

and comment = parse
  | "*)" { () }
  | eof { raise (Lexing_error "Unterminated comment") }
  | _ { comment lexbuf }
