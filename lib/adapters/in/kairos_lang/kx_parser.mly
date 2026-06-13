%{
open Kx_core_syntax
open Kx_surface_syntax
open Kx_topology_syntax

let loc_of_positions (start_pos:Lexing.position) (end_pos:Lexing.position) : Kx_loc.loc =
  { line = start_pos.pos_lnum;
    col = start_pos.pos_cnum - start_pos.pos_bol;
    line_end = end_pos.pos_lnum;
    col_end = end_pos.pos_cnum - end_pos.pos_bol; }

let loc start_pos end_pos = loc_of_positions start_pos end_pos

let mk_expr_loc start_pos end_pos desc =
  Kx_surface_syntax.mk_expr ~loc:(loc start_pos end_pos) desc

let mk_stmt_loc start_pos end_pos desc =
  Kx_surface_syntax.mk_stmt ~loc:(loc start_pos end_pos) desc

let mk_hexpr_loc start_pos end_pos desc =
  Kx_surface_syntax.mk_hexpr ~loc:(loc start_pos end_pos) desc

let indexed_ref base indices = { ref_base = base; ref_indices = indices }
let scalar_ref base = indexed_ref base []

let resolve_init_state ~(inline_init:ident option) : ident =
  match inline_init with
  | Some s -> s
  | None -> failwith "missing init state: mark one state with '(init)'"

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

let is_reserved_history_alias_name (id:string) : bool =
  match implicit_history_alias_k id with Some _ -> true | None -> false

let forbid_reserved_identifier ~(context:string) (id:string) : unit =
  if is_reserved_history_alias_name id then
    failwith
      (Printf.sprintf
         "identifier '%s' is reserved for implicit history aliases (context: %s)" id context)
%}

%token TYPE DOMAIN FUNCTION PREDICATE ACTION
%token NODE RETURNS LOCALS GHOSTS STATES INIT TRANS END
%token REQUIRES ENSURES
%token INVARIANT IN
%token INVARIANTS
%token CONTRACTS
%token TOPOLOGY ROUTE USES CONFLICT ROUTESIGNAL
%token LET
%token IMPORT
%token INSTANCE INSTANCES CALL
%token IF THEN ELSE SKIP FOR FORALL EXISTS
%token WHEN
%token MATCH WITH BAR
%token FROM TO
%token TRUE FALSE
%token TINT TBOOL TREAL
%token PRE
%token PREK
%token AND OR NOT
%token G X W R
%token MAINTAINEDUNTIL WHILEROUTELOCKED
%token LPAREN RPAREN LBRACE RBRACE LBRACK RBRACK COMMA SEMI COLON DOT
%token ASSIGN ARROW IMPL
%token PLUS MINUS STAR SLASH
%token EQ NEQ LT LE GT GE
%token <int> INT
%token <string> IDENT
%token <string> STRING
%token EOF

%nonassoc IEXPR_ARITH
%nonassoc RPAREN

%start <Kx_surface_syntax.program> program
%start <Kx_surface_syntax.source> source_file

%type <Kx_surface_syntax.contract_item> topology_block
%type <Kx_topology_syntax.topology_entry list> topology_entries
%type <Kx_topology_syntax.topology_entry> topology_entry
%type <(Kx_core_syntax.ident * Kx_core_syntax.ident) list> topology_requires_opt point_requirements
%type <Kx_core_syntax.ident * Kx_core_syntax.ident> point_requirement

%%

source_file:
  | frontend_scope_start imports_opt frontend_decls_opt nodes EOF
      {
        { imports = $2; frontend_decls = $3; nodes = $4 }
      }

program:
  | frontend_scope_start imports_opt frontend_decls_opt nodes EOF { $4 }

frontend_scope_start:
  | /* empty */ { () }

imports_opt:
  | /* empty */ { [] }
  | import_decls { $1 }

import_decls:
  | import_decl import_decls { $1 :: $2 }
  | import_decl { [ $1 ] }

import_decl:
  | IMPORT STRING SEMI
      {
        ($2, Some (loc_of_positions (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2)))
      }

frontend_decls_opt:
  | /* empty */ { [] }
  | frontend_decls { $1 }

frontend_decls:
  | frontend_decl frontend_decls { $1 :: $2 }
  | frontend_decl { [$1] }

frontend_decl:
  | type_decl { STypeDecl $1 }
  | domain_decl { SDomainDecl $1 }
  | function_decl { SFunctionDecl $1 }

