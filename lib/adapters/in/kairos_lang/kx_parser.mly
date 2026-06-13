%{
open Kx_core_syntax
open Kx_ast
open Kx_topology_syntax

let loc_of_positions (start_pos:Lexing.position) (end_pos:Lexing.position) : Kx_loc.loc =
  { line = start_pos.pos_lnum;
    col = start_pos.pos_cnum - start_pos.pos_bol;
    line_end = end_pos.pos_lnum;
    col_end = end_pos.pos_cnum - end_pos.pos_bol; }

let mk_expr_loc start_pos end_pos desc =
  Kx_core_syntax_builders.mk_expr ~loc:(loc_of_positions start_pos end_pos) desc
let mk_stmt_loc start_pos end_pos desc =
  Kx_ast_builders.mk_stmt ~loc:(loc_of_positions start_pos end_pos) desc
let mk_hexpr_loc start_pos end_pos desc =
  Kx_core_syntax_builders.mk_hexpr ~loc:(loc_of_positions start_pos end_pos) desc

let indexed_ident (base:ident) (idx:ident) : ident =
  base ^ "_" ^ idx

let indexed_ident_many (base:ident) (idxs:ident list) : ident =
  String.concat "_" (base :: idxs)

let domain_table : (string, ident list) Hashtbl.t = Hashtbl.create 17
let predicate_table : (string, ident list * hexpr) Hashtbl.t = Hashtbl.create 17

let reset_frontend_tables () =
  Hashtbl.clear domain_table;
  Hashtbl.clear predicate_table

let register_domain ~(name:ident) ~(members:ident list) : unit =
  if Hashtbl.mem domain_table name then
    failwith (Printf.sprintf "duplicate finite domain '%s'" name);
  if members = [] then
    failwith (Printf.sprintf "finite domain '%s' has no members" name);
  Hashtbl.add domain_table name members

let domain_members name =
  match Hashtbl.find_opt domain_table name with
  | Some members -> members
  | None -> failwith (Printf.sprintf "unknown finite domain '%s'" name)

let expand_domain_or_single name =
  match Hashtbl.find_opt domain_table name with
  | Some members -> members
  | None -> [ name ]

let cartesian_concat left right =
  List.concat_map (fun xs -> List.map (fun ys -> xs @ ys) right) left

let register_predicate ~(name:ident) ~(params:ident list) ~(body:hexpr) : unit =
  if Hashtbl.mem predicate_table name then
    failwith (Printf.sprintf "duplicate predicate '%s'" name);
  Hashtbl.add predicate_table name (params, body)

let subst_ident ~(param:ident) ~(value:ident) (id:ident) : ident =
  id
  |> String.split_on_char '_'
  |> List.map (fun part -> if String.equal part param then value else part)
  |> String.concat "_"

let rec subst_expr_index ~(param:ident) ~(value:ident) (e:expr) : expr =
  let expr =
    match e.expr with
    | ELitInt _ | ELitBool _ -> e.expr
    | EVar id -> EVar (subst_ident ~param ~value id)
    | EBin (op, a, b) ->
        EBin (op, subst_expr_index ~param ~value a, subst_expr_index ~param ~value b)
    | ECmp (op, a, b) ->
        ECmp (op, subst_expr_index ~param ~value a, subst_expr_index ~param ~value b)
    | EUn (op, inner) -> EUn (op, subst_expr_index ~param ~value inner)
  in
  { e with expr }

let rec subst_hexpr_index ~(param:ident) ~(value:ident) (h:hexpr) : hexpr =
  let hexpr =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h.hexpr
    | HVar id -> HVar (subst_ident ~param ~value id)
    | HPreK (id, k) -> HPreK (subst_ident ~param ~value id, k)
    | HPred (id, args) ->
        HPred (subst_ident ~param ~value id, List.map (subst_hexpr_index ~param ~value) args)
    | HBin (op, a, b) ->
        HBin (op, subst_hexpr_index ~param ~value a, subst_hexpr_index ~param ~value b)
    | HCmp (op, a, b) ->
        HCmp (op, subst_hexpr_index ~param ~value a, subst_hexpr_index ~param ~value b)
    | HUn (op, inner) -> HUn (op, subst_hexpr_index ~param ~value inner)
  in
  { h with hexpr }

let rec subst_ltl_index ~(param:ident) ~(value:ident) (f:ltl) : ltl =
  match f with
  | LTrue | LFalse -> f
  | LAtom (a, op, b) ->
      LAtom (subst_hexpr_index ~param ~value a, op, subst_hexpr_index ~param ~value b)
  | LNot inner -> LNot (subst_ltl_index ~param ~value inner)
  | LAnd (a, b) -> LAnd (subst_ltl_index ~param ~value a, subst_ltl_index ~param ~value b)
  | LOr (a, b) -> LOr (subst_ltl_index ~param ~value a, subst_ltl_index ~param ~value b)
  | LImp (a, b) -> LImp (subst_ltl_index ~param ~value a, subst_ltl_index ~param ~value b)
  | LX inner -> LX (subst_ltl_index ~param ~value inner)
  | LG inner -> LG (subst_ltl_index ~param ~value inner)
  | LW (a, b) -> LW (subst_ltl_index ~param ~value a, subst_ltl_index ~param ~value b)

let rec subst_stmt_index ~(param:ident) ~(value:ident) (s:stmt) : stmt =
  let stmt =
    match s.stmt with
    | SAssign (id, rhs) -> SAssign (subst_ident ~param ~value id, subst_expr_index ~param ~value rhs)
    | SIf (cond, t, e) ->
        SIf
          ( subst_expr_index ~param ~value cond,
            List.map (subst_stmt_index ~param ~value) t,
            List.map (subst_stmt_index ~param ~value) e )
    | SMatch (scrutinee, branches, dflt) ->
        SMatch
          ( subst_expr_index ~param ~value scrutinee,
            List.map
              (fun (ctor, body) -> (subst_ident ~param ~value ctor, List.map (subst_stmt_index ~param ~value) body))
              branches,
            List.map (subst_stmt_index ~param ~value) dflt )
    | SSkip -> SSkip
    | SCall (callee, args, outs) ->
        SCall
          ( subst_ident ~param ~value callee,
            List.map (subst_expr_index ~param ~value) args,
            List.map (subst_ident ~param ~value) outs )
  in
  { s with stmt }

let subst_many_hexpr params args body =
  if List.length params <> List.length args then
    failwith
      (Printf.sprintf "predicate expects %d arguments but got %d" (List.length params) (List.length args));
  List.fold_left2
    (fun acc param value -> subst_hexpr_index ~param ~value acc)
    body params args

let expand_predicate name args =
  match Hashtbl.find_opt predicate_table name with
  | Some (params, body) -> subst_many_hexpr params args body
  | None -> Kx_core_syntax_builders.mk_hpred name (List.map Kx_core_syntax_builders.mk_hvar args)

let rec ltl_of_fo (h:hexpr) : ltl =
  match h.hexpr with
  | HLitBool true -> LTrue
  | HLitBool false -> LFalse
  | HUn (Not, inner) -> LNot (ltl_of_fo inner)
  | HBin (And, a, b) -> LAnd (ltl_of_fo a, ltl_of_fo b)
  | HBin (Or, a, b) -> LOr (ltl_of_fo a, ltl_of_fo b)
  | HCmp (op, a, b) -> LAtom (a, op, b)
  | _ -> LAtom (h, REq, Kx_core_syntax_builders.mk_hbool true)

let rec expr_of_fo (h:hexpr) : expr =
  let expr =
    match h.hexpr with
    | HLitInt n -> ELitInt n
    | HLitBool b -> ELitBool b
    | HVar id -> EVar id
    | HPreK _ ->
        failwith "historical predicate cannot be used in executable expressions"
    | HPred _ ->
        failwith "unexpanded predicate cannot be used in executable expressions"
    | HBin (op, a, b) -> EBin (op, expr_of_fo a, expr_of_fo b)
    | HCmp (op, a, b) -> ECmp (op, expr_of_fo a, expr_of_fo b)
    | HUn (op, inner) -> EUn (op, expr_of_fo inner)
  in
  Kx_core_syntax_builders.mk_expr expr

let rec ltl_and = function
  | [] -> LTrue
  | [ x ] -> x
  | x :: xs -> LAnd (x, ltl_and xs)

let rec ltl_or = function
  | [] -> LFalse
  | [ x ] -> x
  | x :: xs -> LOr (x, ltl_or xs)

let rec hexpr_and = function
  | [] -> Kx_core_syntax_builders.mk_hbool true
  | [ x ] -> x
  | x :: xs -> Kx_core_syntax_builders.mk_hand x (hexpr_and xs)

let rec hexpr_or = function
  | [] -> Kx_core_syntax_builders.mk_hbool false
  | [ x ] -> x
  | x :: xs -> Kx_core_syntax_builders.mk_hor x (hexpr_or xs)

let expand_ltl_quantifier ~universal param domain body =
  domain_members domain
  |> List.map (fun value -> subst_ltl_index ~param ~value body)
  |> if universal then ltl_and else ltl_or

let expand_fo_quantifier ~universal param domain body =
  domain_members domain
  |> List.map (fun value -> subst_hexpr_index ~param ~value body)
  |> if universal then hexpr_and else hexpr_or

let expand_stmt_quantifier param domain body =
  domain_members domain
  |> List.concat_map (fun value -> List.map (subst_stmt_index ~param ~value) body)

let resolve_init_state ~(inline_init:ident option) : ident =
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

let expand_history_alias (alias:string) (arg:ident) : hexpr =
  match Hashtbl.find_opt history_aliases alias with
  | Some (_param, k) -> Kx_core_syntax_builders.mk_hpre_k arg k
  | None -> (
      match implicit_history_alias_k alias with
      | Some k -> Kx_core_syntax_builders.mk_hpre_k arg k
      | None -> failwith (Printf.sprintf "unknown history alias '%s'" alias))

let is_reserved_history_alias_name (id:string) : bool =
  match implicit_history_alias_k id with Some _ -> true | None -> false

let forbid_reserved_identifier ~(context:string) (id:string) : unit =
  if is_reserved_history_alias_name id then
    failwith
      (Printf.sprintf
         "identifier '%s' is reserved for implicit history aliases (context: %s)" id context)

let hvar_indexed base idx = Kx_core_syntax_builders.mk_hvar (indexed_ident base idx)
let hctor ctor = Kx_core_syntax_builders.mk_hvar ctor

let l_atom lhs rel rhs = LAtom (lhs, rel, rhs)
let l_eq lhs rhs = l_atom lhs REq rhs
let l_neq lhs rhs = l_atom lhs RNeq rhs

let rec l_and = function
  | [] -> LTrue
  | [ x ] -> x
  | x :: xs -> LAnd (x, l_and xs)

let maintained_until trigger invariant release =
  LG (LImp (trigger, LX (LW (invariant, release))))

let route_state route = hvar_indexed "routeState" route
let route_locked route = l_eq (route_state route) (hctor "Locked")
let route_released route = l_eq (route_state route) (hctor "Idle")
let while_route_locked route invariant =
  maintained_until (route_locked route) invariant (route_released route)

let topology_generated_guarantees (entries : topology_entry list) : ltl list =
  let routes =
    entries
    |> List.filter_map (function
         | TRoute r -> Some r
         | TConflict _ | TRouteSignal _ -> None)
  in
  let conflicts =
    entries
    |> List.filter_map (function
         | TConflict (a, b) -> Some (a, b)
         | TRoute _ | TRouteSignal _ -> None)
  in
  let signals =
    entries
    |> List.filter_map (function
         | TRouteSignal (route, signal) -> Some (route, signal)
         | TRoute _ | TConflict _ -> None)
  in
  let conflict_peers route =
    conflicts
    |> List.filter_map (fun (a, b) ->
           if String.equal route a then Some b
           else if String.equal route b then Some a
           else None)
  in
  let reserved route = l_eq (hvar_indexed "reserved" route) (Kx_core_syntax_builders.mk_hbool true) in
  let route_signal route = Option.value ~default:route (List.assoc_opt route signals) in
  let signal_color route color = l_eq (hvar_indexed "signal" (route_signal route)) (hctor color) in
  let track_clear track = l_eq (hvar_indexed "occupied" track) (Kx_core_syntax_builders.mk_hbool false) in
  let point_fixed point pos = l_eq (hvar_indexed "pointPosition" point) (hctor pos) in
  let locked_route_guarantee ({ route; points; _ } : topology_route) =
    let conflict_clauses =
      conflict_peers route
      |> List.map (fun peer -> l_neq (route_state peer) (hctor "Locked"))
    in
    let point_clauses = List.map (fun (point, pos) -> point_fixed point pos) points in
    while_route_locked route (l_and (reserved route :: conflict_clauses @ point_clauses))
  in
  let no_green_occupied_guarantee ({ route; tracks; _ } : topology_route) =
    LG (LImp (signal_color route "Green", l_and (List.map track_clear tracks)))
  in
  List.concat_map
    (fun route ->
      [
        locked_route_guarantee route;
        no_green_occupied_guarantee route;
      ])
    routes
%}

