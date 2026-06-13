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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Kx_surface_syntax
open Kx_core_syntax

module B = Kx_core_syntax_builders
module S = Kx_surface_syntax

type source = {
  imports : S.import_decl list;
  type_decls : enum_decl list;
  function_decls : pure_function_decl list;
  nodes : Kx_ast.program;
}

type env = {
  domains : (ident * ident list) list;
  functions : (ident * (vdecl list * ty)) list;
  predicates : (ident * S.predicate_decl) list;
  actions : (ident * S.action_decl) list;
  history_aliases : (ident * (ident * int)) list;
}

let empty_env =
  { domains = []; functions = []; predicates = []; actions = []; history_aliases = [] }

let indexed_ident_many (base : ident) (idxs : ident list) : ident =
  String.concat "_" (base :: idxs)

let indexed_ref_name (r : S.indexed_ref) : ident =
  indexed_ident_many r.ref_base r.ref_indices

let add_unique_assoc what key value assoc =
  if List.mem_assoc key assoc then failwith (Printf.sprintf "duplicate %s '%s'" what key)
  else (key, value) :: assoc

let add_domain env name members =
  if members = [] then failwith (Printf.sprintf "finite domain '%s' has no members" name);
  { env with domains = add_unique_assoc "finite domain" name members env.domains }

let domain_members env name =
  match List.assoc_opt name env.domains with
  | Some members -> members
  | None -> failwith (Printf.sprintf "unknown finite domain '%s'" name)

let expand_domain_or_single env name =
  match List.assoc_opt name env.domains with Some members -> members | None -> [ name ]

let cartesian_concat left right =
  List.concat_map (fun xs -> List.map (fun ys -> xs @ ys) right) left

let expand_index_product env atoms =
  List.fold_right
    (fun atom acc ->
      let choices = List.map (fun name -> [ name ]) (expand_domain_or_single env atom) in
      cartesian_concat choices acc)
    atoms [ [] ]

let expand_index_choices env choices =
  List.concat_map (expand_index_product env) choices

let lower_raw_vdecl env (raw : S.raw_vdecl) : vdecl list =
  match raw.raw_indices with
  | None -> [ { vname = raw.raw_vname; vty = raw.raw_vty } ]
  | Some choices ->
      expand_index_choices env choices
      |> List.map (fun idxs -> { vname = indexed_ident_many raw.raw_vname idxs; vty = raw.raw_vty })

let lower_raw_vdecls env raws = List.concat_map (lower_raw_vdecl env) raws

let subst_ident ~(param : ident) ~(value : ident) id =
  if String.equal id param then value else id

let subst_ref ~(param : ident) ~(value : ident) (r : S.indexed_ref) : S.indexed_ref =
  {
    S.ref_base = subst_ident ~param ~value r.ref_base;
    ref_indices = List.map (subst_ident ~param ~value) r.ref_indices;
  }

let rec subst_expr ~(param : ident) ~(value : ident) (e : S.expr) : S.expr =
  let sexpr =
    match e.sexpr with
    | SELitInt _ | SELitBool _ -> e.sexpr
    | SEVar r -> SEVar (subst_ref ~param ~value r)
    | SECall (callee, args) -> SECall (callee, List.map (subst_expr ~param ~value) args)
    | SEBin (op, a, b) -> SEBin (op, subst_expr ~param ~value a, subst_expr ~param ~value b)
    | SECmp (op, a, b) -> SECmp (op, subst_expr ~param ~value a, subst_expr ~param ~value b)
    | SEUn (op, inner) -> SEUn (op, subst_expr ~param ~value inner)
  in
  { e with sexpr }

