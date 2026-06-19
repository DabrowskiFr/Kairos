%{
open Kx_core_syntax
open Kx_surface_syntax

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

let mk_history_expr_loc start_pos end_pos desc =
  Kx_surface_syntax.mk_history_expr ~loc:(loc start_pos end_pos) desc

let indexed_ref base indices = { ref_base = base; ref_indices = indices }
let scalar_ref base = indexed_ref base []

let indexed_ref_name (r:indexed_ref) : string =
  String.concat "_" (r.ref_base :: r.ref_indices)

let is_scalar_ref_named (name:string) (r:indexed_ref) : bool =
  String.equal r.ref_base name && r.ref_indices = []

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

let has_prefix ~(prefix:string) (s:string) : bool =
  let plen = String.length prefix in
  String.length s >= plen && String.equal (String.sub s 0 plen) prefix

let internal_identifier_prefix = "__kairos_"

let forbid_reserved_identifier ~(context:string) (id:string) : unit =
  if is_reserved_history_alias_name id then
    failwith
      (Printf.sprintf
         "identifier '%s' is reserved for implicit history aliases (context: %s)" id context)
  else if has_prefix ~prefix:internal_identifier_prefix id then
    failwith
      (Printf.sprintf "identifier '%s' uses the reserved internal prefix %s (context: %s)"
         id internal_identifier_prefix context)

let concise_observer_error ~(observer:string) ~(phase:string) (msg:string) : 'a =
  failwith (Printf.sprintf "concise observer '%s' %s expression %s" observer phase msg)

let rec observer_expr_of_hexpr ~(observer:string) ~(phase:string) (h:hexpr) : expr =
  let mk desc = Kx_surface_syntax.mk_expr ?loc:h.hloc desc in
  match h.shexpr with
  | SHLitInt n -> mk (SELitInt n)
  | SHLitBool b -> mk (SELitBool b)
  | SHVar r when is_scalar_ref_named observer r ->
      concise_observer_error ~observer ~phase
        "reads the observer directly; use pre(observer) in the step expression"
  | SHVar r -> mk (SEVar r)
  | SHPreK (r, SNNat 1) when String.equal phase "step" && is_scalar_ref_named observer r ->
      mk (SEVar r)
  | SHPreK (r, _) when is_scalar_ref_named observer r ->
      concise_observer_error ~observer ~phase
        "can only use pre(observer) in the step expression"
  | SHPreK _ ->
      concise_observer_error ~observer ~phase
        "can only use pre(observer) for the observer being defined"
  | SHExpr _ ->
      concise_observer_error ~observer ~phase
        "cannot embed executable expressions with braces"
  | SHPast _ | SHHistoryCall _ | SHHistoryAlias _ | SHCall _
  | SHForall _ | SHExists _ | SHRangeForall _ | SHRangeExists _ ->
      concise_observer_error ~observer ~phase
        "uses a construct that is not supported in concise observer equations"
  | SHBin (op, a, b) ->
      mk (SEBin (op, observer_expr_of_hexpr ~observer ~phase a,
                 observer_expr_of_hexpr ~observer ~phase b))
  | SHCmp (op, a, b) ->
      mk (SECmp (op, observer_expr_of_hexpr ~observer ~phase a,
                 observer_expr_of_hexpr ~observer ~phase b))
  | SHUn (op, inner) ->
      mk (SEUn (op, observer_expr_of_hexpr ~observer ~phase inner))

let rec observer_stmts_of_history_expr ~(observer:string) ~(phase:string)
    (h:history_expr) : stmt list =
  match h.shistory_expr with
  | SHValue formula ->
      [ Kx_surface_syntax.mk_stmt ?loc:h.hvloc
          (SSAssign (scalar_ref observer, observer_expr_of_hexpr ~observer ~phase formula)) ]
  | SHIf (cond, then_value, else_value) ->
      [ Kx_surface_syntax.mk_stmt ?loc:h.hvloc
          (SSIf
             ( observer_expr_of_hexpr ~observer ~phase cond,
               observer_stmts_of_history_expr ~observer ~phase then_value,
               observer_stmts_of_history_expr ~observer ~phase else_value )) ]

let rec expr_refs (e:expr) : string list =
  match e.sexpr with
  | SELitInt _ | SELitBool _ -> []
  | SEVar r -> [indexed_ref_name r]
  | SECall (_, args) -> List.concat_map expr_refs args
  | SEBin (_, a, b) | SECmp (_, a, b) -> expr_refs a @ expr_refs b
  | SEUn (_, inner) -> expr_refs inner

let first_duplicate (names:string list) : string option =
  let rec loop seen = function
    | [] -> None
    | name :: rest ->
        if List.mem name seen then Some name else loop (name :: seen) rest
  in
  loop [] names

let multiple_assign_stmts start_pos end_pos (lhs:indexed_ref list) (rhs:expr list) : stmt list =
  let lhs_len = List.length lhs in
  let rhs_len = List.length rhs in
  if lhs_len <> rhs_len then
    failwith
      (Printf.sprintf
         "multiple assignment arity mismatch: %d left-hand side(s) but %d right-hand side(s)"
         lhs_len rhs_len);
  let lhs_names = List.map indexed_ref_name lhs in
  if lhs_len > 1 then (
    (match first_duplicate lhs_names with
    | Some name ->
        failwith (Printf.sprintf "multiple assignment assigns '%s' more than once" name)
    | None -> ());
    let rhs_refs = List.concat_map expr_refs rhs in
    (match List.find_opt (fun name -> List.mem name rhs_refs) lhs_names with
    | Some name ->
        failwith
          (Printf.sprintf
             "multiple assignment right-hand side mentions assigned variable '%s'" name)
    | None -> ()));
  List.map2
    (fun target value ->
      mk_stmt_loc start_pos end_pos (SSAssign (target, value)))
    lhs rhs

%}