%token TYPE DOMAIN PREDICATE
%token NODE RETURNS LOCALS STATES INIT TRANS END
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

%start <Kx_ast.program> program
%start <(string * Kx_loc.loc option) list * Kx_core_syntax.enum_decl list * Kx_ast.program> source_file

%type <Kx_core_syntax.ltl list> topology_block
%type <Kx_topology_syntax.topology_entry list> topology_entries
%type <Kx_topology_syntax.topology_entry> topology_entry
%type <(Kx_core_syntax.ident * Kx_core_syntax.ident) list> topology_requires_opt point_requirements
%type <Kx_core_syntax.ident * Kx_core_syntax.ident> point_requirement

%%

source_file:
  | frontend_scope_start imports_opt frontend_decls_opt nodes EOF { ($2, $3, $4) }

program:
  | frontend_scope_start imports_opt frontend_decls_opt nodes EOF { $4 }

frontend_scope_start:
  | /* empty */ { reset_frontend_tables () }

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
  | frontend_decl frontend_decls { $1 @ $2 }
  | frontend_decl { $1 }

frontend_decl:
  | type_decl { [$1] }
  | domain_decl { [] }
  | predicate_decl { [] }

type_decl:
  | TYPE IDENT EQ enum_ctor_list SEMI
      {
        let () = forbid_reserved_identifier ~context:"enum type" $2 in
        List.iter (fun name -> forbid_reserved_identifier ~context:"enum constructor" name) $4;
        register_domain ~name:$2 ~members:$4;
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
        register_domain ~name:$2 ~members:$4
      }