type_decl:
  | TYPE IDENT EQ enum_ctor_list SEMI
      {
        let () = forbid_reserved_identifier ~context:"enum type" $2 in
        List.iter (fun name -> forbid_reserved_identifier ~context:"enum constructor" name) $4;
        { enum_name = $2; enum_constructors = $4 }
      }

enum_ctor_list:
  | IDENT BAR enum_ctor_list { $1 :: $3 }
  | IDENT { [$1] }

domain_decl:
  | DOMAIN IDENT EQ enum_ctor_list SEMI
      {
        let () = forbid_reserved_identifier ~context:"finite domain" $2 in
        List.iter (fun name -> forbid_reserved_identifier ~context:"finite domain member" name) $4;
        { domain_name = $2; domain_members = $4 }
      }

function_decl:
  | FUNCTION IDENT LPAREN params_opt RPAREN COLON ty function_contracts_opt EQ expr SEMI
      {
        let () = forbid_reserved_identifier ~context:"function name" $2 in
        if String.equal $2 "result" then
          failwith "function name 'result' is reserved for function postconditions";
        List.iter
          (fun (v:raw_vdecl) ->
            forbid_reserved_identifier ~context:"function parameter" v.raw_vname;
            if String.equal v.raw_vname "result" then
              failwith "function parameter 'result' is reserved for function postconditions")
          $4;
        let reqs, enss = $8 in
        {
          function_name = $2;
          function_params = $4;
          function_return = $7;
          function_requires = reqs;
          function_ensures = enss;
          function_body = $10;
        }
      }

function_contracts_opt:
  | /* empty */ { ([], []) }
  | function_contracts { $1 }

function_contracts:
  | REQUIRES COLON fo_formula SEMI function_contracts
      {
        let reqs, enss = $5 in
        ($3 :: reqs, enss)
      }
  | ENSURES COLON fo_formula SEMI function_contracts
      {
        let reqs, enss = $5 in
        (reqs, $3 :: enss)
      }
  | REQUIRES COLON fo_formula SEMI { ([$3], []) }
  | ENSURES COLON fo_formula SEMI { ([], [$3]) }

predicate_decl:
  | PREDICATE IDENT LPAREN pred_params_opt RPAREN EQ fo_formula SEMI
      {
        let () = forbid_reserved_identifier ~context:"predicate name" $2 in
        List.iter (fun name -> forbid_reserved_identifier ~context:"predicate parameter" name) $4;
        { predicate_name = $2; predicate_params = $4; predicate_body = $7 }
      }

pred_params_opt:
  | /* empty */ { [] }
  | pred_params { $1 }

pred_params:
  | IDENT COMMA pred_params { $1 :: $3 }
  | IDENT { [$1] }

nodes:
  | node nodes { $1 :: $2 }
  | node { [$1] }

node:
  NODE IDENT LPAREN params_opt RPAREN RETURNS LPAREN params_opt RPAREN
  alias_decls_opt
  ghosts_opt
  predicate_decls_opt
  action_decls_opt
  node_contracts_block instances_opt
  locals_opt
  STATES state_decls SEMI
  state_invariants_opt
  TRANS transitions
  END
  {
    let () = forbid_reserved_identifier ~context:"node name" $2 in
    let states, inline_init = $18 in
    let init_state = resolve_init_state ~inline_init in
    {
      node_name = $2;
      inputs = $4;
      outputs = $8;
      history_aliases = $10;
      ghosts = $11;
      predicates = $12;
      actions = $13;
      contracts = $14;
      instances = $15;
      locals = $16;
      state_decls = { states; init_state };
      state_invariants = $20;
      transitions = $22;
    }
  }

params_opt:
  | /* empty */ { [] }
  | params { $1 }

params:
  | param COMMA params { $1 @ $3 }
  | param { $1 }

param:
  param_name COLON ty
    {
      List.iter (fun (name, _) -> forbid_reserved_identifier ~context:"parameter" name) $1;
      List.map (fun (name, indices) -> {raw_vname=name; raw_indices=indices; raw_vty=$3}) $1
    }

param_name:
  | IDENT { [($1, None)] }
  | IDENT LBRACK decl_index_choices RBRACK
      { [($1, Some $3)] }

ty:
  | TINT { TInt }
  | TBOOL { TBool }
  | TREAL { TReal }
  | IDENT { TCustom $1 }

node_contracts_block:
  | CONTRACTS { [] }
  | CONTRACTS node_contracts { $2 }

instances_opt:
  | /* empty */ { [] }
  | INSTANCES instance_list { $2 }

locals_opt:
  | /* empty */ { [] }
  | LOCALS vdecls_opt { $2 }

