%{
open Core.Syntax
open Surface.Ast

let loc start_pos end_pos = Shared.Syntax.loc_of_positions start_pos end_pos

let mk_expr_loc start_pos end_pos desc =
  Surface.Ast.mk_expr ~loc:(loc start_pos end_pos) desc

let mk_stmt_loc start_pos end_pos desc =
  Surface.Ast.mk_stmt ~loc:(loc start_pos end_pos) desc

let mk_hexpr_loc start_pos end_pos desc =
  Surface.Ast.mk_hexpr ~loc:(loc start_pos end_pos) desc

let mk_history_expr_loc start_pos end_pos desc =
  Surface.Ast.mk_history_expr ~loc:(loc start_pos end_pos) desc

let hexpr_of_spec_call_arg name = function
  | SAHExpr expression -> expression
  | SAFormula _ ->
      Shared.Error.well_formedness
        (Printf.sprintf
           "call '%s' uses a Formula argument where a value expression is required"
           name)

let force_harith = function
  | `ParsedHExpr expression -> expression
  | `ParsedHCall (name, args, call_loc) ->
      Surface.Ast.mk_hexpr ~loc:call_loc
        (SHCall (name, List.map (hexpr_of_spec_call_arg name) args))

let split_stmt_match_arms arms =
  let rec loop branches default_branch = function
    | [] -> (List.rev branches, default_branch)
    | `Constructor (ctor, body) :: rest ->
        (match default_branch with
        | Some _ ->
            Shared.Error.well_formedness
              (Printf.sprintf
                 "match branch '%s' is unreachable because it follows '_'" ctor)
        | None -> loop ((ctor, body) :: branches) None rest)
    | `Default body :: rest ->
        (match default_branch with
        | Some _ ->
            Shared.Error.well_formedness
              "match contains more than one '_' branch"
        | None -> loop branches (Some body) rest)
  in
  loop [] None arms

let indexed_ref base indices = { ref_base = base; ref_indices = indices }
let scalar_ref base = indexed_ref base []

let indexed_ref_name (r:indexed_ref) : string =
  String.concat "_" (r.ref_base :: r.ref_indices)

let is_scalar_ref_named (name:string) (r:indexed_ref) : bool =
  String.equal r.ref_base name && r.ref_indices = []

let hidden_init_state = "KairosInternalInit"

let resolve_state_decls ~(states:ident list) ~(inline_init:ident option)
    ~(transitions:transition list) : state_decls =
  if List.exists (String.equal hidden_init_state) states then
    Shared.Error.well_formedness
      (Printf.sprintf "state name '%s' is reserved for frontend lowering"
         hidden_init_state);
  let has_explicit_init =
    List.exists (fun (t:transition) -> String.equal t.src hidden_init_state) transitions
  in
  match inline_init, has_explicit_init with
  | Some _, true ->
      Shared.Error.well_formedness
        "initialization is declared twice: use either 'State(init)' or 'transitions init:', not both"
  | Some init_state, false ->
      { states; init_state; init_is_hidden = false }
  | None, true ->
      {
        states = hidden_init_state :: states;
        init_state = hidden_init_state;
        init_is_hidden = true;
      }
  | None, false ->
      Shared.Error.well_formedness
        "missing initialization: add a 'transitions init:' group"

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
    Shared.Error.well_formedness
      (Printf.sprintf
         "identifier '%s' is reserved for implicit history aliases (context: %s)" id context)
  else if has_prefix ~prefix:internal_identifier_prefix id then
    Shared.Error.well_formedness
      (Printf.sprintf "identifier '%s' uses the reserved internal prefix %s (context: %s)"
         id internal_identifier_prefix context)

let concise_observer_error ~(observer:string) ~(phase:string) (msg:string) : 'a =
  Shared.Error.well_formedness
    (Printf.sprintf "concise observer '%s' %s expression %s" observer phase msg)

let rec observer_expr_of_hexpr ~(observer:string) ~(phase:string) (h:hexpr) : expr =
  let mk desc = Surface.Ast.mk_expr ?loc:h.hloc desc in
  match h.shexpr with
  | SHLitInt n -> mk (SELitInt n)
  | SHLitBool b -> mk (SELitBool b)
  | SHVar r when is_scalar_ref_named observer r ->
      concise_observer_error ~observer ~phase
        "reads the observer directly; use pre(observer) in the step expression"
  | SHVar r -> mk (SEVar r)
  | SHPreK (r, SNNat 1) when String.equal phase "step" ->
      mk (SEPre r)
  | SHPreK (r, _) when is_scalar_ref_named observer r ->
      concise_observer_error ~observer ~phase
        "can only use pre(observer) in the step expression"
  | SHPreK _ ->
      concise_observer_error ~observer ~phase
        "can only use pre(observer) for the observer being defined"
  | SHExpr _ ->
      concise_observer_error ~observer ~phase
        "cannot embed executable expressions with braces"
  | SHCall (name, args) ->
      mk
        (SECall
           (name, List.map (observer_expr_of_hexpr ~observer ~phase) args))
  | SHOld _ | SHPast _ | SHHistoryAlias _
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
      [ Surface.Ast.mk_stmt ?loc:h.hvloc
          (SSAssign (scalar_ref observer, observer_expr_of_hexpr ~observer ~phase formula)) ]
  | SHIf (cond, then_value, else_value) ->
      [ Surface.Ast.mk_stmt ?loc:h.hvloc
          (SSIf
             ( observer_expr_of_hexpr ~observer ~phase cond,
               observer_stmts_of_history_expr ~observer ~phase then_value,
               observer_stmts_of_history_expr ~observer ~phase else_value )) ]

let rec expr_refs (e:expr) : string list =
  match e.sexpr with
  | SELitInt _ | SELitBool _ -> []
  | SEVar r | SEPre r -> [indexed_ref_name r]
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
    Shared.Error.well_formedness
      (Printf.sprintf
         "multiple assignment arity mismatch: %d left-hand side(s) but %d right-hand side(s)"
         lhs_len rhs_len);
  let lhs_names = List.map indexed_ref_name lhs in
  if lhs_len > 1 then (
    (match first_duplicate lhs_names with
    | Some name ->
        Shared.Error.well_formedness
          (Printf.sprintf "multiple assignment assigns '%s' more than once" name)
    | None -> ());
    let rhs_refs = List.concat_map expr_refs rhs in
    (match List.find_opt (fun name -> List.mem name rhs_refs) lhs_names with
    | Some name ->
        Shared.Error.well_formedness
          (Printf.sprintf
             "multiple assignment right-hand side mentions assigned variable '%s'" name)
    | None -> ()));
  List.map2
    (fun target value ->
      mk_stmt_loc start_pos end_pos (SSAssign (target, value)))
    lhs rhs

let range_strings lo hi =
  if lo > hi then
    Shared.Error.well_formedness "empty integer range in indexed declaration";
  let rec loop acc n =
    if n < lo then acc else loop (string_of_int n :: acc) (n - 1)
  in
  loop [] hi

%}