predicate_decl:
  | PREDICATE IDENT LPAREN pred_params_opt RPAREN EQ fo_formula SEMI
      {
        let () = forbid_reserved_identifier ~context:"predicate name" $2 in
        List.iter (fun name -> forbid_reserved_identifier ~context:"predicate parameter" name) $4;
        register_predicate ~name:$2 ~params:$4 ~body:$7
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
    Kx_ast_builders.mk_node
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
      { n with specification = { n.specification with spec_invariants_state_rel = $18 } }
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
      List.iter (fun name -> forbid_reserved_identifier ~context:"parameter" name) $1;
      List.map (fun name -> {vname=name; vty=$3}) $1
    }

param_name:
  | IDENT { [$1] }
  | IDENT LBRACK decl_index_choices RBRACK
      { List.map (indexed_ident_many $1) $3 }

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
  | topology_block node_contracts
      {
        let (a, g) = $2 in
        (a, $1 @ g)
      }
  | topology_block
      {
        ([], $1)
      }
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

topology_block:
  | TOPOLOGY topology_entries END { topology_generated_guarantees $2 }

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
      List.iter (fun name -> forbid_reserved_identifier ~context:"variable declaration" name) $1;
      List.map (fun name -> {vname=name; vty=$3}) $1
    }

decl_names:
  | decl_name COMMA decl_names { $1 @ $3 }
  | decl_name { $1 }

