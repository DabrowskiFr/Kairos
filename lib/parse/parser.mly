%{
open Ast
open Source_file

let expect_now h =
  match h with
  | HNow e -> e
  | _ -> failwith "expected {expr} here"

let loc_of_positions (start_pos:Lexing.position) (end_pos:Lexing.position) =
  { line = start_pos.pos_lnum;
    col = start_pos.pos_cnum - start_pos.pos_bol;
    line_end = end_pos.pos_lnum;
    col_end = end_pos.pos_cnum - end_pos.pos_bol; }

let with_origin_loc origin loc value = Ast_provenance.with_origin ~loc origin value
let mk_iexpr_loc start_pos end_pos desc =
  Ast_builders.mk_iexpr ~loc:(loc_of_positions start_pos end_pos) desc
let mk_stmt_loc start_pos end_pos desc =
  Ast_builders.mk_stmt ~loc:(loc_of_positions start_pos end_pos) desc

let resolve_init_state ~(inline_init:Ast.ident option) : Ast.ident =
  match inline_init with
  | Some s -> s
  | None -> failwith "missing init state: mark one state with '(init)'"

let history_aliases : (string, (string * int)) Hashtbl.t = Hashtbl.create 17

let reset_history_aliases () = Hashtbl.clear history_aliases

let register_history_alias ~(alias:string) ~(param:string) ~(rhs_param:string) ~(k:int) =
  if k < 1 then failwith (Printf.sprintf "history alias '%s' uses invalid k=%d (expected >= 1)" alias k);
  if not (String.equal param rhs_param) then
    failwith
      (Printf.sprintf
         "history alias '%s' is inconsistent: parameter is '%s' but rhs uses '%s'" alias param
         rhs_param);
  Hashtbl.replace history_aliases alias (param, k)

let implicit_history_alias_k (alias:string) : int option =
  let prefix = "prev" in
  let plen = String.length prefix in
  if String.length alias < plen then None
  else if not (String.equal (String.sub alias 0 plen) prefix) then None
  else
    let suffix = String.sub alias plen (String.length alias - plen) in
    if String.length suffix = 0 then Some 1
    else
      let all_digits =
        let rec loop i =
          if i >= String.length suffix then true
          else
            match suffix.[i] with
            | '0' .. '9' -> loop (i + 1)
            | _ -> false
        in
        loop 0
      in
      if not all_digits then None
      else
        let k = int_of_string suffix in
        if k < 1 then None else Some k

let expand_history_alias (alias:string) (arg:iexpr) : hexpr =
  match Hashtbl.find_opt history_aliases alias with
  | Some (_param, k) -> HPreK (arg, k)
  | None -> (
      match implicit_history_alias_k alias with
      | Some k -> HPreK (arg, k)
      | None -> failwith (Printf.sprintf "unknown history alias '%s'" alias))

let mk_var_iexpr_loc start_pos end_pos id =
  mk_iexpr_loc start_pos end_pos (IVar id)

let is_reserved_history_alias_name (id:string) : bool =
  match implicit_history_alias_k id with Some _ -> true | None -> false

let forbid_reserved_identifier ~(context:string) (id:string) : unit =
  if is_reserved_history_alias_name id then
    failwith
      (Printf.sprintf
         "identifier '%s' is reserved for implicit history aliases (context: %s)" id context)
%}

%token NODE RETURNS LOCALS STATES INIT TRANS END
%token REQUIRES ENSURES ASSUME GUARANTEE
%token INVARIANT IN
%token INVARIANTS
%token CONTRACTS
%token LET
%token IMPORT
%token INSTANCE INSTANCES CALL
%token IF THEN ELSE SKIP
%token WHEN
%token MATCH WITH BAR
%token FROM TO
%token TRUE FALSE
%token TINT TBOOL TREAL
%token PRE
%token PREK
%token AND OR NOT
%token G X W R
%token LPAREN RPAREN LBRACE RBRACE LBRACK RBRACK COMMA SEMI COLON
%token ASSIGN ARROW IMPL
%token PLUS MINUS STAR SLASH
%token EQ NEQ LT LE GT GE
%token <int> INT
%token <string> IDENT
%token <string> STRING
%token EOF