%token TYPE FUNCTION PREDICATE METHOD SPEC DEF
%token NODE RETURNS LOCALS GHOSTS OBSERVERS STATES INIT STEP TRANS END
%token REQUIRES ENSURES ASSUME GUARANTEE
%token INVARIANT IN INOUT
%token INVARIANTS
%token EXCEPT
%token CONTRACTS
%token LET
%token IF THEN ELSE SKIP FOR FORALL EXISTS WHILE DO VARIANT
%token WHEN
%token MATCH WITH BAR UNDERSCORE
%token FROM TO
%token TRUE FALSE
%token TINT TBOOL TREAL FORMULA HEXPR NAT
%token PRE OLD
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
%token EOF

%nonassoc IEXPR_ARITH
%nonassoc RPAREN

%start <Surface.Ast.program> program
%start <Surface.Ast.source> source_file

%%

source_file:
  | frontend_scope_start frontend_decls_opt nodes EOF
      {
        { frontend_decls = $2; nodes = $3 }
      }
  | frontend_scope_start frontend_decls_opt EOF
      {
        { frontend_decls = $2; nodes = [] }
      }

program:
  | frontend_scope_start frontend_decls_opt nodes EOF { $3 }

frontend_scope_start:
  | /* empty */ { () }

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
          Shared.Error.well_formedness
            "function name 'result' is reserved for function postconditions";
        List.iter
          (fun (v:raw_vdecl) ->
            forbid_reserved_identifier ~context:"function parameter" v.raw_vname;
            if String.equal v.raw_vname "result" then
              Shared.Error.well_formedness
                "function parameter 'result' is reserved for function postconditions")
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