ghosts_opt:
  | /* empty */ { [] }
  | GHOSTS vdecls_opt { $2 }

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
  | topology_block node_contracts { $1 :: $2 }
  | topology_block { [$1] }
  | REQUIRES COLON ltl SEMI node_contracts { SCRequires $3 :: $5 }
  | ENSURES COLON ltl SEMI node_contracts { SCEnsures $3 :: $5 }
  | REQUIRES COLON ltl SEMI { [SCRequires $3] }
  | ENSURES COLON ltl SEMI { [SCEnsures $3] }

topology_block:
  | TOPOLOGY topology_entries END { SCTopology $2 }

topology_entries:
  | topology_entry topology_entries { $1 :: $2 }
  | topology_entry { [$1] }

topology_entry:
  | ROUTE IDENT USES ident_list topology_requires_opt SEMI
      {
        let () = forbid_reserved_identifier ~context:"topology route" $2 in
        List.iter (fun name -> forbid_reserved_identifier ~context:"topology track" name) $4;
        List.iter
          (fun (point, pos) ->
            forbid_reserved_identifier ~context:"topology point" point;
            forbid_reserved_identifier ~context:"topology point position" pos)
          $5;
        TRoute { route = $2; tracks = $4; points = $5 }
      }
  | CONFLICT IDENT COMMA IDENT SEMI
      {
        let () = forbid_reserved_identifier ~context:"topology conflict route" $2 in
        let () = forbid_reserved_identifier ~context:"topology conflict route" $4 in
        TConflict ($2, $4)
      }
  | ROUTESIGNAL IDENT ARROW IDENT SEMI
      {
        let () = forbid_reserved_identifier ~context:"topology routeSignal route" $2 in
        let () = forbid_reserved_identifier ~context:"topology routeSignal signal" $4 in
        TRouteSignal ($2, $4)
      }

topology_requires_opt:
  | /* empty */ { [] }
  | REQUIRES point_requirements { $2 }

point_requirements:
  | point_requirement COMMA point_requirements { $1 :: $3 }
  | point_requirement { [$1] }

point_requirement:
  | IDENT EQ IDENT { ($1, $3) }

vdecls_opt:
  | /* empty */ { [] }
  | vdecls { $1 }

vdecls:
  | vdecl_group vdecls { $1 @ $2 }
  | vdecl_group { $1 }

vdecl_group:
  decl_names COLON ty SEMI
    {
      List.iter (fun (name, _) -> forbid_reserved_identifier ~context:"variable declaration" name) $1;
      List.map (fun (name, indices) -> {raw_vname=name; raw_indices=indices; raw_vty=$3}) $1
    }

decl_names:
  | decl_name COMMA decl_names { $1 @ $3 }
  | decl_name { $1 }

decl_name:
  | IDENT { [($1, None)] }
  | IDENT LBRACK decl_index_choices RBRACK
      { [($1, Some $3)] }

decl_index_choices:
  | decl_index_product COMMA decl_index_choices { $1 :: $3 }
  | decl_index_product { [$1] }

decl_index_product:
  | IDENT STAR decl_index_product { $1 :: $3 }
  | IDENT { [$1] }

ident_list:
  | IDENT COMMA ident_list { $1 :: $3 }
  | IDENT { [$1] }

alias_decls_opt:
  | /* empty */ { [] }
  | alias_decls { $1 }

alias_decls:
  | alias_decl alias_decls { $1 :: $2 }
  | alias_decl { [$1] }

alias_decl:
  | LET IDENT IDENT EQ PRE LPAREN IDENT RPAREN SEMI
      {
        let () = forbid_reserved_identifier ~context:"history alias parameter" $3 in
        let () = forbid_reserved_identifier ~context:"history alias rhs parameter" $7 in
        { alias_name = $2; alias_param = $3; alias_rhs_param = $7; alias_k = 1 }
      }
  | LET IDENT IDENT EQ PREK LPAREN IDENT COMMA INT RPAREN SEMI
      {
        let () = forbid_reserved_identifier ~context:"history alias parameter" $3 in
        let () = forbid_reserved_identifier ~context:"history alias rhs parameter" $7 in
        { alias_name = $2; alias_param = $3; alias_rhs_param = $7; alias_k = $9 }
      }

predicate_decls_opt:
  | /* empty */ { [] }
  | predicate_decls { $1 }

predicate_decls:
  | predicate_decl predicate_decls { $1 :: $2 }
  | predicate_decl { [$1] }

action_decls_opt:
  | /* empty */ { [] }
  | action_decls { $1 }

action_decls:
  | action_decl action_decls { $1 :: $2 }
  | action_decl { [$1] }

