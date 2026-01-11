%{
open Ast

let expect_now h =
  match h with
  | HNow e -> e
  | _ -> failwith "expected {expr} here"
%}

%token NODE RETURNS LOCALS STATES INIT TRANS END
%token REQUIRES ENSURES ASSUME GUARANTEE
%token INVARIANT INVARIANTS
%token INSTANCE INSTANCES CALL
%token IF THEN ELSE SKIP ASSERT
%token TRUE FALSE
%token TINT TBOOL TREAL
%token PRE
%token MIN MAX ADD MUL AND OR NOT FIRST
%token G X
%token LET IN
%token STATE
%token LPAREN RPAREN LBRACE RBRACE LBRACK RBRACK COMMA SEMI COLON DOT
%token ASSIGN ARROW
%token PLUS MINUS STAR SLASH
%token EQ NEQ LT LE GT GE
%token <int> INT
%token <string> IDENT
%token EOF

%start <Ast.program> program

%%

program:
  | nodes EOF { $1 }

nodes:
  | node nodes { $1 :: $2 }
  | node { [$1] }

node:
  NODE IDENT LPAREN params_opt RPAREN RETURNS LPAREN params_opt RPAREN contracts_opt invariants_opt instances_opt
  LOCALS vdecls_opt
  STATES state_list SEMI
  INIT IDENT
  TRANS transitions
  END
  {
    {
      nname = $2;
      inputs = $4;
      outputs = $8;
      contracts = $10 @ $11;
      instances = $12;
      locals = $14;
      states = $16;
      init_state = $19;
      trans = $21;
    }
  }

params_opt:
  | /* empty */ { [] }
  | params { $1 }

params:
  | param COMMA params { $1 :: $3 }
  | param { [$1] }

param:
  IDENT COLON ty { {vname=$1; vty=$3} }

ty:
  | TINT { TInt }
  | TBOOL { TBool }
  | TREAL { TReal }
  | IDENT { TCustom $1 }

contracts_opt:
  | /* empty */ { [] }
  | contracts { $1 }

contracts:
  | contract contracts { $1 :: $2 }
  | contract { [$1] }

invariants_opt:
  | /* empty */ { [] }
  | INVARIANTS invariant_list { $2 }

instances_opt:
  | /* empty */ { [] }
  | INSTANCES instance_list { $2 }

instance_list:
  | instance_decl instance_list { $1 :: $2 }
  | instance_decl { [$1] }

instance_decl:
  | INSTANCE IDENT COLON IDENT SEMI { ($2, $4) }

invariant_list:
  | invariant_decl invariant_list { $1 :: $2 }
  | invariant_decl { [$1] }

invariant_decl:
  | INVARIANT IDENT EQ hexpr SEMI { Invariant ($2, $4) }
  | INVARIANT STATE state_relop IDENT SEMI { InvariantState ($3, $4) }
  | INVARIANT STATE state_relop IDENT ARROW ltl_atom SEMI { InvariantStateRel ($3, $4, $6) }

contract:
  | REQUIRES ltl SEMI { Requires $2 }
  | ENSURES ltl SEMI { Ensures $2 }
  | ASSUME ltl SEMI { Assume $2 }
  | GUARANTEE ltl SEMI { Guarantee $2 }
  | INVARIANT IDENT EQ hexpr SEMI { Invariant ($2, $4) }
  | INVARIANT STATE state_relop IDENT SEMI { InvariantState ($3, $4) }
  | INVARIANT STATE state_relop IDENT ARROW ltl_atom SEMI { InvariantStateRel ($3, $4, $6) }

vdecls_opt:
  | /* empty */ { [] }
  | vdecls { $1 }

vdecls:
  | vdecl vdecls { $1 :: $2 }
  | vdecl { [$1] }

vdecl:
  IDENT COLON ty SEMI { {vname=$1; vty=$3} }

state_list:
  | IDENT COMMA state_list { $1 :: $3 }
  | IDENT { [$1] }

transitions:
  | transition transitions { $1 :: $2 }
  | transition { [$1] }

transition:
  IDENT ARROW IDENT guard_opt LBRACE trans_contracts_opt stmt_list_opt RBRACE
  {
    { src=$1; dst=$3; guard=$4; contracts=$6; body=$7 }
  }

guard_opt:
  | /* empty */ { None }
  | LBRACK iexpr RBRACK { Some $2 }