history_expr:
  | IF fo_formula THEN history_expr ELSE history_expr END
      {
        mk_history_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7)
          (SHIf ($2, $4, $6))
      }
  | hexpr
      {
        mk_history_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1)
          (SHValue (force_harith $1))
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
  | PREDICATE IDENT LPAREN typed_params_opt RPAREN EQ fo_formula SEMI
      {
        let () = forbid_reserved_identifier ~context:"predicate name" $2 in
        List.iter
          (fun param ->
            forbid_reserved_identifier ~context:"predicate parameter" param.param_name)
          $4;
        { predicate_name = $2; predicate_params = $4; predicate_body = $7 }
      }

typed_params_opt:
  | /* empty */ { [] }
  | typed_params { $1 }

typed_params:
  | typed_param COMMA typed_params { $1 :: $3 }
  | typed_param { [$1] }

typed_param:
  | IDENT COLON ty { { param_name = $1; param_ty = $3 } }

nodes:
  | node nodes { $1 :: $2 }
  | node { [$1] }

node:
  NODE IDENT LPAREN params_opt RPAREN RETURNS LPAREN params_opt RPAREN
	  alias_decls_opt
	  ghosts_opt
	  observers_opt
	  predicate_decls_opt
	  method_decls_opt
	  node_contracts_block
  locals_opt
	  STATES state_decls SEMI
  state_invariants_opt
	  TRANS transitions
	  END
	  {
	    let () = forbid_reserved_identifier ~context:"node name" $2 in
	    let states, inline_init = $18 in
	    let state_decls =
	      resolve_state_decls ~states ~inline_init ~transitions:$22
	    in
	    {
	      node_name = $2;
	      inputs = $4;
	      outputs = $8;
	      history_aliases = $10;
	      ghosts = $11;
	      observers = $12;
	      predicates = $13;
	      methods = $14;
	      contracts = $15;
	      locals = $16;
	      state_decls;
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
  | IDENT COLON ty INIT LBRACE observer_stmt_list_opt RBRACE STEP LBRACE observer_stmt_list_opt RBRACE
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

node_contracts:
  | ASSUME contract_name_opt COLON ltl SEMI node_contracts
      { SCAssume ($2, $4) :: $6 }
  | GUARANTEE contract_name_opt COLON ltl SEMI node_contracts
      { SCGuarantee ($2, $4) :: $6 }
  | ASSUME contract_name_opt COLON ltl SEMI
      { [SCAssume ($2, $4)] }
  | GUARANTEE contract_name_opt COLON ltl SEMI
      { [SCGuarantee ($2, $4)] }

contract_name_opt:
  | /* empty */ { None }
  | IDENT
      {
        let () = forbid_reserved_identifier ~context:"contract name" $1 in
        Some $1
      }

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
  | decl_index_choice COMMA decl_index_choices { $1 @ $3 }
  | decl_index_choice { $1 }

decl_index_choice:
  | decl_index_product { [$1] }
  | INT DOT DOT INT { List.map (fun i -> [i]) (range_strings $1 $4) }

decl_index_product:
  | decl_index_atom STAR decl_index_product { $1 :: $3 }
  | decl_index_atom { [$1] }

decl_index_atom:
  | IDENT { $1 }
  | INT { string_of_int $1 }

ident_list:
  | IDENT COMMA ident_list { $1 :: $3 }
  | IDENT { [$1] }

index_arg_list:
  | index_arg COMMA index_arg_list { $1 :: $3 }
  | index_arg { [$1] }

index_arg:
  | IDENT { $1 }
  | INT { string_of_int $1 }

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
        {
          alias_name = $2;
          alias_param = $3;
          alias_rhs_param = $7;
          alias_k = $9;
        }
      }

predicate_decls_opt:
  | /* empty */ { [] }
  | predicate_decls { $1 }

predicate_decls:
  | predicate_decl predicate_decls { $1 :: $2 }
  | predicate_decl { [$1] }

method_decls_opt:
  | /* empty */ { [] }
  | method_decls { $1 }

method_decls:
  | method_decl method_decls { $1 :: $2 }
  | method_decl { [$1] }

method_decl:
  | METHOD IDENT LPAREN method_params_opt RPAREN method_contracts_opt LBRACE stmt_list_opt RBRACE
      {
        let () = forbid_reserved_identifier ~context:"method name" $2 in
        List.iter
          (fun param ->
            forbid_reserved_identifier ~context:"method parameter"
              param.method_param_name)
          $4;
        let requires, ensures = $6 in
        { method_name = $2; method_params = $4; method_requires = requires;
          method_ensures = ensures; method_body = $8 }
      }

method_params_opt:
  | /* empty */ { [] }
  | method_params { $1 }

method_params:
  | method_param COMMA method_params { $1 :: $3 }
  | method_param { [$1] }

method_param:
  | IDENT COLON ty
      {
        { method_param_name = $1; method_param_ty = $3;
          method_param_mode = MPIn }
      }
  | IN IDENT COLON ty
      {
        { method_param_name = $2; method_param_ty = $4;
          method_param_mode = MPIn }
      }
  | INOUT IDENT COLON ty
      {
        { method_param_name = $2; method_param_ty = $4;
          method_param_mode = MPInOut }
      }

method_contracts_opt:
  | /* empty */ { ([], []) }
  | CONTRACTS method_contracts { $2 }

method_contracts:
  | method_contract method_contracts
      {
        let reqs, enss = $2 in
        match $1 with
        | `Requires f -> (f :: reqs, enss)
        | `Ensures f -> (reqs, f :: enss)
      }
  | method_contract
      {
        match $1 with
        | `Requires f -> ([f], [])
        | `Ensures f -> ([], [f])
      }

method_contract:
  | REQUIRES COLON fo_formula SEMI { `Requires $3 }
  | ENSURES COLON fo_formula SEMI { `Ensures $3 }

state_decls:
  | state_decl COMMA state_decls {
      let s, i = $1 in
      let ss, ii = $3 in
      let init_opt =
        match (i, ii) with
        | None, x | x, None -> x
        | Some a, Some b when String.equal a b -> Some a
        | Some a, Some b ->
            Shared.Error.well_formedness
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
  | INVARIANT IN state_selector COLON invariant_formula_list
      { List.map (fun f -> { selector = $3; formula = f }) $5 }

invariant_entries:
  | invariant_entry invariant_entries { $1 @ $2 }
  | invariant_entry { $1 }

invariant_entry:
  | IN state_selector COLON invariant_formula_list
      { List.map (fun f -> { selector = $2; formula = f }) $4 }

state_selector:
  | state_selector_diff { $1 }

state_selector_diff:
  | state_selector_diff EXCEPT state_selector_atom { SSelDiff ($1, $3) }
  | state_selector_atom { $1 }

state_selector_atom:
  | IDENT { SSelState $1 }
  | STATES { SSelAll }
  | LBRACE ident_list RBRACE { SSelSet $2 }
  | LPAREN state_selector RPAREN { $2 }

invariant_formula_list:
  | fo_formula SEMI invariant_formula_list { $1 :: $3 }
  | fo_formula SEMI { [$1] }

transitions:
  | transition_group transitions { $1 @ $2 }
  | transition_group { $1 }
  | MATCH IDENT WITH match_transitions
      {
        if not (String.equal $2 "state") then
          Shared.Error.well_formedness
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
  | INIT COLON to_transitions {
      List.map
        (fun (dst, guard, body) ->
          { src = hidden_init_state; dst; guard; body; ensures = [] })
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
  | IDENT LPAREN expr_list_opt RPAREN SEMI
      { [mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 5) (SSMethodCall ($1, $3))] }
  | FOR IDENT IN IDENT LBRACE stmt_list_opt RBRACE
      { [mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SSFor ($2, $4, $6))] }
  | FOR IDENT IN nat_expr DOT DOT nat_expr LBRACE stmt_list_opt RBRACE
      { [mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 10) (SSForRange ($2, $4, $7, $9))] }

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
  | IF expr THEN stmt_list_opt if_tail
      {
        let else_branch, end_pos = $5 in
        mk_stmt_loc (Parsing.rhs_start_pos 1) end_pos (SSIf($2,$4,else_branch))
      }
  | WHILE expr loop_annotations DO stmt_list_opt END
      {
        let invariants, variant = $3 in
        mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6)
          (SSWhile ($2, invariants, variant, $5))
      }
  | MATCH expr WITH stmt_match_arms END
      {
        let branches, default_branch = split_stmt_match_arms $4 in
        mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 5)
          (SSMatch ($2, branches, default_branch))
      }
  | SKIP { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) SSSkip }