action_decl:
  | ACTION IDENT LPAREN pred_params_opt RPAREN LBRACE stmt_list_opt RBRACE
      {
        let () = forbid_reserved_identifier ~context:"action name" $2 in
        List.iter (fun name -> forbid_reserved_identifier ~context:"action parameter" name) $4;
        { action_name = $2; action_params = $4; action_body = $7 }
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
      { List.map (fun f -> { state = $3; formula = f }) $5 }

invariant_entries:
  | invariant_entry invariant_entries { $1 @ $2 }
  | invariant_entry { $1 }

invariant_entry:
  | IN IDENT COLON invariant_formula_list
      { List.map (fun f -> { state = $2; formula = f }) $4 }

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
        (fun (dst, guard, body) ->
          { src = $2; dst; guard; body })
        $4
    }
  | IDENT COLON to_transitions {
      List.map
        (fun (dst, guard, body) ->
          { src = $1; dst; guard; body })
        $3
    }

to_transitions:
  | to_transition to_transitions { $1 :: $2 }
  | to_transition { [$1] }

to_transition:
  | TO IDENT guard_opt LBRACE stmt_list_opt RBRACE
      {
        ($2, $3, $5)
      }

match_transitions:
  | match_transition match_transitions { $1 :: $2 }
  | match_transition { [$1] }

match_transition:
  | BAR IDENT ARROW IDENT guard_opt LBRACE stmt_list_opt RBRACE
      {
        { src = $2; dst = $4; guard = $5; body = $7 }
      }

guard_opt:
  | /* empty */ { None }
  | LBRACK expr RBRACK { Some $2 }
  | WHEN expr { Some $2 }

stmt_list_opt:
  | /* empty */ { [] }
  | stmt_list { $1 }

stmt_list:
  | stmt_item stmt_list { $1 @ $2 }
  | stmt_item { $1 }

stmt_item:
  | stmt SEMI { [$1] }
  | IDENT LPAREN id_list_opt RPAREN SEMI
      { [mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 5) (SSActionCall ($1, $3))] }
  | FOR IDENT IN IDENT LBRACE stmt_list_opt RBRACE
      { [mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SSFor ($2, $4, $6))] }

stmt:
  | indexed_ref ASSIGN expr { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SSAssign($1,$3)) }
  | IF expr THEN stmt_list_opt ELSE stmt_list_opt END { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SSIf($2,$4,$6)) }
  | SKIP { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) SSSkip }
  | CALL IDENT LPAREN expr_list_opt RPAREN RETURNS LPAREN id_list_opt RPAREN
      { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 9) (SSCall($2, $4, $8)) }

indexed_ref:
  | IDENT { scalar_ref $1 }
  | IDENT LBRACK ident_list RBRACK { indexed_ref $1 $3 }

(* arithmetic expressions without booleans *)
arith_atom:
  | INT { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SELitInt $1) }
  | indexed_ref { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SEVar $1) }
  | LPAREN arith RPAREN { $2 }

arith_unary:
  | MINUS arith_unary { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SEUn(Neg,$2)) }
  | arith_atom { $1 }

arith_mul:
  | arith_mul STAR arith_unary { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin(Mul,$1,$3)) }
  | arith_mul SLASH arith_unary { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin(Div,$1,$3)) }
  | arith_unary { $1 }

arith:
  | arith PLUS arith_mul { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin(Add,$1,$3)) }
  | arith MINUS arith_mul { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin(Sub,$1,$3)) }
  | arith_mul { $1 }


cmp_atom:
  | arith %prec IEXPR_ARITH { $1 }
  | TRUE { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SELitBool true) }
  | FALSE { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SELitBool false) }

expr_atom:
  | LPAREN expr RPAREN { $2 }
  | IDENT LPAREN expr_list_opt RPAREN
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SECall ($1, $3)) }
  | cmp_atom EQ cmp_atom { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp(REq, $1, $3)) }
  | cmp_atom NEQ cmp_atom { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp(RNeq, $1, $3)) }
  | cmp_atom LT cmp_atom { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp(RLt, $1, $3)) }
  | cmp_atom LE cmp_atom { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp(RLe, $1, $3)) }
  | cmp_atom GT cmp_atom { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp(RGt, $1, $3)) }
  | cmp_atom GE cmp_atom { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp(RGe, $1, $3)) }
  | cmp_atom { $1 }

expr_not:
  | NOT expr_not { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SEUn(Not,$2)) }
  | expr_atom { $1 }

expr_and:
  | expr_and AND expr_not { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin(And,$1,$3)) }
  | expr_not { $1 }