stmt_list_opt:
  | /* empty */ { [] }
  | stmt_list { $1 }

stmt_list:
  | stmt SEMI stmt_list { $1 :: $3 }
  | stmt SEMI { [$1] }

stmt:
  | IDENT ASSIGN iexpr { SAssign($1,$3) }
  | IF iexpr THEN stmt_list_opt ELSE stmt_list_opt END { SIf($2,$4,$6) }
  | SKIP { SSkip }
  | ASSERT ltl { SAssert $2 }
  | CALL IDENT LPAREN iexpr_list_opt RPAREN RETURNS LPAREN id_list_opt RPAREN
      { SCall($2, $4, $8) }

trans_contracts_opt:
  | /* empty */ { [] }
  | trans_contracts { $1 }

trans_contracts:
  | trans_contract trans_contracts { $1 :: $2 }
  | trans_contract { [$1] }

trans_contract:
  | REQUIRES ltl SEMI { Requires $2 }
  | ENSURES ltl SEMI { Ensures $2 }
  | ASSUME ltl SEMI { Assume $2 }
  | GUARANTEE ltl SEMI { Guarantee $2 }

(* arithmetic expressions without booleans *)
arith_atom:
  | INT { ILitInt $1 }
  | TRUE { ILitBool true }
  | FALSE { ILitBool false }
  | IDENT { IVar $1 }
  | LPAREN iexpr RPAREN { IPar $2 }

arith_unary:
  | MINUS arith_unary { IUn(Neg,$2) }
  | arith_atom { $1 }

arith_mul:
  | arith_mul STAR arith_unary { IBin(Mul,$1,$3) }
  | arith_mul SLASH arith_unary { IBin(Div,$1,$3) }
  | arith_unary { $1 }

arith:
  | arith PLUS arith_mul { IBin(Add,$1,$3) }
  | arith MINUS arith_mul { IBin(Sub,$1,$3) }
  | arith_mul { $1 }

(* arithmetic/boolean expressions for history contexts; include scan/scan1 *)
harith_atom:
  | INT { ILitInt $1 }
  | TRUE { ILitBool true }
  | FALSE { ILitBool false }
  | IDENT { IVar $1 }
  | IDENT LPAREN op COMMA harith RPAREN
      { if $1 = "scan1" then IScan1($3,$5) else failwith "unknown scan1" }
  | IDENT LPAREN op COMMA harith COMMA harith RPAREN
      { if $1 = "scan" then IScan($3,$5,$7) else if $1 = "fold" then IScan($3,$5,$7) else failwith "unknown scan" }
  | IDENT LPAREN INT COMMA wop COMMA harith RPAREN
      { if $1 = "window" then IScan(OMin, ILitInt $3, $7) else failwith "unknown window" }
  | LPAREN hiexpr RPAREN { IPar $2 }

harith_unary:
  | MINUS harith_unary { IUn(Neg,$2) }
  | harith_atom { $1 }

harith_mul:
  | harith_mul STAR harith_unary { IBin(Mul,$1,$3) }
  | harith_mul SLASH harith_unary { IBin(Div,$1,$3) }
  | harith_unary { $1 }

harith:
  | harith PLUS harith_mul { IBin(Add,$1,$3) }
  | harith MINUS harith_mul { IBin(Sub,$1,$3) }
  | harith_mul { $1 }

(* boolean/relational expressions over arith, layered to avoid precedence conflicts *)
iexpr_tail_opt:
  | relop arith {
      fun lhs ->
        match $1 with
        | REq -> IBin(Eq, lhs, $2)
        | RNeq -> IBin(Neq, lhs, $2)
        | RLt -> IBin(Lt, lhs, $2)
        | RLe -> IBin(Le, lhs, $2)
        | RGt -> IBin(Gt, lhs, $2)
        | RGe -> IBin(Ge, lhs, $2)
    }
  | /* empty */ { fun lhs -> lhs }

iexpr_atom:
  | arith iexpr_tail_opt { $2 $1 }

iexpr_not:
  | NOT iexpr_not { IUn(Not,$2) }
  | iexpr_atom { $1 }

iexpr_and:
  | iexpr_and AND iexpr_not { IBin(And,$1,$3) }
  | iexpr_not { $1 }