stmt_match_arms:
  | stmt_match_arm stmt_match_arms { $1 :: $2 }
  | stmt_match_arm { [$1] }

stmt_match_arm:
  | BAR IDENT LBRACE stmt_list_opt RBRACE { `Constructor ($2, $4) }
  | BAR UNDERSCORE LBRACE stmt_list_opt RBRACE { `Default $4 }

if_tail:
  | ELSE stmt_list_opt END { ($2, Parsing.rhs_end_pos 3) }
  | END { ([], Parsing.rhs_end_pos 1) }

loop_annotations:
  | /* empty */ { ([], None) }
  | loop_annotation loop_annotations
      {
        let invs, variant = $2 in
        match $1 with
        | `Invariant inv -> (inv :: invs, variant)
        | `Variant v ->
            (match variant with
            | None -> (invs, Some v)
            | Some _ -> Shared.Error.well_formedness "while loop has more than one variant")
      }

loop_annotation:
  | INVARIANT COLON fo_formula SEMI { `Invariant $3 }
  | VARIANT COLON expr SEMI { `Variant $3 }

indexed_ref:
  | IDENT { scalar_ref $1 }
  | IDENT LBRACK index_arg_list RBRACK { indexed_ref $1 $3 }

indexed_ref_list:
  | indexed_ref COMMA indexed_ref_list { $1 :: $3 }
  | indexed_ref { [$1] }