expr_or:
  | expr_or OR expr_and { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin(Or,$1,$3)) }
  | expr_and { $1 }

expr:
  | expr_or { $1 }


expr_list_opt:
  | /* empty */ { [] }
  | expr_list { $1 }

expr_list:
  | expr COMMA expr_list { $1 :: $3 }
  | expr { [$1] }

id_list_opt:
  | /* empty */ { [] }
  | id_list { $1 }

id_list:
  | IDENT COMMA id_list { $1 :: $3 }
  | IDENT { [$1] }

h_atom:
  | INT { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitInt $1) }
  | TRUE { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitBool true) }
  | FALSE { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitBool false) }
  | IDENT indexed_ref { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SHHistoryAlias ($1, $2)) }
  | indexed_ref { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHVar $1) }
  | PRE LPAREN indexed_ref RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SHPreK ($3, 1))
    }
  | PREK LPAREN indexed_ref COMMA INT RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHPreK ($3, $5))
    }
  | LBRACE expr RBRACE { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHExpr $2) }
  | LPAREN hexpr RPAREN { $2 }

h_unary:
  | MINUS h_unary { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SHUn (Neg, $2)) }
  | h_atom { $1 }

h_mul:
  | h_mul STAR h_unary { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Mul, $1, $3)) }
  | h_mul SLASH h_unary { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Div, $1, $3)) }
  | h_unary { $1 }

h_arith:
  | h_arith PLUS h_mul { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Add, $1, $3)) }
  | h_arith MINUS h_mul { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Sub, $1, $3)) }
  | h_mul { $1 }

hexpr:
  | h_arith { $1 }

ltl_atom:
  | hexpr relop hexpr { SLAtom($1,$2,$3) }
  | IDENT LPAREN id_list_opt RPAREN
      { SLFo (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SHCall ($1, $3))) }
  | FORALL IDENT IN IDENT DOT ltl
      { SLForall ($2, $4, $6) }
  | EXISTS IDENT IN IDENT DOT ltl
      { SLExists ($2, $4, $6) }
  | MAINTAINEDUNTIL LPAREN ltl COMMA ltl COMMA ltl RPAREN
      { SLMaintainedUntil ($3, $5, $7) }
  | WHILEROUTELOCKED LPAREN IDENT COMMA ltl RPAREN
      {
        let () = forbid_reserved_identifier ~context:"whileRouteLocked route" $3 in
        SLWhileRouteLocked ($3, $5)
      }
  | LPAREN ltl RPAREN { $2 }

fo_leaf:
  | hexpr relop hexpr { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHCmp($2,$1,$3)) }
  | IDENT LPAREN id_list_opt RPAREN
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SHCall ($1, $3)) }
  | FORALL IDENT IN IDENT DOT fo_formula
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHForall ($2, $4, $6)) }
  | EXISTS IDENT IN IDENT DOT fo_formula
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHExists ($2, $4, $6)) }
  | LPAREN fo_formula RPAREN { $2 }

fo_un:
  | NOT fo_un { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SHUn(Not,$2)) }
  | fo_leaf { $1 }

fo_and:
  | fo_and AND fo_un { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin(And,$1,$3)) }
  | fo_un { $1 }

fo_or:
  | fo_or OR fo_and { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin(Or,$1,$3)) }
  | fo_and { $1 }

fo_formula:
  | fo_imp { $1 }

fo_imp:
  | fo_or IMPL fo_imp {
      let not_lhs = mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHUn(Not,$1)) in
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin(Or, not_lhs, $3))
    }
  | fo_or { $1 }

ltl_un:
  | NOT ltl_un { SLNot $2 }
  | X ltl_un { SLX $2 }
  | G ltl_un { SLG $2 }
  | ltl_atom { $1 }

ltl_and:
  | ltl_and AND ltl_un { SLAnd($1,$3) }
  | ltl_un { $1 }

ltl_or:
  | ltl_or OR ltl_and { SLOr($1,$3) }
  | ltl_and { $1 }

ltl_w:
  | ltl_or W ltl_w { SLW($1,$3) }
  | ltl_or R ltl_w { SLW($3, SLAnd($1, $3)) }
  | ltl_or { $1 }

ltl:
  | ltl_imp { $1 }

ltl_imp:
  | ltl_w IMPL ltl_imp { SLImp($1,$3) }
  | ltl_w { $1 }

relop:
  | EQ { REq }
  | NEQ { RNeq }
  | LT { RLt }
  | LE { RLe }
  | GT { RGt }
  | GE { RGe }
