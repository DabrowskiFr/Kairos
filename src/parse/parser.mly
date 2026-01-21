%{
open Ast

let expect_now h =
  match h with
  | HNow e -> e
  | _ -> failwith "expected {expr} here"
%}

%token NODE RETURNS LOCALS STATES INIT TRANS END
%token REQUIRES ENSURES ASSUME GUARANTEE
%token INSTANCE INSTANCES CALL
%token IF THEN ELSE SKIP
%token TRUE FALSE
%token TINT TBOOL TREAL
%token PRE
%token MIN MAX ADD MUL AND OR NOT FIRST
%token G X
%token LPAREN RPAREN LBRACE RBRACE LBRACK RBRACK COMMA SEMI COLON DOT
%token ASSIGN ARROW IMPL
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
  NODE IDENT LPAREN params_opt RPAREN RETURNS LPAREN params_opt RPAREN node_contracts_opt instances_opt
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
      assumes = fst $10;
      guarantees = snd $10;
      invariants_mon = [];
      instances = $11;
      locals = $13;
      states = $15;
      init_state = $18;
      trans = $20;
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

node_contracts_opt:
  | /* empty */ { ([], []) }
  | node_contracts { $1 }

instances_opt:
  | /* empty */ { [] }
  | INSTANCES instance_list { $2 }

instance_list:
  | instance_decl instance_list { $1 :: $2 }
  | instance_decl { [$1] }

instance_decl:
  | INSTANCE IDENT COLON IDENT SEMI { ($2, $4) }

node_contracts:
  | ASSUME ltl SEMI node_contracts { let (a, g) = $4 in ($2 :: a, g) }
  | GUARANTEE ltl SEMI node_contracts { let (a, g) = $4 in (a, $2 :: g) }
  | ASSUME ltl SEMI { ([$2], []) }
  | GUARANTEE ltl SEMI { ([], [$2]) }

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
    let (reqs, enss) = $6 in
    { src=$1; dst=$3; guard=$4; requires=reqs; ensures=enss; lemmas=[]; body=$7 }
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
  | CALL IDENT LPAREN iexpr_list_opt RPAREN RETURNS LPAREN id_list_opt RPAREN
      { SCall($2, $4, $8) }

trans_contracts_opt:
  | /* empty */ { ([], []) }
  | trans_contracts { $1 }

trans_contracts:
  | REQUIRES fo_formula SEMI trans_contracts { let (reqs, enss) = $4 in ($2 :: reqs, enss) }
  | ENSURES fo_formula SEMI trans_contracts { let (reqs, enss) = $4 in (reqs, $2 :: enss) }
  | REQUIRES fo_formula SEMI { ([$2], []) }
  | ENSURES fo_formula SEMI { ([], [$2]) }

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
  | LBRACE iexpr RBRACE { HNow $2 }
  | PRE LPAREN iexpr RPAREN { HPre($3,None) }
  | PRE LPAREN iexpr COMMA iexpr RPAREN { HPre($3,Some $5) }
  | IDENT LPAREN iexpr COMMA iexpr COMMA INT RPAREN
      { if $1 = "pre_k" then HPreK($3,$5,$7) else failwith "unknown history op" }
  | IDENT LPAREN op COMMA hexpr COMMA hexpr RPAREN
      { if $1 = "fold" then HFold($3, expect_now $5, expect_now $7) else failwith "unknown history op" }

op:
  | MIN { OMin }
  | MAX { OMax }
  | ADD { OAdd }
  | MUL { OMul }
  | AND { OAnd }
  | OR  { OOr }
  | FIRST { OFirst }

ltl_atom:
  | fo_atom_noparen { LAtom $1 }
  | LPAREN ltl RPAREN { $2 }

fo_atom_noparen:
  | TRUE { FTrue }
  | FALSE { FFalse }
  | hexpr relop hexpr { FRel($1,$2,$3) }
  | IDENT LPAREN hexpr_list_opt RPAREN { FPred($1,$3) }

fo_atom:
  | fo_atom_noparen { $1 }
  | LPAREN fo_formula RPAREN { $2 }

fo_un:
  | NOT fo_un { FNot $2 }
  | fo_atom { $1 }

fo_and:
  | fo_and AND fo_un { FAnd($1,$3) }
  | fo_un { $1 }

fo_or:
  | fo_or OR fo_and { FOr($1,$3) }
  | fo_and { $1 }

fo_formula:
  | fo_imp { $1 }

fo_imp:
  | fo_or IMPL fo_imp { FImp($1,$3) }
  | fo_or { $1 }

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
  | ltl_imp { $1 }

ltl_imp:
  | ltl_or IMPL ltl_imp { LImp($1,$3) }
  | ltl_or { $1 }

relop:
  | EQ { REq }
  | NEQ { RNeq }
  | LT { RLt }
  | LE { RLe }
  | GT { RGt }
  | GE { RGe }

hexpr_list_opt:
  | /* empty */ { [] }
  | hexpr_list { $1 }

hexpr_list:
  | hexpr COMMA hexpr_list { $1 :: $3 }
  | hexpr { [$1] }