(* arithmetic expressions without booleans *)
arith_atom:
  | INT { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SELitInt $1) }
  | indexed_ref { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SEVar $1) }
  | IDENT LPAREN expr_list_opt RPAREN
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SECall ($1, $3)) }
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

(* Observer blocks use the executable expression language extended with
   [pre(reference)]. Keeping this grammar separate makes [pre] unavailable in
   transitions, methods, function bodies, guards, and loop expressions. *)
observer_stmt_list_opt:
  | /* empty */ { [] }
  | observer_stmt_list { $1 }

observer_stmt_list:
  | observer_stmt_item observer_stmt_list { $1 @ $2 }
  | observer_stmt_item { $1 }

observer_stmt_item:
  | observer_assignment_stmt SEMI { $1 }
  | observer_stmt SEMI { [$1] }

observer_assignment_stmt:
  | indexed_ref_list ASSIGN observer_expr_list
      {
        multiple_assign_stmts
          (Parsing.rhs_start_pos 1)
          (Parsing.rhs_end_pos 3)
          $1
          $3
      }

observer_stmt:
  | IF observer_expr THEN observer_stmt_list_opt observer_if_tail
      {
        let else_branch, end_pos = $5 in
        mk_stmt_loc (Parsing.rhs_start_pos 1) end_pos
          (SSIf ($2, $4, else_branch))
      }
  | MATCH observer_expr WITH observer_stmt_match_arms END
      {
        let branches, default_branch = split_stmt_match_arms $4 in
        mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 5)
          (SSMatch ($2, branches, default_branch))
      }
  | SKIP
      { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) SSSkip }

observer_stmt_match_arms:
  | observer_stmt_match_arm observer_stmt_match_arms { $1 :: $2 }
  | observer_stmt_match_arm { [$1] }

observer_stmt_match_arm:
  | BAR IDENT LBRACE observer_stmt_list_opt RBRACE
      { `Constructor ($2, $4) }
  | BAR UNDERSCORE LBRACE observer_stmt_list_opt RBRACE
      { `Default $4 }

observer_if_tail:
  | ELSE observer_stmt_list_opt END { ($2, Parsing.rhs_end_pos 3) }
  | END { ([], Parsing.rhs_end_pos 1) }

observer_arith_atom:
  | INT
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SELitInt $1) }
  | indexed_ref
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SEVar $1) }
  | PRE LPAREN indexed_ref RPAREN
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SEPre $3) }
  | IDENT LPAREN observer_expr_list_opt RPAREN
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SECall ($1, $3)) }
  | LPAREN observer_arith RPAREN { $2 }

observer_arith_unary:
  | MINUS observer_arith_unary
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SEUn (Neg, $2)) }
  | observer_arith_atom { $1 }