%nonassoc IEXPR_ARITH
%nonassoc RPAREN

%start <Ast.program> program
%start <Source_file.t> source_file

%%

source_file:
  | imports_opt nodes EOF { { imports = $1; nodes = $2 } }

program:
  | imports_opt nodes EOF { $2 }

imports_opt:
  | /* empty */ { [] }
  | import_decls { $1 }

import_decls:
  | import_decl import_decls { $1 :: $2 }
  | import_decl { [ $1 ] }

import_decl:
  | IMPORT STRING SEMI
      {
        { import_path = $2;
          import_loc = Some (loc_of_positions (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2)) }
      }

nodes:
  | node nodes { $1 :: $2 }
  | node { [$1] }

node:
  NODE IDENT LPAREN params_opt RPAREN RETURNS LPAREN params_opt RPAREN
  alias_scope_start
  alias_decls_opt
  node_contracts_block instances_opt
  locals_opt
  STATES state_decls SEMI
  state_invariants_opt
  TRANS transitions
  END
  {
    let () = forbid_reserved_identifier ~context:"node name" $2 in
    let states, inline_init = $16 in
    let init_state = resolve_init_state ~inline_init in
    Ast_builders.mk_node
      ~nname:$2
      ~inputs:$4
      ~outputs:$8
      ~assumes:(fst $12)
      ~guarantees:(snd $12)
      ~instances:$13
      ~locals:$14
      ~states
      ~init_state
      ~trans:$20
    |> fun n ->
      { n with attrs = { n.attrs with invariants_state_rel = $18 } }
  }

params_opt:
  | /* empty */ { [] }
  | params { $1 }

params:
  | param COMMA params { $1 :: $3 }
  | param { [$1] }

param:
  IDENT COLON ty
    {
      let () = forbid_reserved_identifier ~context:"parameter" $1 in
      {vname=$1; vty=$3}
    }

ty:
  | TINT { TInt }
  | TBOOL { TBool }
  | TREAL { TReal }
  | IDENT { TCustom $1 }

node_contracts_block:
  | CONTRACTS { ([], []) }
  | CONTRACTS node_contracts { $2 }

instances_opt:
  | /* empty */ { [] }
  | INSTANCES instance_list { $2 }

locals_opt:
  | /* empty */ { [] }
  | LOCALS vdecls_opt { $2 }

instance_list:
  | instance_decl instance_list { $1 :: $2 }
  | instance_decl { [$1] }

instance_decl:
  | INSTANCE IDENT COLON IDENT SEMI
      {
        let () = forbid_reserved_identifier ~context:"instance name" $2 in
        let () = forbid_reserved_identifier ~context:"instance node reference" $4 in
        ($2, $4)
      }

node_contracts:
  | REQUIRES COLON ltl SEMI node_contracts
      {
        let (a, g) = $5 in ($3 :: a, g)
      }
  | ENSURES COLON ltl SEMI node_contracts
      {
        let (a, g) = $5 in (a, $3 :: g)
      }
  | REQUIRES COLON ltl SEMI
      {
        ([$3], [])
      }
  | ENSURES COLON ltl SEMI
      {
        ([], [$3])
      }

vdecls_opt:
  | /* empty */ { [] }
  | vdecls { $1 }

vdecls:
  | vdecl_group vdecls { $1 @ $2 }
  | vdecl_group { $1 }

vdecl_group:
  ident_list COLON ty SEMI
    {
      List.iter (fun name -> forbid_reserved_identifier ~context:"variable declaration" name) $1;
      List.map (fun name -> {vname=name; vty=$3}) $1
    }