decl_name:
  | IDENT { [$1] }
  | IDENT LBRACK decl_index_choices RBRACK
      { List.map (indexed_ident_many $1) $3 }

decl_index_choices:
  | decl_index_product COMMA decl_index_choices { $1 @ $3 }
  | decl_index_product { $1 }

decl_index_product:
  | decl_index_atom STAR decl_index_product { cartesian_concat $1 $3 }
  | decl_index_atom { $1 }

decl_index_atom:
  | IDENT { List.map (fun name -> [name]) (expand_domain_or_single $1) }

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
          Kx_ast_builders.mk_transition
            ~src:$2
            ~dst
            ~guard
            ~body)
        $4
    }
  | IDENT COLON to_transitions {
      List.map
        (fun (dst, guard, body) ->
          Kx_ast_builders.mk_transition
            ~src:$1
            ~dst
            ~guard
            ~body)
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
        Kx_ast_builders.mk_transition
          ~src:$2
          ~dst:$4
          ~guard:$5
          ~body:$7
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
  | FOR IDENT IN IDENT LBRACE stmt_list_opt RBRACE
      { expand_stmt_quantifier $2 $4 $6 }

stmt:
  | indexed_ref ASSIGN expr { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (SAssign($1,$3)) }
  | IF expr THEN stmt_list_opt ELSE stmt_list_opt END { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 7) (SIf($2,$4,$6)) }
  | SKIP { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) SSkip }
  | CALL IDENT LPAREN expr_list_opt RPAREN RETURNS LPAREN id_list_opt RPAREN
      { mk_stmt_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 9) (SCall($2, $4, $8)) }