let rec subst_hexpr ~(param : ident) ~(value : ident) (h : S.hexpr) : S.hexpr =
  let shexpr =
    match h.shexpr with
    | SHLitInt _ | SHLitBool _ -> h.shexpr
    | SHVar r -> SHVar (subst_ref ~param ~value r)
    | SHPreK (r, k) -> SHPreK (subst_ref ~param ~value r, k)
    | SHHistoryAlias (alias, r) -> SHHistoryAlias (alias, subst_ref ~param ~value r)
    | SHCall (callee, args) -> SHCall (callee, List.map (subst_ident ~param ~value) args)
    | SHExpr e -> SHExpr (subst_expr ~param ~value e)
    | SHBin (op, a, b) ->
        SHBin (op, subst_hexpr ~param ~value a, subst_hexpr ~param ~value b)
    | SHCmp (op, a, b) ->
        SHCmp (op, subst_hexpr ~param ~value a, subst_hexpr ~param ~value b)
    | SHUn (op, inner) -> SHUn (op, subst_hexpr ~param ~value inner)
    | SHForall (bound, domain, body) when String.equal bound param ->
        SHForall (bound, domain, body)
    | SHExists (bound, domain, body) when String.equal bound param ->
        SHExists (bound, domain, body)
    | SHForall (bound, domain, body) -> SHForall (bound, domain, subst_hexpr ~param ~value body)
    | SHExists (bound, domain, body) -> SHExists (bound, domain, subst_hexpr ~param ~value body)
  in
  { h with shexpr }