ident_list:
  | IDENT COMMA ident_list { $1 :: $3 }
  | IDENT { [$1] }

alias_scope_start:
  | /* empty */ { reset_history_aliases () }

alias_decls_opt:
  | /* empty */ { () }
  | alias_decls { () }

alias_decls:
  | alias_decl alias_decls { () }
  | alias_decl { () }

alias_decl:
  | LET IDENT IDENT EQ PRE LPAREN IDENT RPAREN SEMI
      {
        let () = forbid_reserved_identifier ~context:"history alias parameter" $3 in
        let () = forbid_reserved_identifier ~context:"history alias rhs parameter" $7 in
        register_history_alias ~alias:$2 ~param:$3 ~rhs_param:$7 ~k:1
      }
  | LET IDENT IDENT EQ PREK LPAREN IDENT COMMA INT RPAREN SEMI
      {
        let () = forbid_reserved_identifier ~context:"history alias parameter" $3 in
        let () = forbid_reserved_identifier ~context:"history alias rhs parameter" $7 in
        register_history_alias ~alias:$2 ~param:$3 ~rhs_param:$7 ~k:$9
      }

state_decls:
  | state_decl COMMA state_decls {
      let s, i = $1 in
      let ss, ii = $3 in
      let init_opt =
        match (i, ii) with
        | None, x | x, None -> x
        | Some a, Some b when String.equal a b -> Some a
        | Some a, Some b ->
            failwith
              (Printf.sprintf
                 "multiple inline init states are not allowed: '%s' and '%s'" a b)
      in
      (s :: ss, init_opt)
    }
  | state_decl {
      let s, i = $1 in
      ([s], i)
    }

state_decl:
  | IDENT
      {
        let () = forbid_reserved_identifier ~context:"state name" $1 in
        ($1, None)
      }
  | IDENT LPAREN INIT RPAREN
      {
        let () = forbid_reserved_identifier ~context:"state name" $1 in
        ($1, Some $1)
      }

state_invariants_opt:
  | /* empty */ { [] }
  | state_invariants { $1 }

state_invariants:
  | INVARIANTS invariant_entries { $2 }
  | state_invariant state_invariants { $1 @ $2 }
  | state_invariant { $1 }

state_invariant:
  | INVARIANT IN IDENT COLON invariant_formula_list
      { List.map (fun f -> { is_eq = true; state = $3; formula = f }) $5 }

invariant_entries:
  | invariant_entry invariant_entries { $1 @ $2 }
  | invariant_entry { $1 }

invariant_entry:
  | IN IDENT COLON invariant_formula_list
      { List.map (fun f -> { is_eq = true; state = $2; formula = f }) $4 }

invariant_formula_list:
  | fo_formula SEMI invariant_formula_list { $1 :: $3 }
  | fo_formula SEMI { [$1] }

transitions:
  | transition_group transitions { $1 @ $2 }
  | transition_group { $1 }
  | MATCH IDENT WITH match_transitions
      {
        if not (String.equal $2 "state") then
          failwith
            (Printf.sprintf
               "unsupported match target '%s' in transitions (expected 'state')" $2);
        $4
      }

transition_group:
  | FROM IDENT COLON to_transitions {
      List.map
        (fun (dst, guard, reqs, enss, body) ->
          Ast_builders.mk_transition
            ~src:$2
            ~dst
            ~guard
            ~requires:reqs
            ~ensures:enss
            ~body)
        $4
    }
  | IDENT COLON to_transitions {
      List.map
        (fun (dst, guard, reqs, enss, body) ->
          Ast_builders.mk_transition
            ~src:$1
            ~dst
            ~guard
            ~requires:reqs
            ~ensures:enss
            ~body)
        $3
    }

to_transitions:
  | to_transition to_transitions { $1 :: $2 }
  | to_transition { [$1] }