observer_arith_mul:
  | observer_arith_mul STAR observer_arith_unary
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin (Mul, $1, $3)) }
  | observer_arith_mul SLASH observer_arith_unary
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin (Div, $1, $3)) }
  | observer_arith_unary { $1 }

observer_arith:
  | observer_arith PLUS observer_arith_mul
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin (Add, $1, $3)) }
  | observer_arith MINUS observer_arith_mul
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin (Sub, $1, $3)) }
  | observer_arith_mul { $1 }

observer_cmp_atom:
  | observer_arith %prec IEXPR_ARITH { $1 }
  | TRUE
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SELitBool true) }
  | FALSE
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SELitBool false) }

observer_expr_atom:
  | LPAREN observer_expr RPAREN { $2 }
  | observer_cmp_atom EQ observer_cmp_atom
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp (REq, $1, $3)) }
  | observer_cmp_atom NEQ observer_cmp_atom
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp (RNeq, $1, $3)) }
  | observer_cmp_atom LT observer_cmp_atom
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp (RLt, $1, $3)) }
  | observer_cmp_atom LE observer_cmp_atom
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp (RLe, $1, $3)) }
  | observer_cmp_atom GT observer_cmp_atom
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp (RGt, $1, $3)) }
  | observer_cmp_atom GE observer_cmp_atom
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SECmp (RGe, $1, $3)) }
  | observer_cmp_atom { $1 }

observer_expr_not:
  | NOT observer_expr_not
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SEUn (Not, $2)) }
  | observer_expr_atom { $1 }

observer_expr_and:
  | observer_expr_and AND observer_expr_not
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin (And, $1, $3)) }
  | observer_expr_not { $1 }

observer_expr_or:
  | observer_expr_or OR observer_expr_and
      { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SEBin (Or, $1, $3)) }
  | observer_expr_and { $1 }

observer_expr:
  | observer_expr_or { $1 }

observer_expr_list_opt:
  | /* empty */ { [] }
  | observer_expr_list { $1 }

observer_expr_list:
  | observer_expr COMMA observer_expr_list { $1 :: $3 }
  | observer_expr { [$1] }

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
  | fo_formula { SAHExpr $1 }

h_atom:
  | INT { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitInt $1)) }
  | TRUE { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitBool true)) }
  | FALSE { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHLitBool false)) }
  | IDENT indexed_ref { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SHHistoryAlias ($1, $2))) }
  | indexed_ref { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (SHVar $1)) }
  | PRE LPAREN indexed_ref RPAREN {
      `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SHPreK ($3, SNNat 1)))
    }
  | OLD LPAREN hexpr RPAREN {
      `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (SHOld (force_harith $3)))
    }
  | PREK LPAREN indexed_ref COMMA nat_expr RPAREN {
      `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHPreK ($3, $5)))
    }
  | PAST LPAREN fo_formula COMMA nat_expr RPAREN {
      `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (SHPast ($3, $5)))
    }
  | LBRACE expr RBRACE { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHExpr $2)) }
  | IDENT LPAREN spec_arg_list_opt RPAREN
      {
        `ParsedHCall
          ($1, $3, loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4))
      }
  | LPAREN hexpr RPAREN { $2 }

h_unary:
  | MINUS h_unary { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (SHUn (Neg, force_harith $2))) }
  | h_atom { $1 }

h_mul:
  | h_mul STAR h_unary { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Mul, force_harith $1, force_harith $3))) }
  | h_mul SLASH h_unary { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Div, force_harith $1, force_harith $3))) }
  | h_unary { $1 }

h_arith:
  | h_arith PLUS h_mul { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Add, force_harith $1, force_harith $3))) }
  | h_arith MINUS h_mul { `ParsedHExpr (mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHBin (Sub, force_harith $1, force_harith $3))) }
  | h_mul { $1 }

hexpr:
  | h_arith { $1 }

ltl_atom:
  | hexpr relop hexpr { SLAtom(force_harith $1,$2,force_harith $3) }
  | hexpr {
      match $1 with
      | `ParsedHExpr expression -> SLFo expression
      | `ParsedHCall (name, args, _) -> SLCall (name, args)
    }
  | DOLLAR IDENT { SLFormulaParam $2 }
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
  | hexpr relop hexpr { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SHCmp($2,force_harith $1,force_harith $3)) }
  | hexpr { force_harith $1 }
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