let rec subst_ltl ~(param : ident) ~(value : ident) (f : S.ltl) : S.ltl =
  match f with
  | SLTrue | SLFalse -> f
  | SLAtom (a, op, b) ->
      SLAtom (subst_hexpr ~param ~value a, op, subst_hexpr ~param ~value b)
  | SLFo h -> SLFo (subst_hexpr ~param ~value h)
  | SLNot inner -> SLNot (subst_ltl ~param ~value inner)
  | SLAnd (a, b) -> SLAnd (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLOr (a, b) -> SLOr (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLImp (a, b) -> SLImp (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLX inner -> SLX (subst_ltl ~param ~value inner)
  | SLG inner -> SLG (subst_ltl ~param ~value inner)
  | SLW (a, b) -> SLW (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLForall (bound, domain, body) when String.equal bound param -> SLForall (bound, domain, body)
  | SLExists (bound, domain, body) when String.equal bound param -> SLExists (bound, domain, body)
  | SLForall (bound, domain, body) -> SLForall (bound, domain, subst_ltl ~param ~value body)
  | SLExists (bound, domain, body) -> SLExists (bound, domain, subst_ltl ~param ~value body)
  | SLMaintainedUntil (trigger, invariant, release) ->
      SLMaintainedUntil
        ( subst_ltl ~param ~value trigger,
          subst_ltl ~param ~value invariant,
          subst_ltl ~param ~value release )
  | SLWhileRouteLocked (route, invariant) ->
      SLWhileRouteLocked (subst_ident ~param ~value route, subst_ltl ~param ~value invariant)

let rec subst_stmt ~(param : ident) ~(value : ident) (s : S.stmt) : S.stmt =
  let sstmt =
    match s.sstmt with
    | SSAssign (lhs, rhs) -> SSAssign (subst_ref ~param ~value lhs, subst_expr ~param ~value rhs)
    | SSIf (cond, t, e) ->
        SSIf
          ( subst_expr ~param ~value cond,
            List.map (subst_stmt ~param ~value) t,
            List.map (subst_stmt ~param ~value) e )
    | SSMatch (scrutinee, branches, dflt) ->
        SSMatch
          ( subst_expr ~param ~value scrutinee,
            List.map
              (fun (ctor, body) -> (ctor, List.map (subst_stmt ~param ~value) body))
              branches,
            List.map (subst_stmt ~param ~value) dflt )
    | SSSkip -> SSSkip
    | SSCall (callee, args, outs) ->
        SSCall (callee, List.map (subst_expr ~param ~value) args, List.map (subst_ident ~param ~value) outs)
    | SSActionCall (callee, args) -> SSActionCall (callee, List.map (subst_ident ~param ~value) args)
    | SSFor (bound, domain, body) when String.equal bound param -> SSFor (bound, domain, body)
    | SSFor (bound, domain, body) -> SSFor (bound, domain, List.map (subst_stmt ~param ~value) body)
  in
  { s with sstmt }

let rec ltl_of_fo (h : hexpr) : ltl =
  match h.hexpr with
  | HLitBool true -> LTrue
  | HLitBool false -> LFalse
  | HUn (Not, inner) -> LNot (ltl_of_fo inner)
  | HBin (And, a, b) -> LAnd (ltl_of_fo a, ltl_of_fo b)
  | HBin (Or, a, b) -> LOr (ltl_of_fo a, ltl_of_fo b)
  | HCmp (op, a, b) -> LAtom (a, op, b)
  | _ -> LAtom (h, REq, B.mk_hbool true)

let rec expr_of_fo (h : hexpr) : expr =
  let expr =
    match h.hexpr with
    | HLitInt n -> ELitInt n
    | HLitBool b -> ELitBool b
    | HVar id -> EVar id
    | HPreK _ -> failwith "historical predicate cannot be used in executable expressions"
    | HPred _ -> failwith "unexpanded predicate cannot be used in executable expressions"
    | HFunCall (fn, args) -> EFunCall (fn, List.map expr_of_fo args)
    | HBin (op, a, b) -> EBin (op, expr_of_fo a, expr_of_fo b)
    | HCmp (op, a, b) -> ECmp (op, expr_of_fo a, expr_of_fo b)
    | HUn (op, inner) -> EUn (op, expr_of_fo inner)
  in
  { expr; loc = h.loc }

let rec core_ltl_and = function
  | [] -> LTrue
  | [ x ] -> x
  | x :: xs -> LAnd (x, core_ltl_and xs)

let rec core_ltl_or = function
  | [] -> LFalse
  | [ x ] -> x
  | x :: xs -> LOr (x, core_ltl_or xs)

let rec core_hexpr_and = function
  | [] -> B.mk_hbool true
  | [ x ] -> x
  | x :: xs -> B.mk_hand x (core_hexpr_and xs)

let rec core_hexpr_or = function
  | [] -> B.mk_hbool false
  | [ x ] -> x
  | x :: xs -> B.mk_hor x (core_hexpr_or xs)

let function_sig env name = List.assoc_opt name env.functions

let is_bool_function env name =
  match function_sig env name with Some (_, TBool) -> true | Some _ | None -> false

let ident_args_of_exprs ~(context : string) (args : S.expr list) : ident list =
  List.map
    (fun arg ->
      match arg.sexpr with
      | SEVar { ref_base; ref_indices = [] } -> ref_base
      | _ -> failwith (Printf.sprintf "%s expects identifier arguments" context))
    args

let implicit_history_alias_k (alias : string) : int option =
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

let expand_history_alias env alias arg =
  match List.assoc_opt alias env.history_aliases with
  | Some (_param, k) -> B.mk_hpre_k arg k
  | None -> (
      match implicit_history_alias_k alias with
      | Some k -> B.mk_hpre_k arg k
      | None -> failwith (Printf.sprintf "unknown history alias '%s'" alias))

let rec lower_expr env (e : S.expr) : expr =
  let expr =
    match e.sexpr with
    | SELitInt n -> ELitInt n
    | SELitBool b -> ELitBool b
    | SEVar r -> EVar (indexed_ref_name r)
    | SECall (callee, args) -> (
        match function_sig env callee with
        | Some _ -> EFunCall (callee, List.map (lower_expr env) args)
        | None ->
            let args =
              ident_args_of_exprs ~context:("predicate '" ^ callee ^ "'") args
            in
            (expr_of_fo (expand_predicate env [] callee args)).expr)
    | SEBin (op, a, b) -> EBin (op, lower_expr env a, lower_expr env b)
    | SECmp (op, a, b) -> ECmp (op, lower_expr env a, lower_expr env b)
    | SEUn (op, inner) -> EUn (op, lower_expr env inner)
  in
  { expr; loc = e.loc }

and lower_hexpr env stack (h : S.hexpr) : hexpr =
  let mk desc = B.mk_hexpr ?loc:h.hloc desc in
  match h.shexpr with
  | SHLitInt n -> mk (HLitInt n)
  | SHLitBool b -> mk (HLitBool b)
  | SHVar r -> mk (HVar (indexed_ref_name r))
  | SHPreK (r, k) -> mk (HPreK (indexed_ref_name r, k))
  | SHHistoryAlias (alias, r) -> expand_history_alias env alias (indexed_ref_name r)
  | SHCall (callee, args) ->
      if is_bool_function env callee then
        mk (HFunCall (callee, List.map B.mk_hvar args))
      else expand_predicate env stack callee args
  | SHExpr e -> B.hexpr_of_expr (lower_expr env e)
  | SHBin (op, a, b) -> mk (HBin (op, lower_hexpr env stack a, lower_hexpr env stack b))
  | SHCmp (op, a, b) -> mk (HCmp (op, lower_hexpr env stack a, lower_hexpr env stack b))
  | SHUn (op, inner) -> mk (HUn (op, lower_hexpr env stack inner))
  | SHForall (param, domain, body) ->
      domain_members env domain
      |> List.map (fun value -> lower_hexpr env stack (subst_hexpr ~param ~value body))
      |> core_hexpr_and
  | SHExists (param, domain, body) ->
      domain_members env domain
      |> List.map (fun value -> lower_hexpr env stack (subst_hexpr ~param ~value body))
      |> core_hexpr_or

and expand_predicate env stack name args =
  match List.assoc_opt name env.predicates with
  | None -> failwith (Printf.sprintf "unknown predicate '%s'" name)
  | Some pred ->
      if List.mem name stack then
        failwith (Printf.sprintf "cyclic predicate expansion involving '%s'" name);
      if List.length pred.predicate_params <> List.length args then
        failwith
          (Printf.sprintf "predicate '%s' expects %d arguments but got %d" name
             (List.length pred.predicate_params) (List.length args));
      let body =
        List.fold_left2
          (fun acc param value -> subst_hexpr ~param ~value acc)
          pred.predicate_body pred.predicate_params args
      in
      lower_hexpr env (name :: stack) body

let rec lower_ltl env (f : S.ltl) : ltl =
  match f with
  | SLTrue -> LTrue
  | SLFalse -> LFalse
  | SLAtom (a, op, b) -> LAtom (lower_hexpr env [] a, op, lower_hexpr env [] b)
  | SLFo h -> ltl_of_fo (lower_hexpr env [] h)
  | SLNot inner -> LNot (lower_ltl env inner)
  | SLAnd (a, b) -> LAnd (lower_ltl env a, lower_ltl env b)
  | SLOr (a, b) -> LOr (lower_ltl env a, lower_ltl env b)
  | SLImp (a, b) -> LImp (lower_ltl env a, lower_ltl env b)
  | SLX inner -> LX (lower_ltl env inner)
  | SLG inner -> LG (lower_ltl env inner)
  | SLW (a, b) -> LW (lower_ltl env a, lower_ltl env b)
  | SLForall (param, domain, body) ->
      domain_members env domain
      |> List.map (fun value -> lower_ltl env (subst_ltl ~param ~value body))
      |> core_ltl_and
  | SLExists (param, domain, body) ->
      domain_members env domain
      |> List.map (fun value -> lower_ltl env (subst_ltl ~param ~value body))
      |> core_ltl_or
  | SLMaintainedUntil (trigger, invariant, release) ->
      LG (LImp (lower_ltl env trigger, LX (LW (lower_ltl env invariant, lower_ltl env release))))
  | SLWhileRouteLocked (route, invariant) ->
      let route_state = B.mk_hvar (indexed_ident_many "routeState" [ route ]) in
      let locked = LAtom (route_state, REq, B.mk_hvar "Locked") in
      let released = LAtom (route_state, REq, B.mk_hvar "Idle") in
      LG (LImp (locked, LX (LW (lower_ltl env invariant, released))))

let rec lower_stmt env stack (s : S.stmt) : Kx_ast.stmt list =
  match s.sstmt with
  | SSAssign (lhs, rhs) ->
      [ Kx_ast_builders.mk_stmt ?loc:s.sloc (SAssign (indexed_ref_name lhs, lower_expr env rhs)) ]
  | SSIf (cond, then_branch, else_branch) ->
      [
        Kx_ast_builders.mk_stmt ?loc:s.sloc
          (SIf
             ( lower_expr env cond,
               lower_stmt_list env stack then_branch,
               lower_stmt_list env stack else_branch ));
      ]
  | SSMatch (scrutinee, branches, default_branch) ->
      [
        Kx_ast_builders.mk_stmt ?loc:s.sloc
          (SMatch
             ( lower_expr env scrutinee,
               List.map (fun (ctor, body) -> (ctor, lower_stmt_list env stack body)) branches,
               lower_stmt_list env stack default_branch ));
      ]
  | SSSkip -> [ Kx_ast_builders.mk_stmt ?loc:s.sloc SSkip ]
  | SSCall (callee, args, outs) ->
      [ Kx_ast_builders.mk_stmt ?loc:s.sloc (SCall (callee, List.map (lower_expr env) args, outs)) ]
  | SSActionCall (callee, args) -> expand_action env stack callee args
  | SSFor (param, domain, body) ->
      domain_members env domain
      |> List.concat_map (fun value ->
             body
             |> List.map (subst_stmt ~param ~value)
             |> lower_stmt_list env stack)

and lower_stmt_list env stack stmts =
  List.concat_map (lower_stmt env stack) stmts

and expand_action env stack name args =
  match List.assoc_opt name env.actions with
  | None -> failwith (Printf.sprintf "unknown action '%s'" name)
  | Some action ->
      if List.mem name stack then
        failwith (Printf.sprintf "cyclic action expansion involving '%s'" name);
      if List.length action.action_params <> List.length args then
        failwith
          (Printf.sprintf "action '%s' expects %d arguments but got %d" name
             (List.length action.action_params) (List.length args));
      let body =
        List.fold_left2
          (fun acc param value -> List.map (subst_stmt ~param ~value) acc)
          action.action_body action.action_params args
      in
      lower_stmt_list env (name :: stack) body

let hvar_indexed base idx = B.mk_hvar (indexed_ident_many base [ idx ])
let hctor ctor = B.mk_hvar ctor
let l_eq lhs rhs = LAtom (lhs, REq, rhs)
let l_neq lhs rhs = LAtom (lhs, RNeq, rhs)

let maintained_until trigger invariant release =
  LG (LImp (trigger, LX (LW (invariant, release))))

let while_route_locked route invariant =
  let route_state = hvar_indexed "routeState" route in
  let locked = l_eq route_state (hctor "Locked") in
  let released = l_eq route_state (hctor "Idle") in
  maintained_until locked invariant released

let topology_generated_guarantees (entries : Kx_topology_syntax.topology_entry list) : ltl list =
  let open Kx_topology_syntax in
  let routes =
    entries
    |> List.filter_map (function TRoute r -> Some r | TConflict _ | TRouteSignal _ -> None)
  in
  let conflicts =
    entries
    |> List.filter_map (function TConflict (a, b) -> Some (a, b) | TRoute _ | TRouteSignal _ -> None)
  in
  let signals =
    entries
    |> List.filter_map (function TRouteSignal (route, signal) -> Some (route, signal) | TRoute _ | TConflict _ -> None)
  in
  let conflict_peers route =
    conflicts
    |> List.filter_map (fun (a, b) ->
           if String.equal route a then Some b
           else if String.equal route b then Some a
           else None)
  in
  let route_state route = hvar_indexed "routeState" route in
  let reserved route = l_eq (hvar_indexed "reserved" route) (B.mk_hbool true) in
  let route_signal route = Option.value ~default:route (List.assoc_opt route signals) in
  let signal_color route color = l_eq (hvar_indexed "signal" (route_signal route)) (hctor color) in
  let track_clear track = l_eq (hvar_indexed "occupied" track) (B.mk_hbool false) in
  let point_fixed point pos = l_eq (hvar_indexed "pointPosition" point) (hctor pos) in
  let locked_route_guarantee ({ route; points; _ } : topology_route) =
    let conflict_clauses =
      conflict_peers route |> List.map (fun peer -> l_neq (route_state peer) (hctor "Locked"))
    in
    let point_clauses = List.map (fun (point, pos) -> point_fixed point pos) points in
    while_route_locked route (core_ltl_and (reserved route :: conflict_clauses @ point_clauses))
  in
  let no_green_occupied_guarantee ({ route; tracks; _ } : topology_route) =
    LG (LImp (signal_color route "Green", core_ltl_and (List.map track_clear tracks)))
  in
  List.concat_map
    (fun route -> [ locked_route_guarantee route; no_green_occupied_guarantee route ])
    routes

let lower_contracts env contracts =
  let assumes, guarantees =
    List.fold_left
      (fun (assumes, guarantees) -> function
        | S.SCRequires f -> (lower_ltl env f :: assumes, guarantees)
        | S.SCEnsures f -> (assumes, lower_ltl env f :: guarantees)
        | S.SCTopology entries ->
            (assumes, List.rev_append (topology_generated_guarantees entries) guarantees))
      ([], []) contracts
  in
  (List.rev assumes, List.rev guarantees)

let lower_transition env (t : S.transition) : Kx_ast.transition =
  Kx_ast_builders.mk_transition ~src:t.src ~dst:t.dst
    ~guard:(Option.map (lower_expr env) t.guard)
    ~body:(lower_stmt_list env [] t.body)

let validate_unique_named_decls kind get_name decls =
  let seen = Hashtbl.create 17 in
  List.iter
    (fun decl ->
      let name = get_name decl in
      match Hashtbl.find_opt seen name with
      | Some () -> failwith (Printf.sprintf "duplicate %s '%s'" kind name)
      | None -> Hashtbl.add seen name ())
    decls

let node_env base_env (n : S.node) =
  validate_unique_named_decls "predicate" (fun (p : S.predicate_decl) -> p.predicate_name) n.predicates;
  validate_unique_named_decls "action" (fun (a : S.action_decl) -> a.action_name) n.actions;
  validate_unique_named_decls "history alias" (fun (a : S.history_alias_decl) -> a.alias_name) n.history_aliases;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.functions then
        failwith
          (Printf.sprintf "predicate '%s' conflicts with a pure function of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.functions then
        failwith
          (Printf.sprintf "action '%s' conflicts with a pure function of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.exists (fun (p : S.predicate_decl) -> String.equal p.predicate_name a.action_name) n.predicates then
        failwith
          (Printf.sprintf "action '%s' conflicts with a predicate of the same name" a.action_name))
    n.actions;
  {
    base_env with
    predicates = List.map (fun p -> (p.S.predicate_name, p)) n.predicates;
    actions = List.map (fun a -> (a.S.action_name, a)) n.actions;
    history_aliases =
      List.map
        (fun a ->
          if a.S.alias_k < 1 then
            failwith
              (Printf.sprintf "history alias '%s' uses invalid k=%d (expected >= 1)" a.alias_name a.alias_k);
          if not (String.equal a.alias_param a.alias_rhs_param) then
            failwith
              (Printf.sprintf
                 "history alias '%s' is inconsistent: parameter is '%s' but rhs uses '%s'"
                 a.alias_name a.alias_param a.alias_rhs_param);
          (a.alias_name, (a.alias_param, a.alias_k)))
        n.history_aliases;
  }

let lower_node base_env (n : S.node) : Kx_ast.node =
  let env = node_env base_env n in
  let assumes, guarantees = lower_contracts env n.contracts in
  let node =
    Kx_ast_builders.mk_node ~nname:n.node_name ~inputs:(lower_raw_vdecls env n.inputs)
      ~outputs:(lower_raw_vdecls env n.outputs) ~assumes ~guarantees ~instances:n.instances
      ~locals:(lower_raw_vdecls env n.locals) ~ghosts:(lower_raw_vdecls env n.ghosts)
      ~states:n.state_decls.states ~init_state:n.state_decls.init_state
      ~trans:(List.map (lower_transition env) n.transitions)
  in
  {
    node with
    specification =
      {
        node.specification with
        spec_invariants_state_rel =
          List.map
            (fun (inv : S.state_invariant) ->
              { Kx_ast.state = inv.state; formula = lower_hexpr env [] inv.formula })
            n.state_invariants;
      };
  }

let lower_function_decl env (f : S.function_decl) : pure_function_decl =
  {
    function_name = f.function_name;
    function_params = lower_raw_vdecls env f.function_params;
    function_return = f.function_return;
    function_requires = List.map (lower_hexpr env []) f.function_requires;
    function_ensures = List.map (lower_hexpr env []) f.function_ensures;
    function_body = lower_expr env f.function_body;
  }

let elaborate_frontend_decl (env, type_decls, function_decls) = function
  | S.STypeDecl decl ->
      let env = add_domain env decl.enum_name decl.enum_constructors in
      (env, decl :: type_decls, function_decls)
  | S.SDomainDecl decl ->
      let env = add_domain env decl.domain_name decl.domain_members in
      (env, type_decls, function_decls)
  | S.SFunctionDecl f ->
      if List.mem_assoc f.function_name env.functions then
        failwith (Printf.sprintf "duplicate pure function '%s'" f.function_name);
      let lowered = lower_function_decl env f in
      let signature = (lowered.function_params, lowered.function_return) in
      let env = { env with functions = (lowered.function_name, signature) :: env.functions } in
      (env, type_decls, lowered :: function_decls)

let elaborate_source (source : S.source) : source =
  let env, type_decls, function_decls =
    List.fold_left elaborate_frontend_decl (empty_env, [], []) source.frontend_decls
  in
  {
    imports = source.imports;
    type_decls = List.rev type_decls;
    function_decls = List.rev function_decls;
    nodes = List.map (lower_node env) source.nodes;
  }