to_transition:
  | TO IDENT guard_opt LBRACE trans_contracts_opt stmt_list_opt RBRACE
      {
        let (reqs, enss) = $5 in
        ($2, $3, reqs, enss, $6)
      }

match_transitions:
  | match_transition match_transitions { $1 :: $2 }
  | match_transition { [$1] }

match_transition:
  | BAR IDENT ARROW IDENT guard_opt LBRACE trans_contracts_opt stmt_list_opt RBRACE
      {
        let (reqs, enss) = $7 in
        Ast_builders.mk_transition
          ~src:$2
          ~dst:$4
          ~guard:$5
          ~requires:reqs
          ~ensures:enss
          ~body:$8
      }

guard_opt:
  | /* empty */ { None }
  | LBRACK iexpr RBRACK { Some $2 }
  | LBRACK TRUE RBRACK {
      Some (mk_iexpr_loc (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) (ILitBool true))
    }
  | LBRACK FALSE RBRACK {
      Some (mk_iexpr_loc (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) (ILitBool false))
    }
  | WHEN iexpr { Some $2 }
  | WHEN TRUE {
      Some (mk_iexpr_loc (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) (ILitBool true))
    }
  | WHEN FALSE {
      Some (mk_iexpr_loc (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) (ILitBool false))
    }

stmt_list_opt:
  | /* empty */ { [] }
  | stmt_list { $1 }

stmt_list:
  | stmt SEMI stmt_list { $1 :: $3 }
  | stmt SEMI { [$1] }

stmt:
  | IDENT ASSIGN iexpr { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SAssign($1,$3)) }
  | IDENT ASSIGN TRUE {
      let e = mk_iexpr_loc (Parsing.rhs_start_pos 3) (Parsing.rhs_end_pos 3) (ILitBool true) in
      mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SAssign($1,e))
    }
  | IDENT ASSIGN FALSE {
      let e = mk_iexpr_loc (Parsing.rhs_start_pos 3) (Parsing.rhs_end_pos 3) (ILitBool false) in
      mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SAssign($1,e))
    }
  | IF iexpr THEN stmt_list_opt ELSE stmt_list_opt END { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SIf($2,$4,$6)) }
  | IF TRUE THEN stmt_list_opt ELSE stmt_list_opt END {
      let c = mk_iexpr_loc (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) (ILitBool true) in
      mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SIf(c,$4,$6))
    }
  | IF FALSE THEN stmt_list_opt ELSE stmt_list_opt END {
      let c = mk_iexpr_loc (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) (ILitBool false) in
      mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SIf(c,$4,$6))
    }
  | SKIP { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) SSkip }
  | CALL IDENT LPAREN iexpr_list_opt RPAREN RETURNS LPAREN id_list_opt RPAREN
      { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 9) (SCall($2, $4, $8)) }

trans_contracts_opt:
  | /* empty */ { ([], []) }
  | trans_contracts { $1 }

trans_contracts:
  | ASSUME fo_formula SEMI trans_contracts
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        let (reqs, enss) = $4 in (with_origin_loc UserContract loc $2 :: reqs, enss)
      }
  | GUARANTEE fo_formula SEMI trans_contracts
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        let (reqs, enss) = $4 in (reqs, with_origin_loc UserContract loc $2 :: enss)
      }
  | ASSUME fo_formula SEMI
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        ([with_origin_loc UserContract loc $2], [])
      }
  | GUARANTEE fo_formula SEMI
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        ([], [with_origin_loc UserContract loc $2])
      }
  (* Legacy spelling kept for backward compatibility. *)
  | REQUIRES fo_formula SEMI trans_contracts
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        let (reqs, enss) = $4 in (with_origin_loc UserContract loc $2 :: reqs, enss)
      }
  | ENSURES fo_formula SEMI trans_contracts
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        let (reqs, enss) = $4 in (reqs, with_origin_loc UserContract loc $2 :: enss)
      }
  | REQUIRES fo_formula SEMI
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        ([with_origin_loc UserContract loc $2], [])
      }
  | ENSURES fo_formula SEMI
      {
        let loc = loc_of_positions (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) in
        ([], [with_origin_loc UserContract loc $2])
      }