%token TYPE FUNCTION PREDICATE ACTION SPEC DEF HISTORY
%token NODE RETURNS LOCALS GHOSTS OBSERVERS STATES INIT STEP TRANS END
%token REQUIRES ENSURES
%token INVARIANT IN
%token INVARIANTS
%token CONTRACTS
%token LET
%token IMPORT
%token INSTANCE INSTANCES CALL
%token IF THEN ELSE SKIP FOR FORALL EXISTS
%token WHEN
%token MATCH WITH BAR
%token FROM TO
%token TRUE FALSE
%token TINT TBOOL TREAL FORMULA HEXPR NAT
%token PRE
%token PREK
%token PAST
%token AND OR NOT
%token G X W R
%token LPAREN RPAREN LBRACE RBRACE LBRACK RBRACK COMMA SEMI COLON DOT DOLLAR
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
  | function_decl { SFunctionDecl $1 }
  | spec_def_decl { SSpecDefDecl $1 }
  | history_def_decl { SHistoryDefDecl $1 }

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

spec_def_decl:
  | SPEC DEF IDENT LPAREN spec_params_opt RPAREN EQ ltl SEMI
      {
        let () = forbid_reserved_identifier ~context:"spec definition name" $3 in
        {
          spec_def_name = $3;
          spec_def_params = $5;
          spec_def_body = $8;
        }
      }

history_def_decl:
  | HISTORY DEF IDENT LPAREN IDENT COLON HEXPR RPAREN COLON ty
    INIT EQ history_expr SEMI history_init_ensures_opt
    STEP EQ history_expr SEMI history_step_ensures_opt
      {
        let () = forbid_reserved_identifier ~context:"history definition name" $3 in
        let () = forbid_reserved_identifier ~context:"history definition parameter" $5 in
        if String.equal $5 "self" then
          failwith "history definition parameter 'self' is reserved for the generated history value";
        {
          history_def_name = $3;
          history_param = $5;
          history_ty = $10;
          history_init = $13;
          history_init_ensures = $15;
          history_step = $18;
          history_step_ensures = $20;
        }
      }