iexpr_or:
  | iexpr_or OR iexpr_and { IBin(Or,$1,$3) }
  | iexpr_and { $1 }

iexpr:
  | iexpr_or { $1 }

(* boolean/relational expressions for history contexts *)
hiexpr_tail_opt:
  | relop harith {
      fun lhs ->
        match $1 with
        | REq -> IBin(Eq, lhs, $2)
        | RNeq -> IBin(Neq, lhs, $2)
        | RLt -> IBin(Lt, lhs, $2)
        | RLe -> IBin(Le, lhs, $2)
        | RGt -> IBin(Gt, lhs, $2)
        | RGe -> IBin(Ge, lhs, $2)
    }
  | /* empty */ { fun lhs -> lhs }

hiexpr_atom:
  | harith hiexpr_tail_opt { $2 $1 }

hiexpr_not:
  | NOT hiexpr_not { IUn(Not,$2) }
  | hiexpr_atom { $1 }

hiexpr_and:
  | hiexpr_and AND hiexpr_not { IBin(And,$1,$3) }
  | hiexpr_not { $1 }

hiexpr_or:
  | hiexpr_or OR hiexpr_and { IBin(Or,$1,$3) }
  | hiexpr_and { $1 }

hiexpr:
  | hiexpr_or { $1 }

iexpr_list_opt:
  | /* empty */ { [] }
  | iexpr_list { $1 }

iexpr_list:
  | iexpr COMMA iexpr_list { $1 :: $3 }
  | iexpr { [$1] }

id_list_opt:
  | /* empty */ { [] }
  | id_list { $1 }

id_list:
  | IDENT COMMA id_list { $1 :: $3 }
  | IDENT { [$1] }

hexpr:
  | LBRACE hiexpr RBRACE { HNow $2 }
  | PRE LPAREN arith RPAREN { HPre($3,None) }
  | PRE LPAREN arith COMMA arith RPAREN { HPre($3,Some $5) }
  | IDENT LPAREN arith COMMA arith COMMA INT RPAREN
      { if $1 = "pre_k" then HPreK($3,$5,$7) else failwith "unknown history op" }
  | IDENT LPAREN op COMMA hexpr RPAREN
      { if $1 = "scan1" then HScan1($3, expect_now $5) else failwith "unknown history op" }
  | IDENT LPAREN op COMMA hexpr COMMA hexpr RPAREN
      { if $1 = "scan" then HScan($3, expect_now $5, expect_now $7) else if $1 = "fold" then HFold($3, expect_now $5, expect_now $7) else failwith "unknown history op" }
  | IDENT LPAREN INT COMMA wop COMMA hexpr RPAREN
      { if $1 = "window" then HWindow($3,$5, expect_now $7) else failwith "unknown window op" }
  | LET IDENT EQ hexpr IN hexpr { HLet($2,$4,$6) }

op:
  | MIN { OMin }
  | MAX { OMax }
  | ADD { OAdd }
  | MUL { OMul }
  | AND { OAnd }
  | OR  { OOr }
  | FIRST { OFirst }

wop:
  | MIN { WMin }
  | MAX { WMax }
  | ADD { WSum }
  | MUL { WCount }

ltl_atom:
  | TRUE { LTrue }
  | FALSE { LFalse }
  | hexpr relop hexpr { LAtom (ARel($1,$2,$3)) }
  | IDENT LPAREN hexpr_list_opt RPAREN { LAtom (APred($1,$3)) }
  | LPAREN ltl RPAREN { $2 }

ltl_un:
  | NOT ltl_un { LNot $2 }
  | X ltl_un { LX $2 }
  | G ltl_un { LG $2 }
  | ltl_atom { $1 }

ltl_and:
  | ltl_and AND ltl_un { LAnd($1,$3) }
  | ltl_un { $1 }

ltl_or:
  | ltl_or OR ltl_and { LOr($1,$3) }
  | ltl_and { $1 }

ltl:
  | ltl_or { $1 }

relop:
  | EQ { REq }
  | NEQ { RNeq }
  | LT { RLt }
  | LE { RLe }
  | GT { RGt }
  | GE { RGe }

state_relop:
  | EQ { true }
  | NEQ { false }

hexpr_list_opt:
  | /* empty */ { [] }
  | hexpr_list { $1 }

hexpr_list:
  | hexpr COMMA hexpr_list { $1 :: $3 }
  | hexpr { [$1] }