indexed_ref:
  | IDENT { $1 }
  | IDENT LBRACK ident_list RBRACK { indexed_ident_many $1 $3 }

(* arithmetic expressions without booleans *)
arith_atom:
  | INT { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (ELitInt $1) }
  | indexed_ref { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (EVar $1) }
  | LPAREN arith RPAREN { $2 }

arith_unary:
  | MINUS arith_unary { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (EUn(Neg,$2)) }
  | arith_atom { $1 }

arith_mul:
  | arith_mul STAR arith_unary { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (EBin(Mul,$1,$3)) }
  | arith_mul SLASH arith_unary { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (EBin(Div,$1,$3)) }
  | arith_unary { $1 }

arith:
  | arith PLUS arith_mul { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (EBin(Add,$1,$3)) }
  | arith MINUS arith_mul { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (EBin(Sub,$1,$3)) }
  | arith_mul { $1 }


cmp_atom:
  | arith %prec IEXPR_ARITH { $1 }
  | TRUE { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (ELitBool true) }
  | FALSE { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (ELitBool false) }

expr_atom:
  | LPAREN expr RPAREN { $2 }
  | IDENT LPAREN id_list_opt RPAREN { expr_of_fo (expand_predicate $1 $3) }
  | cmp_atom EQ cmp_atom { Kx_core_syntax_builders.mk_expr (ECmp(REq, $1, $3)) }
  | cmp_atom NEQ cmp_atom { Kx_core_syntax_builders.mk_expr (ECmp(RNeq, $1, $3)) }
  | cmp_atom LT cmp_atom { Kx_core_syntax_builders.mk_expr (ECmp(RLt, $1, $3)) }
  | cmp_atom LE cmp_atom { Kx_core_syntax_builders.mk_expr (ECmp(RLe, $1, $3)) }
  | cmp_atom GT cmp_atom { Kx_core_syntax_builders.mk_expr (ECmp(RGt, $1, $3)) }
  | cmp_atom GE cmp_atom { Kx_core_syntax_builders.mk_expr (ECmp(RGe, $1, $3)) }
  | cmp_atom { $1 }