history_init_ensures_opt:
  | /* empty */ { [] }
  | history_init_ensures { $1 }

history_init_ensures:
  | INIT ENSURES COLON fo_formula SEMI history_init_ensures { $4 :: $6 }
  | INIT ENSURES COLON fo_formula SEMI { [$4] }

history_step_ensures_opt:
  | /* empty */ { [] }
  | history_step_ensures { $1 }

history_step_ensures:
  | STEP ENSURES COLON fo_formula SEMI history_step_ensures { $4 :: $6 }
  | STEP ENSURES COLON fo_formula SEMI { [$4] }

history_expr:
  | IF fo_formula THEN history_expr ELSE history_expr END
      {
        mk_history_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7)
          (SHIf ($2, $4, $6))
      }
  | hexpr
      {
        mk_history_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1)
          (SHValue $1)
      }

spec_params_opt:
  | /* empty */ { [] }
  | spec_params { $1 }

spec_params:
  | spec_param COMMA spec_params { $1 :: $3 }
  | spec_param { [$1] }

spec_param:
  | IDENT COLON spec_param_kind
      {
        let () = forbid_reserved_identifier ~context:"spec definition parameter" $1 in
        { spec_param_name = $1; spec_param_kind = $3 }
      }

spec_param_kind:
  | FORMULA { SPFormula }
  | HEXPR { SPHExpr }
  | NAT { SPNat }

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
	  observers_opt
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
	    let states, inline_init = $19 in
	    let init_state = resolve_init_state ~inline_init in
	    {
	      node_name = $2;
	      inputs = $4;
	      outputs = $8;
	      history_aliases = $10;
	      ghosts = $11;
	      observers = $12;
	      predicates = $13;
	      actions = $14;
	      contracts = $15;
	      instances = $16;
	      locals = $17;
	      state_decls = { states; init_state };
	      state_invariants = $21;
	      transitions = $23;
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

observers_opt:
  | /* empty */ { [] }
  | OBSERVERS observer_decls { $2 }

observer_decls:
  | observer_decl observer_decls { $1 :: $2 }
  | observer_decl { [$1] }

observer_decl:
  | IDENT COLON ty INIT LBRACE stmt_list_opt RBRACE STEP LBRACE stmt_list_opt RBRACE
      {
        let () = forbid_reserved_identifier ~context:"observer name" $1 in
        {
          observer_name = $1;
          observer_ty = $3;
          observer_init = $6;
          observer_step = $10;
        }
	      }
  | IDENT COLON ty EQ history_expr ARROW history_expr SEMI
      {
        let () = forbid_reserved_identifier ~context:"observer name" $1 in
        {
          observer_name = $1;
          observer_ty = $3;
          observer_init = observer_stmts_of_history_expr ~observer:$1 ~phase:"init" $5;
          observer_step = observer_stmts_of_history_expr ~observer:$1 ~phase:"step" $7;
        }
      }

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
  | REQUIRES COLON ltl SEMI node_contracts { SCRequires $3 :: $5 }
  | ENSURES COLON ltl SEMI node_contracts { SCEnsures $3 :: $5 }
  | REQUIRES COLON ltl SEMI { [SCRequires $3] }
  | ENSURES COLON ltl SEMI { [SCEnsures $3] }

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
          { src = $2; dst; guard; body; ensures = [] })
        $4
    }
  | IDENT COLON to_transitions {
      List.map
        (fun (dst, guard, body) ->
          { src = $1; dst; guard; body; ensures = [] })
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
        { src = $2; dst = $4; guard = $5; body = $7; ensures = [] }
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
  | assignment_stmt SEMI { $1 }
  | stmt SEMI { [$1] }
  | IDENT LPAREN id_list_opt RPAREN SEMI
      { [mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 5) (SSActionCall ($1, $3))] }
  | FOR IDENT IN IDENT LBRACE stmt_list_opt RBRACE
      { [mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SSFor ($2, $4, $6))] }