(* arithmetic expressions without booleans *)
arith_atom:
  | INT { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (ILitInt $1) }
  | IDENT { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (IVar $1) }
  | LPAREN arith RPAREN { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IPar $2) }

arith_unary:
  | MINUS arith_unary { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (IUn(Neg,$2)) }
  | arith_atom { $1 }

arith_mul:
  | arith_mul STAR arith_unary { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IBin(Mul,$1,$3)) }
  | arith_mul SLASH arith_unary { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IBin(Div,$1,$3)) }
  | arith_unary { $1 }

arith:
  | arith PLUS arith_mul { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IBin(Add,$1,$3)) }
  | arith MINUS arith_mul { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IBin(Sub,$1,$3)) }
  | arith_mul { $1 }


iexpr_atom:
  | LPAREN iexpr RPAREN { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IPar $2) }
  | arith relop arith {
      match $2 with
      | REq -> Ast_builders.mk_iexpr (IBin(Eq, $1, $3))
      | RNeq -> Ast_builders.mk_iexpr (IBin(Neq, $1, $3))
      | RLt -> Ast_builders.mk_iexpr (IBin(Lt, $1, $3))
      | RLe -> Ast_builders.mk_iexpr (IBin(Le, $1, $3))
      | RGt -> Ast_builders.mk_iexpr (IBin(Gt, $1, $3))
      | RGe -> Ast_builders.mk_iexpr (IBin(Ge, $1, $3))
    }
  | arith %prec IEXPR_ARITH { $1 }

iexpr_not:
  | NOT iexpr_not { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (IUn(Not,$2)) }
  | iexpr_atom { $1 }

iexpr_and:
  | iexpr_and AND iexpr_not { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IBin(And,$1,$3)) }
  | iexpr_not { $1 }

iexpr_or:
  | iexpr_or OR iexpr_and { mk_iexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (IBin(Or,$1,$3)) }
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
  | IDENT IDENT {
      let arg = mk_var_iexpr_loc (Parsing.rhs_start_pos 2) (Parsing.rhs_end_pos 2) $2 in
      expand_history_alias $1 arg
    }
  | arith { HNow $1 }
  | LBRACE iexpr RBRACE { HNow $2 }
  | PRE LPAREN iexpr RPAREN { HPreK($3, 1) }
  | PREK LPAREN iexpr COMMA INT RPAREN { HPreK($3, $5) }

ltl_atom:
  | fo_atom_noparen { $1 }
  | LPAREN ltl RPAREN { $2 }

fo_atom_noparen:
  | TRUE { LTrue }
  | FALSE { LFalse }
  | hexpr relop hexpr { LAtom(FRel($1,$2,$3)) }
  | IDENT LPAREN hexpr_list_opt RPAREN { LAtom(FPred($1,$3)) }

fo_atom:
  | fo_atom_noparen { $1 }
  | LPAREN fo_formula RPAREN { $2 }

fo_un:
  | NOT fo_un { LNot $2 }
  | fo_atom { $1 }

fo_and:
  | fo_and AND fo_un { LAnd($1,$3) }
  | fo_un { $1 }

fo_or:
  | fo_or OR fo_and { LOr($1,$3) }
  | fo_and { $1 }

fo_formula:
  | fo_imp { $1 }

fo_imp:
  | fo_or IMPL fo_imp { LImp($1,$3) }
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

ltl_w:
  | ltl_or W ltl_w { LW($1,$3) }
  | ltl_or R ltl_w { LW($3, LAnd($1, $3)) }
  | ltl_or { $1 }

ltl:
  | ltl_imp { $1 }

ltl_imp:
  | ltl_w IMPL ltl_imp { LImp($1,$3) }
  | ltl_w { $1 }

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