expr_not:
  | NOT expr_not { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (EUn(Not,$2)) }
  | expr_atom { $1 }

expr_and:
  | expr_and AND expr_not { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (EBin(And,$1,$3)) }
  | expr_not { $1 }

expr_or:
  | expr_or OR expr_and { mk_expr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (EBin(Or,$1,$3)) }
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
  | INT { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (HLitInt $1) }
  | TRUE { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (HLitBool true) }
  | FALSE { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (HLitBool false) }
  | IDENT IDENT { expand_history_alias $1 $2 }
  | indexed_ref { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (HVar $1) }
  | PRE LPAREN IDENT RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 4) (HPreK ($3, 1))
    }
  | PREK LPAREN IDENT COMMA INT RPAREN {
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 6) (HPreK ($3, $5))
    }
  | LBRACE expr RBRACE { Kx_core_syntax_builders.hexpr_of_expr $2 }
  | LPAREN hexpr RPAREN { $2 }

h_unary:
  | MINUS h_unary { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (HUn (Neg, $2)) }
  | h_atom { $1 }

h_mul:
  | h_mul STAR h_unary { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HBin (Mul, $1, $3)) }
  | h_mul SLASH h_unary { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HBin (Div, $1, $3)) }
  | h_unary { $1 }

h_arith:
  | h_arith PLUS h_mul { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HBin (Add, $1, $3)) }
  | h_arith MINUS h_mul { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HBin (Sub, $1, $3)) }
  | h_mul { $1 }

hexpr:
  | h_arith { $1 }

ltl_atom:
  | hexpr relop hexpr { LAtom($1,$2,$3) }
  | IDENT LPAREN id_list_opt RPAREN { ltl_of_fo (expand_predicate $1 $3) }
  | FORALL IDENT IN IDENT DOT ltl
      { expand_ltl_quantifier ~universal:true $2 $4 $6 }
  | EXISTS IDENT IN IDENT DOT ltl
      { expand_ltl_quantifier ~universal:false $2 $4 $6 }
  | MAINTAINEDUNTIL LPAREN ltl COMMA ltl COMMA ltl RPAREN
      { LG (LImp ($3, LX (LW ($5, $7)))) }
  | WHILEROUTELOCKED LPAREN IDENT COMMA ltl RPAREN
      {
        let () = forbid_reserved_identifier ~context:"whileRouteLocked route" $3 in
        while_route_locked $3 $5
      }
  | LPAREN ltl RPAREN { $2 }

fo_leaf:
  | hexpr relop hexpr { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HCmp($2,$1,$3)) }
  | IDENT LPAREN id_list_opt RPAREN { expand_predicate $1 $3 }
  | FORALL IDENT IN IDENT DOT fo_formula
      { expand_fo_quantifier ~universal:true $2 $4 $6 }
  | EXISTS IDENT IN IDENT DOT fo_formula
      { expand_fo_quantifier ~universal:false $2 $4 $6 }
  | LPAREN fo_formula RPAREN { $2 }

fo_un:
  | NOT fo_un { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 2) (HUn(Not,$2)) }
  | fo_leaf { $1 }

fo_and:
  | fo_and AND fo_un { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HBin(And,$1,$3)) }
  | fo_un { $1 }

fo_or:
  | fo_or OR fo_and { mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HBin(Or,$1,$3)) }
  | fo_and { $1 }

fo_formula:
  | fo_imp { $1 }

fo_imp:
  | fo_or IMPL fo_imp {
      let not_lhs = mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 1) (HUn(Not,$1)) in
      mk_hexpr_loc (Parsing.rhs_start_pos 1) (Parsing.rhs_end_pos 3) (HBin(Or, not_lhs, $3))
    }
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