assignment_stmt:
  | indexed_ref_list ASSIGN expr_list
      {
        multiple_assign_stmts
          (Parsing.rhs_start_pos 1)
          (Parsing.rhs_end_pos 3)
          $1
          $3
      }

stmt:
  | IF expr THEN stmt_list_opt ELSE stmt_list_opt END { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SSIf($2,$4,$6)) }
  | SKIP { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) SSSkip }
  | CALL IDENT LPAREN expr_list_opt RPAREN RETURNS LPAREN id_list_opt RPAREN
      { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 9) (SSCall($2, $4, $8)) }

indexed_ref:
  | IDENT { scalar_ref $1 }
  | IDENT LBRACK ident_list RBRACK { indexed_ref $1 $3 }

indexed_ref_list:
  | indexed_ref COMMA indexed_ref_list { $1 :: $3 }
  | indexed_ref { [$1] }

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

nat_expr:
  | INT { SNNat $1 }
  | IDENT { SNVar $1 }

spec_arg_list_opt:
  | /* empty */ { [] }
  | spec_arg_list { $1 }

spec_arg_list:
  | spec_arg COMMA spec_arg_list { $1 :: $3 }
  | spec_arg { [$1] }

spec_arg:
  | LBRACK ltl RBRACK { SAFormula $2 }
  | DOLLAR IDENT { SAFormula (SLFormulaParam $2) }
  | hexpr { SAHExpr $1 }

h_atom:
  | INT { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitInt $1) }
  | TRUE { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitBool true) }
  | FALSE { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitBool false) }
  | HISTORY IDENT LPAREN indexed_ref RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 5) (SHHistoryCall ($2, $4))
    }
  | IDENT indexed_ref { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SHHistoryAlias ($1, $2)) }
  | indexed_ref { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHVar $1) }
  | PRE LPAREN indexed_ref RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SHPreK ($3, SNNat 1))
    }
  | PREK LPAREN indexed_ref COMMA nat_expr RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHPreK ($3, $5))
    }
  | PAST LPAREN hexpr COMMA nat_expr RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHPast ($3, $5))
    }
  | PAST LPAREN fo_formula COMMA nat_expr RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHPast ($3, $5))
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
  | DOLLAR IDENT { SLFormulaParam $2 }
  | IDENT LPAREN spec_arg_list_opt RPAREN
      { SLCall ($1, $3) }
  | FORALL IDENT IN IDENT DOT ltl
      { SLForall ($2, $4, $6) }
  | EXISTS IDENT IN IDENT DOT ltl
      { SLExists ($2, $4, $6) }
  | FORALL IDENT IN nat_expr DOT DOT nat_expr DOT ltl
      { SLRangeForall ($2, $4, $7, $9) }
  | EXISTS IDENT IN nat_expr DOT DOT nat_expr DOT ltl
      { SLRangeExists ($2, $4, $7, $9) }
  | LPAREN ltl RPAREN { $2 }

fo_leaf:
  | hexpr relop hexpr { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHCmp($2,$1,$3)) }
  | IDENT LPAREN id_list_opt RPAREN
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SHCall ($1, $3)) }
  | FORALL IDENT IN IDENT DOT fo_formula
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHForall ($2, $4, $6)) }
  | EXISTS IDENT IN IDENT DOT fo_formula
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHExists ($2, $4, $6)) }
  | FORALL IDENT IN nat_expr DOT DOT nat_expr DOT fo_formula
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 9) (SHRangeForall ($2, $4, $7, $9)) }
  | EXISTS IDENT IN nat_expr DOT DOT nat_expr DOT fo_formula
      { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 9) (SHRangeExists ($2, $4, $7, $9)) }
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
