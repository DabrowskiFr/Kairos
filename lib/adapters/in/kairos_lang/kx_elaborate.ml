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
  enum_sets : (ident * ident list) list;
  functions : (ident * (vdecl list * ty)) list;
  spec_defs : (ident * S.spec_def_decl) list;
  history_defs : (ident * S.history_def_decl) list;
  predicates : (ident * S.predicate_decl) list;
  actions : (ident * S.action_decl) list;
  history_aliases : (ident * (ident * int)) list;
}

let empty_env =
  {
    enum_sets = [];
    functions = [];
    spec_defs = [];
    history_defs = [];
    predicates = [];
    actions = [];
    history_aliases = [];
  }

type spec_context = {
  formula_params : (ident * S.ltl) list;
  hexpr_params : (ident * S.hexpr) list;
  nat_params : (ident * int) list;
  spec_stack : ident list;
}

let empty_spec_context =
  { formula_params = []; hexpr_params = []; nat_params = []; spec_stack = [] }

let indexed_ident_many (base : ident) (idxs : ident list) : ident =
  String.concat "_" (base :: idxs)

let indexed_ref_name (r : S.indexed_ref) : ident =
  indexed_ident_many r.ref_base r.ref_indices

let same_indexed_ref (a : S.indexed_ref) (b : S.indexed_ref) =
  String.equal a.ref_base b.ref_base && a.ref_indices = b.ref_indices

let generated_history_prefix = "__kairos_history_"

let generated_history_name def_name r =
  generated_history_prefix ^ def_name ^ "_" ^ indexed_ref_name r

let add_unique_assoc what key value assoc =
  if List.mem_assoc key assoc then failwith (Printf.sprintf "duplicate %s '%s'" what key)
  else (key, value) :: assoc

let add_enum_set env name members =
  if members = [] then failwith (Printf.sprintf "enum type '%s' has no constructors" name);
  { env with enum_sets = add_unique_assoc "enum type" name members env.enum_sets }

let enum_members env name =
  match List.assoc_opt name env.enum_sets with
  | Some members -> members
  | None -> failwith (Printf.sprintf "unknown enum type '%s'" name)

let expand_enum_or_single env name =
  match List.assoc_opt name env.enum_sets with Some members -> members | None -> [ name ]

let cartesian_concat left right =
  List.concat_map (fun xs -> List.map (fun ys -> xs @ ys) right) left

let expand_index_product env atoms =
  List.fold_right
    (fun atom acc ->
      let choices = List.map (fun name -> [ name ]) (expand_enum_or_single env atom) in
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

let nat_literal_of_ident id =
  match int_of_string_opt id with
  | Some n when n >= 0 -> Some n
  | _ -> None

let subst_ref ~(param : ident) ~(value : ident) (r : S.indexed_ref) : S.indexed_ref =
  {
    S.ref_base = subst_ident ~param ~value r.ref_base;
    ref_indices = List.map (subst_ident ~param ~value) r.ref_indices;
  }

let subst_nat_expr ~(param : ident) ~(value : ident) = function
  | SNNat _ as n -> n
  | SNVar id when String.equal id param -> (
      match nat_literal_of_ident value with Some n -> SNNat n | None -> SNVar value)
  | SNVar id -> SNVar id

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
    | SHPreK (r, k) -> SHPreK (subst_ref ~param ~value r, subst_nat_expr ~param ~value k)
    | SHPast (inner, k) ->
        SHPast (subst_hexpr ~param ~value inner, subst_nat_expr ~param ~value k)
    | SHHistoryCall (name, r) -> SHHistoryCall (name, subst_ref ~param ~value r)
    | SHHistoryAlias (alias, r) -> SHHistoryAlias (alias, subst_ref ~param ~value r)
    | SHCall (callee, args) -> SHCall (callee, List.map (subst_ident ~param ~value) args)
    | SHExpr e -> SHExpr (subst_expr ~param ~value e)
    | SHBin (op, a, b) ->
        SHBin (op, subst_hexpr ~param ~value a, subst_hexpr ~param ~value b)
    | SHCmp (op, a, b) ->
        SHCmp (op, subst_hexpr ~param ~value a, subst_hexpr ~param ~value b)
    | SHUn (op, inner) -> SHUn (op, subst_hexpr ~param ~value inner)
    | SHForall (bound, enum_name, body) when String.equal bound param ->
        SHForall (bound, enum_name, body)
    | SHExists (bound, enum_name, body) when String.equal bound param ->
        SHExists (bound, enum_name, body)
    | SHForall (bound, enum_name, body) -> SHForall (bound, enum_name, subst_hexpr ~param ~value body)
    | SHExists (bound, enum_name, body) -> SHExists (bound, enum_name, subst_hexpr ~param ~value body)
    | SHRangeForall (bound, lo, hi, body) when String.equal bound param ->
        SHRangeForall (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
    | SHRangeExists (bound, lo, hi, body) when String.equal bound param ->
        SHRangeExists (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
    | SHRangeForall (bound, lo, hi, body) ->
        SHRangeForall
          ( bound,
            subst_nat_expr ~param ~value lo,
            subst_nat_expr ~param ~value hi,
            subst_hexpr ~param ~value body )
    | SHRangeExists (bound, lo, hi, body) ->
        SHRangeExists
          ( bound,
            subst_nat_expr ~param ~value lo,
            subst_nat_expr ~param ~value hi,
            subst_hexpr ~param ~value body )
  in
  { h with shexpr }

let rec subst_spec_arg ~(param : ident) ~(value : ident) = function
  | SAFormula f -> SAFormula (subst_ltl ~param ~value f)
  | SAHExpr h -> SAHExpr (subst_hexpr ~param ~value h)

and subst_ltl ~(param : ident) ~(value : ident) (f : S.ltl) : S.ltl =
  match f with
  | SLTrue | SLFalse -> f
  | SLAtom (a, op, b) ->
      SLAtom (subst_hexpr ~param ~value a, op, subst_hexpr ~param ~value b)
  | SLFo h -> SLFo (subst_hexpr ~param ~value h)
  | SLFormulaParam id -> SLFormulaParam (subst_ident ~param ~value id)
  | SLCall (callee, args) -> SLCall (callee, List.map (subst_spec_arg ~param ~value) args)
  | SLNot inner -> SLNot (subst_ltl ~param ~value inner)
  | SLAnd (a, b) -> SLAnd (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLOr (a, b) -> SLOr (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLImp (a, b) -> SLImp (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLX inner -> SLX (subst_ltl ~param ~value inner)
  | SLG inner -> SLG (subst_ltl ~param ~value inner)
  | SLW (a, b) -> SLW (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLForall (bound, enum_name, body) when String.equal bound param -> SLForall (bound, enum_name, body)
  | SLExists (bound, enum_name, body) when String.equal bound param -> SLExists (bound, enum_name, body)
  | SLForall (bound, enum_name, body) -> SLForall (bound, enum_name, subst_ltl ~param ~value body)
  | SLExists (bound, enum_name, body) -> SLExists (bound, enum_name, subst_ltl ~param ~value body)
  | SLRangeForall (bound, lo, hi, body) when String.equal bound param ->
      SLRangeForall (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
  | SLRangeExists (bound, lo, hi, body) when String.equal bound param ->
      SLRangeExists (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
  | SLRangeForall (bound, lo, hi, body) ->
      SLRangeForall
        ( bound,
          subst_nat_expr ~param ~value lo,
          subst_nat_expr ~param ~value hi,
          subst_ltl ~param ~value body )
  | SLRangeExists (bound, lo, hi, body) ->
      SLRangeExists
        ( bound,
          subst_nat_expr ~param ~value lo,
          subst_nat_expr ~param ~value hi,
          subst_ltl ~param ~value body )

let rec subst_stmt ~(param : ident) ~(value : ident) (s : S.stmt) : S.stmt =
  let sstmt =
    match s.sstmt with
    | SSAssign (lhs, rhs) -> SSAssign (subst_ref ~param ~value lhs, subst_expr ~param ~value rhs)
    | SSIf (cond, t, e) ->
        SSIf
          ( subst_expr ~param ~value cond,
            List.map (subst_stmt ~param ~value) t,
            List.map (subst_stmt ~param ~value) e )
    | SSWhile (cond, invariants, variant, body) ->
        SSWhile
          ( subst_expr ~param ~value cond,
            List.map (subst_hexpr ~param ~value) invariants,
            Option.map (subst_expr ~param ~value) variant,
            List.map (subst_stmt ~param ~value) body )
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
    | SSFor (bound, enum_name, body) when String.equal bound param -> SSFor (bound, enum_name, body)
    | SSFor (bound, enum_name, body) -> SSFor (bound, enum_name, List.map (subst_stmt ~param ~value) body)
    | SSForRange (bound, lo, hi, body) when String.equal bound param ->
        SSForRange
          ( bound,
            subst_nat_expr ~param ~value lo,
            subst_nat_expr ~param ~value hi,
            body )
    | SSForRange (bound, lo, hi, body) ->
        SSForRange
          ( bound,
            subst_nat_expr ~param ~value lo,
            subst_nat_expr ~param ~value hi,
            List.map (subst_stmt ~param ~value) body )
  in
  { s with sstmt }

let rec subst_history_expr ~(param : ident) ~(value : ident) (h : S.history_expr) :
    S.history_expr =
  let shistory_expr =
    match h.shistory_expr with
    | SHValue formula -> SHValue (subst_hexpr ~param ~value formula)
    | SHIf (cond, then_value, else_value) ->
        SHIf
          ( subst_hexpr ~param ~value cond,
            subst_history_expr ~param ~value then_value,
            subst_history_expr ~param ~value else_value )
  in
  { h with shistory_expr }

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

let rec range_values lo hi =
  if lo > hi then [] else lo :: range_values (lo + 1) hi

let eval_nat ctx = function
  | SNNat n ->
      if n < 0 then failwith "natural number literal must be non-negative";
      n
  | SNVar id -> (
      match List.assoc_opt id ctx.nat_params with
      | Some n -> n
      | None -> failwith (Printf.sprintf "unknown Nat parameter '%s'" id))

let is_scalar_ref_named name (r : S.indexed_ref) =
  String.equal r.ref_base name && r.ref_indices = []

let ref_with_nat_params ctx (r : S.indexed_ref) : S.indexed_ref =
  let resolve_index id =
    match List.assoc_opt id ctx.nat_params with
    | Some n -> string_of_int n
    | None -> id
  in
  { r with ref_indices = List.map resolve_index r.ref_indices }

let scalar_nat_value ctx (r : S.indexed_ref) : int option =
  match r.ref_indices with
  | [] -> (
      match List.assoc_opt r.ref_base ctx.nat_params with
      | Some n -> Some n
      | None -> nat_literal_of_ident r.ref_base)
  | _ -> None

let resolve_history_source_ref ctx (r : S.indexed_ref) =
  let r = ref_with_nat_params ctx r in
  match (r.ref_indices, List.assoc_opt r.ref_base ctx.hexpr_params) with
  | [], Some { shexpr = SHVar actual; _ } -> actual
  | [], Some _ ->
      failwith
        (Printf.sprintf
           "historical expression operator expects variable argument '%s' to be a variable reference"
           r.ref_base)
  | _ -> r

let rec shift_hexpr_past k (h : hexpr) : hexpr =
  if k < 0 then failwith "past offset must be non-negative";
  if k = 0 then h
  else
    let mk desc = B.mk_hexpr ?loc:h.loc desc in
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar v -> mk (HPreK (v, k))
    | HPreK (v, j) -> mk (HPreK (v, j + k))
    | HPred (name, args) -> mk (HPred (name, List.map (shift_hexpr_past k) args))
    | HFunCall (name, args) -> mk (HFunCall (name, List.map (shift_hexpr_past k) args))
    | HBin (op, a, b) -> mk (HBin (op, shift_hexpr_past k a, shift_hexpr_past k b))
    | HCmp (op, a, b) -> mk (HCmp (op, shift_hexpr_past k a, shift_hexpr_past k b))
    | HUn (op, inner) -> mk (HUn (op, shift_hexpr_past k inner))

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

let rec ident_arg_of_surface_hexpr ctx (h : S.hexpr) : ident =
  match h.shexpr with
  | SHVar ({ ref_base; ref_indices = [] } as r) -> (
      match List.assoc_opt ref_base ctx.hexpr_params with
      | Some actual -> ident_arg_of_surface_hexpr ctx actual
      | None -> indexed_ref_name r)
  | _ -> failwith "predicate arguments must be identifiers"

let ident_arg_of_name ctx id =
  match List.assoc_opt id ctx.hexpr_params with
  | Some actual -> ident_arg_of_surface_hexpr ctx actual
  | None -> id

let spec_arg_as_ident ctx = function
  | SAHExpr h -> ident_arg_of_surface_hexpr ctx h
  | SAFormula _ -> failwith "predicate arguments must be identifiers"

let formula_arg_of_spec_arg _ctx = function
  | SAFormula f -> f
  | SAHExpr _ -> failwith "Formula parameter expects a formula argument"

let hexpr_arg_of_spec_arg ctx = function
  | SAHExpr ({ shexpr = SHVar { ref_base; ref_indices = [] }; _ }) as arg -> (
      match List.assoc_opt ref_base ctx.hexpr_params with
      | Some h -> h
      | None -> (
          match arg with SAHExpr h -> h | SAFormula _ -> assert false))
  | SAHExpr h -> h
  | SAFormula _ -> failwith "HExpr parameter expects a historical expression argument"

let nat_arg_of_spec_arg ctx = function
  | SAHExpr { shexpr = SHLitInt n; _ } ->
      if n < 0 then failwith "Nat parameter expects a non-negative integer";
      n
  | SAHExpr { shexpr = SHVar { ref_base; ref_indices = [] }; _ } -> eval_nat ctx (SNVar ref_base)
  | _ -> failwith "Nat parameter expects an integer literal or Nat parameter"

let rec lower_expr env (e : S.expr) : expr =
  let expr =
    match e.sexpr with
    | SELitInt n -> ELitInt n
    | SELitBool b -> ELitBool b
    | SEVar r when r.ref_indices = [] -> (
        match nat_literal_of_ident r.ref_base with
        | Some n -> ELitInt n
        | None -> EVar (indexed_ref_name r))
    | SEVar r -> EVar (indexed_ref_name r)
    | SECall (callee, args) -> (
        match function_sig env callee with
        | Some _ -> EFunCall (callee, List.map (lower_expr env) args)
        | None ->
            let args =
              ident_args_of_exprs ~context:("predicate '" ^ callee ^ "'") args
            in
            (expr_of_fo (expand_predicate env empty_spec_context [] callee args)).expr)
    | SEBin (op, a, b) -> EBin (op, lower_expr env a, lower_expr env b)
    | SECmp (op, a, b) -> ECmp (op, lower_expr env a, lower_expr env b)
    | SEUn (op, inner) -> EUn (op, lower_expr env inner)
  in
  { expr; loc = e.loc }

and lower_hexpr env ctx stack (h : S.hexpr) : hexpr =
  let mk desc = B.mk_hexpr ?loc:h.hloc desc in
  match h.shexpr with
  | SHLitInt n -> mk (HLitInt n)
  | SHLitBool b -> mk (HLitBool b)
  | SHVar r -> (
      match scalar_nat_value ctx r with
      | Some n -> mk (HLitInt n)
      | None ->
          let r = ref_with_nat_params ctx r in
          begin
            match r with
            | { ref_base; _ } when is_scalar_ref_named ref_base r -> (
                match List.assoc_opt ref_base ctx.hexpr_params with
                | Some { shexpr = SHVar actual; _ } when is_scalar_ref_named ref_base actual ->
                    mk (HVar (indexed_ref_name actual))
                | Some actual -> lower_hexpr env ctx stack actual
                | None -> mk (HVar (indexed_ref_name r)))
            | _ -> mk (HVar (indexed_ref_name r))
          end)
  | SHPreK (r, k) -> (
      let k = eval_nat ctx k in
      let r = ref_with_nat_params ctx r in
      match r with
      | { ref_base; _ } when is_scalar_ref_named ref_base r -> (
          match List.assoc_opt ref_base ctx.hexpr_params with
          | Some { shexpr = SHVar actual; _ } when is_scalar_ref_named ref_base actual ->
              mk (HVar (indexed_ref_name actual)) |> shift_hexpr_past k
          | Some actual -> lower_hexpr env ctx stack actual |> shift_hexpr_past k
          | None -> mk (HPreK (indexed_ref_name r, k)))
      | _ -> mk (HPreK (indexed_ref_name r, k)))
  | SHPast (inner, k) -> lower_hexpr env ctx stack inner |> shift_hexpr_past (eval_nat ctx k)
  | SHHistoryCall (name, r) ->
      let r = resolve_history_source_ref ctx r in
      if not (List.mem_assoc name env.history_defs) then
        failwith (Printf.sprintf "unknown history definition '%s'" name);
      mk (HVar (generated_history_name name r))
  | SHHistoryAlias (alias, r) -> expand_history_alias env alias (indexed_ref_name r)
  | SHCall (callee, args) ->
      let args = List.map (ident_arg_of_name ctx) args in
      if is_bool_function env callee then
        mk (HFunCall (callee, List.map B.mk_hvar args))
      else expand_predicate env ctx stack callee args
  | SHExpr e -> B.hexpr_of_expr (lower_expr env e)
  | SHBin (op, a, b) -> mk (HBin (op, lower_hexpr env ctx stack a, lower_hexpr env ctx stack b))
  | SHCmp (op, a, b) -> mk (HCmp (op, lower_hexpr env ctx stack a, lower_hexpr env ctx stack b))
  | SHUn (op, inner) -> mk (HUn (op, lower_hexpr env ctx stack inner))
  | SHForall (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value -> lower_hexpr env ctx stack (subst_hexpr ~param ~value body))
      |> core_hexpr_and
  | SHExists (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value -> lower_hexpr env ctx stack (subst_hexpr ~param ~value body))
      |> core_hexpr_or
  | SHRangeForall (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_hexpr env ctx stack body)
      |> core_hexpr_and
  | SHRangeExists (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_hexpr env ctx stack body)
      |> core_hexpr_or

and expand_predicate env ctx stack name args =
  (* Source predicates must be declared and are fully expanded here. Do not
     synthesize [HPred] for unknown names: that would silently move an
     undeclared frontend name into the trusted core pipeline. *)
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
      lower_hexpr env ctx (name :: stack) body

and bind_spec_param ctx (formal : S.spec_param) arg =
  match formal.spec_param_kind with
  | SPFormula ->
      { ctx with formula_params = (formal.spec_param_name, formula_arg_of_spec_arg ctx arg) :: ctx.formula_params }
  | SPHExpr ->
      { ctx with hexpr_params = (formal.spec_param_name, hexpr_arg_of_spec_arg ctx arg) :: ctx.hexpr_params }
  | SPNat ->
      { ctx with nat_params = (formal.spec_param_name, nat_arg_of_spec_arg ctx arg) :: ctx.nat_params }

and expand_spec_call env ctx name args =
  match List.assoc_opt name env.spec_defs with
  | Some def ->
      if List.mem name ctx.spec_stack then
        failwith (Printf.sprintf "cyclic spec definition expansion involving '%s'" name);
      if List.length def.spec_def_params <> List.length args then
        failwith
          (Printf.sprintf "spec definition '%s' expects %d arguments but got %d" name
             (List.length def.spec_def_params) (List.length args));
      let ctx =
        List.fold_left2 bind_spec_param
          { ctx with spec_stack = name :: ctx.spec_stack }
          def.spec_def_params args
      in
      lower_ltl env ctx def.spec_def_body
  | None ->
      let args = List.map (spec_arg_as_ident ctx) args in
      if is_bool_function env name then
        ltl_of_fo (B.mk_hexpr (HFunCall (name, List.map B.mk_hvar args)))
      else ltl_of_fo (expand_predicate env ctx [] name args)

and lower_ltl env ctx (f : S.ltl) : ltl =
  match f with
  | SLTrue -> LTrue
  | SLFalse -> LFalse
  | SLAtom (a, op, b) -> LAtom (lower_hexpr env ctx [] a, op, lower_hexpr env ctx [] b)
  | SLFo h -> ltl_of_fo (lower_hexpr env ctx [] h)
  | SLFormulaParam name -> (
      match List.assoc_opt name ctx.formula_params with
      | Some f -> lower_ltl env ctx f
      | None -> failwith (Printf.sprintf "unknown Formula parameter '%s'" name))
  | SLCall (name, args) -> expand_spec_call env ctx name args
  | SLNot inner -> LNot (lower_ltl env ctx inner)
  | SLAnd (a, b) -> LAnd (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLOr (a, b) -> LOr (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLImp (a, b) -> LImp (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLX inner -> LX (lower_ltl env ctx inner)
  | SLG inner -> LG (lower_ltl env ctx inner)
  | SLW (a, b) -> LW (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLForall (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value -> lower_ltl env ctx (subst_ltl ~param ~value body))
      |> core_ltl_and
  | SLExists (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value -> lower_ltl env ctx (subst_ltl ~param ~value body))
      |> core_ltl_or
  | SLRangeForall (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_ltl env ctx body)
      |> core_ltl_and
  | SLRangeExists (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_ltl env ctx body)
      |> core_ltl_or

let rec lower_contract_ltls env (f : S.ltl) : ltl list =
  match f with
  | SLAnd (a, b) -> lower_contract_ltls env a @ lower_contract_ltls env b
  | SLForall (param, enum_name, body) ->
      enum_members env enum_name
      |> List.concat_map (fun value -> lower_contract_ltls env (subst_ltl ~param ~value body))
  | SLRangeForall (param, lo, hi, body) ->
      range_values (eval_nat empty_spec_context lo) (eval_nat empty_spec_context hi)
      |> List.concat_map (fun value ->
             let ctx = { empty_spec_context with nat_params = [ (param, value) ] } in
             [ lower_ltl env ctx body ])
  | _ -> [ lower_ltl env empty_spec_context f ]

type generated_history = {
  hist_name : ident;
  hist_def : S.history_def_decl;
  hist_source : S.indexed_ref;
  hist_ty : ty;
  hist_self_pre_depth : int;
}

let generated_history_key def_name r =
  def_name ^ ":" ^ indexed_ref_name r

let generated_history_delay_name h idx =
  Printf.sprintf "%s__delay%d" h.hist_name idx

let generated_history_snapshot_name h idx =
  Printf.sprintf "%s__snap%d" h.hist_name idx

let generated_history_delay_count h =
  max 0 (h.hist_self_pre_depth - 1)

let generated_history_snapshot_count h =
  if generated_history_delay_count h = 0 then 0 else h.hist_self_pre_depth

let generated_history_delay_names h =
  List.init (generated_history_delay_count h) (fun i ->
      generated_history_delay_name h (i + 1))

let generated_history_snapshot_names h =
  List.init (generated_history_snapshot_count h) (fun i ->
      generated_history_snapshot_name h i)

let rec max_self_pre_depth_hexpr (self_name : ident) (h : S.hexpr) =
  match h.shexpr with
  | SHLitInt _ | SHLitBool _ | SHVar _ | SHHistoryAlias _ -> 0
  | SHPreK (r, k) ->
      if is_scalar_ref_named self_name r then
        match k with
        | SNNat n -> n
        | SNVar _ ->
            failwith "history definition update uses non-constant pre_k(self, k)"
      else 0
  | SHPast (inner, _) -> max_self_pre_depth_hexpr self_name inner
  | SHHistoryCall _ -> 0
  | SHCall _ -> 0
  | SHExpr _ -> 0
  | SHBin (_, a, b) | SHCmp (_, a, b) ->
      max (max_self_pre_depth_hexpr self_name a) (max_self_pre_depth_hexpr self_name b)
  | SHUn (_, inner) -> max_self_pre_depth_hexpr self_name inner
  | SHForall (_, _, body) | SHExists (_, _, body) -> max_self_pre_depth_hexpr self_name body
  | SHRangeForall (_, _, _, body) | SHRangeExists (_, _, _, body) ->
      max_self_pre_depth_hexpr self_name body

let rec max_self_pre_depth_history_expr (self_name : ident) (h : S.history_expr) =
  match h.shistory_expr with
  | SHValue formula -> max_self_pre_depth_hexpr self_name formula
  | SHIf (cond, then_value, else_value) ->
      max
        (max_self_pre_depth_hexpr self_name cond)
        (max
           (max_self_pre_depth_history_expr self_name then_value)
           (max_self_pre_depth_history_expr self_name else_value))

let validate_history_source_ref env (n : S.node) (r : S.indexed_ref) =
  let name = indexed_ref_name r in
  let vars = lower_raw_vdecls env (n.inputs @ n.outputs @ n.locals @ n.ghosts) in
  match List.find_opt (fun (v : vdecl) -> String.equal v.vname name) vars with
  | Some _ -> ()
  | None ->
      failwith
        (Printf.sprintf
           "historical expression source '%s' is not a node input, output, local, or declared ghost"
           name)

let add_generated_history env n def_name r acc =
  let key = generated_history_key def_name r in
  if
    List.exists
      (fun h -> String.equal (generated_history_key h.hist_def.S.history_def_name h.hist_source) key)
      acc
  then
    acc
  else
    match List.assoc_opt def_name env.history_defs with
    | None -> failwith (Printf.sprintf "unknown history definition '%s'" def_name)
    | Some hist_def ->
        validate_history_source_ref env n r;
        let hist_self_pre_depth =
          max_self_pre_depth_history_expr "self" hist_def.history_step
        in
        {
          hist_name = generated_history_name def_name r;
          hist_def;
          hist_source = r;
          hist_ty = hist_def.history_ty;
          hist_self_pre_depth;
        }
        :: acc

let rec collect_history_hexpr env n ctx stack acc (h : S.hexpr) =
  match h.shexpr with
  | SHLitInt _ | SHLitBool _ -> acc
  | SHVar ({ ref_base; _ } as r) when is_scalar_ref_named ref_base r -> (
      match List.assoc_opt ref_base ctx.hexpr_params with
      | Some { shexpr = SHVar actual; _ } when same_indexed_ref actual r -> acc
      | Some actual -> collect_history_hexpr env n ctx stack acc actual
      | None -> acc)
  | SHVar _ -> acc
  | SHPreK (({ ref_base; _ } as r), _) when is_scalar_ref_named ref_base r -> (
      match List.assoc_opt ref_base ctx.hexpr_params with
      | Some { shexpr = SHVar actual; _ } when same_indexed_ref actual r -> acc
      | Some actual -> collect_history_hexpr env n ctx stack acc actual
      | None -> acc)
  | SHPreK _ -> acc
  | SHPast (inner, _) -> collect_history_hexpr env n ctx stack acc inner
  | SHHistoryCall (name, r) ->
      let r = resolve_history_source_ref ctx r in
      add_generated_history env n name r acc
  | SHHistoryAlias _ -> acc
  | SHCall (callee, args) -> (
      let args = List.map (ident_arg_of_name ctx) args in
      match List.assoc_opt callee env.predicates with
      | None -> acc
      | Some pred ->
          if List.mem callee stack then
            failwith (Printf.sprintf "cyclic predicate expansion involving '%s'" callee);
          if List.length pred.predicate_params <> List.length args then
            failwith
              (Printf.sprintf "predicate '%s' expects %d arguments but got %d" callee
                 (List.length pred.predicate_params) (List.length args));
          let body =
            List.fold_left2
              (fun acc param value -> subst_hexpr ~param ~value acc)
              pred.predicate_body pred.predicate_params args
          in
          collect_history_hexpr env n ctx (callee :: stack) acc body)
  | SHExpr _ -> acc
  | SHBin (_, a, b) | SHCmp (_, a, b) ->
      let acc = collect_history_hexpr env n ctx stack acc a in
      collect_history_hexpr env n ctx stack acc b
  | SHUn (_, inner) -> collect_history_hexpr env n ctx stack acc inner
  | SHForall (param, enum_name, body) | SHExists (param, enum_name, body) ->
      enum_members env enum_name
      |> List.fold_left
           (fun acc value ->
             collect_history_hexpr env n ctx stack acc (subst_hexpr ~param ~value body))
           acc
  | SHRangeForall (param, lo, hi, body) | SHRangeExists (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.fold_left
           (fun acc value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             collect_history_hexpr env n ctx stack acc body)
           acc

and collect_history_spec_arg env n ctx stack acc = function
  | SAFormula f -> collect_history_ltl env n ctx stack acc f
  | SAHExpr h -> collect_history_hexpr env n ctx stack acc h

and collect_history_ltl env n ctx stack acc (f : S.ltl) =
  match f with
  | SLTrue | SLFalse -> acc
  | SLAtom (a, _, b) ->
      let acc = collect_history_hexpr env n ctx stack acc a in
      collect_history_hexpr env n ctx stack acc b
  | SLFo h -> collect_history_hexpr env n ctx stack acc h
  | SLFormulaParam name -> (
      match List.assoc_opt name ctx.formula_params with
      | Some actual -> collect_history_ltl env n ctx stack acc actual
      | None -> acc)
  | SLCall (name, args) ->
      let acc = List.fold_left (collect_history_spec_arg env n ctx stack) acc args in
      (match List.assoc_opt name env.spec_defs with
      | Some def ->
          if List.mem name stack then
            failwith (Printf.sprintf "cyclic spec definition expansion involving '%s'" name);
          if List.length def.spec_def_params <> List.length args then
            failwith
              (Printf.sprintf "spec definition '%s' expects %d arguments but got %d" name
                 (List.length def.spec_def_params) (List.length args));
          let ctx =
            List.fold_left2 bind_spec_param
              { ctx with spec_stack = name :: ctx.spec_stack }
              def.spec_def_params args
          in
          collect_history_ltl env n ctx (name :: stack) acc def.spec_def_body
      | None -> acc)
  | SLNot inner | SLX inner | SLG inner -> collect_history_ltl env n ctx stack acc inner
  | SLAnd (a, b) | SLOr (a, b) | SLImp (a, b) | SLW (a, b) ->
      let acc = collect_history_ltl env n ctx stack acc a in
      collect_history_ltl env n ctx stack acc b
  | SLForall (param, enum_name, body) | SLExists (param, enum_name, body) ->
      enum_members env enum_name
      |> List.fold_left
           (fun acc value ->
             collect_history_ltl env n ctx stack acc (subst_ltl ~param ~value body))
           acc
  | SLRangeForall (param, lo, hi, body) | SLRangeExists (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.fold_left
           (fun acc value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             collect_history_ltl env n ctx stack acc body)
           acc

let collect_node_histories env n contracts =
  let acc =
    List.fold_left
      (fun acc -> function
        | S.SCRequires f | S.SCEnsures f ->
            collect_history_ltl env n empty_spec_context [] acc f)
      [] contracts
  in
  n.state_invariants
  |> List.fold_left
       (fun acc (inv : S.state_invariant) ->
         collect_history_hexpr env n empty_spec_context [] acc inv.formula)
       acc
  |> List.rev

let generated_history_raw_vdecls (h : generated_history) : S.raw_vdecl list =
  ({ raw_vname = h.hist_name; raw_indices = None; raw_vty = h.hist_ty } : S.raw_vdecl)
  :: (generated_history_delay_names h @ generated_history_snapshot_names h
     |> List.map (fun raw_vname -> ({ raw_vname; raw_indices = None; raw_vty = h.hist_ty } : S.raw_vdecl)))

let scalar_ref name = S.mk_scalar_ref name

let scalar_expr name =
  S.mk_expr (SEVar (scalar_ref name))

let scalar_assign name rhs =
  S.mk_stmt (SSAssign (scalar_ref name, rhs))

let self_expr_for_depth h depth =
  if depth < 1 then failwith "pre_k(self, k) expects k >= 1";
  if generated_history_snapshot_count h > 0 then
    generated_history_snapshot_name h (depth - 1) |> scalar_expr
  else if depth = 1 then scalar_expr h.hist_name
  else generated_history_delay_name h (depth - 1) |> scalar_expr

let history_expr_failure h msg =
  failwith (Printf.sprintf "history definition '%s': %s" h.hist_def.S.history_def_name msg)

let rec expr_mentions name (e : S.expr) =
  match e.sexpr with
  | SELitInt _ | SELitBool _ -> false
  | SEVar r -> String.equal (indexed_ref_name r) name
  | SECall (_, args) -> List.exists (expr_mentions name) args
  | SEBin (_, a, b) | SECmp (_, a, b) -> expr_mentions name a || expr_mentions name b
  | SEUn (_, inner) -> expr_mentions name inner

let rec history_value_to_expr h ~phase (formula : S.hexpr) : S.expr =
  let source_param = h.hist_def.S.history_param in
  let source_name = indexed_ref_name h.hist_source in
  let loc = formula.hloc in
  let mk desc = S.mk_expr ?loc desc in
  let const_nat = function
    | SNNat n -> n
    | SNVar _ ->
        history_expr_failure h "history update uses non-constant pre_k depth"
  in
  match formula.shexpr with
  | SHLitInt n -> mk (SELitInt n)
  | SHLitBool b -> mk (SELitBool b)
  | SHVar r when is_scalar_ref_named source_param r -> mk (SEVar (scalar_ref source_name))
  | SHVar r when is_scalar_ref_named "self" r ->
      history_expr_failure h
        "history update reads bare self; use pre(self) or pre_k(self, k)"
  | SHVar r -> mk (SEVar r)
  | SHPreK (r, k) when is_scalar_ref_named "self" r ->
      if String.equal phase "init" then
        history_expr_failure h "init update cannot read pre(self)";
      self_expr_for_depth h (const_nat k)
  | SHPreK (r, _) when is_scalar_ref_named source_param r ->
      history_expr_failure h
        "history update cannot read pre(parameter); use the parameter for the current sample"
  | SHPreK _ | SHPast _ ->
      history_expr_failure h
        "history update can only use bounded past on self"
  | SHHistoryCall _ ->
      history_expr_failure h "history update cannot call another history definition"
  | SHHistoryAlias _ ->
      history_expr_failure h "history update cannot use a history alias"
  | SHCall (name, _) ->
      history_expr_failure h
        (Printf.sprintf "history update cannot call predicate '%s'" name)
  | SHExpr e ->
      let e =
        e
        |> subst_expr ~param:source_param ~value:source_name
      in
      if expr_mentions "self" e then
        history_expr_failure h
          "history update reads bare self inside an executable expression; use pre(self)"
      else e
  | SHBin (op, a, b) ->
      mk (SEBin (op, history_value_to_expr h ~phase a, history_value_to_expr h ~phase b))
  | SHCmp (op, a, b) ->
      mk (SECmp (op, history_value_to_expr h ~phase a, history_value_to_expr h ~phase b))
  | SHUn (op, inner) -> mk (SEUn (op, history_value_to_expr h ~phase inner))
  | SHForall _ | SHExists _ | SHRangeForall _ | SHRangeExists _ ->
      history_expr_failure h "history update cannot contain quantifiers"

let rec history_update_stmts h ~phase target (value : S.history_expr) : S.stmt list =
  match value.shistory_expr with
  | SHValue formula -> [ scalar_assign target (history_value_to_expr h ~phase formula) ]
  | SHIf (cond, then_value, else_value) ->
      [
        S.mk_stmt
          (SSIf
             ( history_value_to_expr h ~phase cond,
               history_update_stmts h ~phase target then_value,
               history_update_stmts h ~phase target else_value ));
      ]

let history_init_stmts h =
  let update = history_update_stmts h ~phase:"init" h.hist_name h.hist_def.S.history_init in
  let padding_targets = generated_history_delay_names h @ generated_history_snapshot_names h in
  update @ List.map (fun target -> scalar_assign target (scalar_expr h.hist_name)) padding_targets

let history_step_stmts h =
  let snapshot_stmts =
    match generated_history_snapshot_names h with
    | [] -> []
    | snap0 :: rest ->
        scalar_assign snap0 (scalar_expr h.hist_name)
        :: List.mapi
             (fun idx snap -> scalar_assign snap (scalar_expr (generated_history_delay_name h (idx + 1))))
             rest
  in
  let update = history_update_stmts h ~phase:"step" h.hist_name h.hist_def.S.history_step in
  let delay_updates =
    List.init (generated_history_delay_count h) (fun i ->
        let delay_idx = i + 1 in
        scalar_assign (generated_history_delay_name h delay_idx)
          (scalar_expr (generated_history_snapshot_name h (delay_idx - 1))))
  in
  snapshot_stmts @ update @ delay_updates

let history_updates_for_transition ~(init_state : ident) histories (t : S.transition) =
  let is_init_transition = String.equal t.src init_state in
  List.concat_map
    (fun h -> if is_init_transition then history_init_stmts h else history_step_stmts h)
    histories

let rec shift_input_pre_for_transition input_names (formula : S.hexpr) =
  let shift_nat k =
    match k with
    | SNNat n ->
        if n <= 1 then None else Some (SNNat (n - 1))
    | SNVar _ ->
        failwith "history transition ensures uses non-constant pre_k depth on an input"
  in
  let shexpr =
    match formula.shexpr with
    | SHLitInt _ | SHLitBool _ | SHVar _ -> formula.shexpr
    | SHPreK (r, k) when List.mem (indexed_ref_name r) input_names -> (
        match shift_nat k with
        | None -> SHVar r
        | Some k -> SHPreK (r, k))
    | SHPreK _ -> formula.shexpr
    | SHPast (inner, k) -> SHPast (shift_input_pre_for_transition input_names inner, k)
    | SHHistoryCall _ | SHHistoryAlias _ | SHCall _ | SHExpr _ -> formula.shexpr
    | SHBin (op, a, b) ->
        SHBin
          (op, shift_input_pre_for_transition input_names a, shift_input_pre_for_transition input_names b)
    | SHCmp (op, a, b) ->
        SHCmp
          (op, shift_input_pre_for_transition input_names a, shift_input_pre_for_transition input_names b)
    | SHUn (op, inner) -> SHUn (op, shift_input_pre_for_transition input_names inner)
    | SHForall (param, enum_name, body) ->
        SHForall (param, enum_name, shift_input_pre_for_transition input_names body)
    | SHExists (param, enum_name, body) ->
        SHExists (param, enum_name, shift_input_pre_for_transition input_names body)
    | SHRangeForall (param, lo, hi, body) ->
        SHRangeForall (param, lo, hi, shift_input_pre_for_transition input_names body)
    | SHRangeExists (param, lo, hi, body) ->
        SHRangeExists (param, lo, hi, shift_input_pre_for_transition input_names body)
  in
  { formula with shexpr }

let instantiate_history_hexpr h formula =
  formula
  |> subst_hexpr ~param:h.hist_def.S.history_param ~value:(indexed_ref_name h.hist_source)
  |> subst_hexpr ~param:"self" ~value:h.hist_name

let history_phase_ensures input_names h phase_formulas =
  phase_formulas
  |> List.map (instantiate_history_hexpr h)
  |> List.map (shift_input_pre_for_transition input_names)

let history_ensures_for_transition ~(input_names : ident list) ~(init_state : ident) histories
    (t : S.transition) =
  let is_init_transition = String.equal t.src init_state in
  histories
  |> List.concat_map (fun h ->
         if is_init_transition then
           history_phase_ensures input_names h h.hist_def.S.history_init_ensures
         else history_phase_ensures input_names h h.hist_def.S.history_step_ensures)

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
  | SSWhile (cond, invariants, variant, body) ->
      [
        Kx_ast_builders.mk_stmt ?loc:s.sloc
          (SWhile
             ( lower_expr env cond,
               List.map (lower_hexpr env empty_spec_context []) invariants,
               Option.map (lower_expr env) variant,
               lower_stmt_list env stack body ));
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
  | SSFor (param, enum_name, body) ->
      enum_members env enum_name
      |> List.concat_map (fun value ->
             body
             |> List.map (subst_stmt ~param ~value)
             |> lower_stmt_list env stack)
  | SSForRange (param, lo, hi, body) ->
      range_values (eval_nat empty_spec_context lo) (eval_nat empty_spec_context hi)
      |> List.concat_map (fun value ->
             body
             |> List.map (subst_stmt ~param ~value:(string_of_int value))
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
      let instantiate formulas =
        List.fold_left2
          (fun acc param value -> List.map (subst_hexpr ~param ~value) acc)
          formulas action.action_params args
      in
      let assertion formula =
        Kx_ast_builders.mk_stmt
          (SAssert (lower_hexpr env empty_spec_context [] formula))
      in
      List.map assertion (instantiate action.action_requires)
      @ lower_stmt_list env (name :: stack) body
      @ List.map assertion (instantiate action.action_ensures)

let validate_unique_named_decls kind get_name decls =
  let seen = Hashtbl.create 17 in
  List.iter
    (fun decl ->
      let name = get_name decl in
      match Hashtbl.find_opt seen name with
      | Some () -> failwith (Printf.sprintf "duplicate %s '%s'" kind name)
      | None -> Hashtbl.add seen name ())
    decls

let observer_raw_vdecl (obs : S.observer_decl) : S.raw_vdecl =
  { raw_vname = obs.observer_name; raw_indices = None; raw_vty = obs.observer_ty }

let observer_init_stmts (obs : S.observer_decl) = obs.observer_init

let observer_step_stmts (obs : S.observer_decl) = obs.observer_step

let observer_updates_for_transition ~(init_state : ident) observers (t : S.transition) =
  let is_init_transition = String.equal t.src init_state in
  List.concat_map
	(fun obs -> if is_init_transition then observer_init_stmts obs else observer_step_stmts obs)
	observers

let rec stmt_assigns_to targets (s : S.stmt) : ident option =
  let assigned_ref r =
    let name = indexed_ref_name r in
    if List.mem name targets then Some name else None
  in
  match s.sstmt with
  | SSAssign (lhs, _) -> assigned_ref lhs
  | SSIf (_, then_branch, else_branch) ->
      List.find_map (stmt_assigns_to targets) (then_branch @ else_branch)
  | SSWhile (_, _, _, body) -> List.find_map (stmt_assigns_to targets) body
  | SSMatch (_, branches, default_branch) ->
      List.find_map (stmt_assigns_to targets)
        (List.concat_map snd branches @ default_branch)
  | SSSkip | SSCall _ | SSActionCall _ -> None
  | SSFor (_, _, body) -> List.find_map (stmt_assigns_to targets) body
  | SSForRange (_, _, _, body) -> List.find_map (stmt_assigns_to targets) body

let rec expr_refs (e : S.expr) : ident list =
  match e.sexpr with
  | SELitInt _ | SELitBool _ -> []
  | SEVar r -> [ indexed_ref_name r ]
  | SECall (_, args) -> List.concat_map expr_refs args
  | SEBin (_, a, b) | SECmp (_, a, b) -> expr_refs a @ expr_refs b
  | SEUn (_, inner) -> expr_refs inner

let rec hexpr_refs (h : S.hexpr) : ident list =
  match h.shexpr with
  | SHLitInt _ | SHLitBool _ -> []
  | SHVar r | SHPreK (r, _) | SHHistoryCall (_, r) | SHHistoryAlias (_, r) ->
      [ indexed_ref_name r ]
  | SHPast (inner, _) -> hexpr_refs inner
  | SHCall (_, args) -> args
  | SHExpr e -> expr_refs e
  | SHBin (_, a, b) | SHCmp (_, a, b) -> hexpr_refs a @ hexpr_refs b
  | SHUn (_, inner) -> hexpr_refs inner
  | SHForall (bound, _, body) | SHExists (bound, _, body) ->
      List.filter (fun name -> not (String.equal name bound)) (hexpr_refs body)
  | SHRangeForall (bound, _, _, body) | SHRangeExists (bound, _, _, body) ->
      List.filter (fun name -> not (String.equal name bound)) (hexpr_refs body)

let rec stmt_refs (s : S.stmt) : ident list =
  match s.sstmt with
  | SSAssign (_, rhs) -> expr_refs rhs
  | SSIf (cond, then_branch, else_branch) ->
      expr_refs cond @ List.concat_map stmt_refs (then_branch @ else_branch)
  | SSWhile (cond, invariants, variant, body) ->
      expr_refs cond
      @ List.concat_map hexpr_refs invariants
      @ Option.fold ~none:[] ~some:expr_refs variant
      @ List.concat_map stmt_refs body
  | SSMatch (scrutinee, branches, default_branch) ->
      expr_refs scrutinee @ List.concat_map stmt_refs (List.concat_map snd branches @ default_branch)
  | SSSkip -> []
  | SSCall (_, args, _) -> List.concat_map expr_refs args
  | SSActionCall _ -> []
  | SSFor (_, _, body) -> List.concat_map stmt_refs body
  | SSForRange (_, _, _, body) -> List.concat_map stmt_refs body

let rec stmt_assignment_targets (s : S.stmt) : ident list =
  match s.sstmt with
  | SSAssign (lhs, _) -> [ indexed_ref_name lhs ]
  | SSIf (_, then_branch, else_branch) ->
      List.concat_map stmt_assignment_targets (then_branch @ else_branch)
  | SSWhile (_, _, _, body) -> List.concat_map stmt_assignment_targets body
  | SSMatch (_, branches, default_branch) ->
      List.concat_map stmt_assignment_targets (List.concat_map snd branches @ default_branch)
  | SSSkip | SSCall _ | SSActionCall _ -> []
  | SSFor (_, _, body) -> List.concat_map stmt_assignment_targets body
  | SSForRange (_, _, _, body) -> List.concat_map stmt_assignment_targets body

let rec stmt_must_assign target (s : S.stmt) : bool =
  match s.sstmt with
  | SSAssign (lhs, _) -> String.equal (indexed_ref_name lhs) target
  | SSIf (_, then_branch, else_branch) ->
      stmt_list_must_assign target then_branch && stmt_list_must_assign target else_branch
  | SSMatch (_, branches, default_branch) ->
      List.for_all (fun (_, body) -> stmt_list_must_assign target body) branches
      && stmt_list_must_assign target default_branch
  | SSSkip | SSCall _ | SSActionCall _ | SSFor _ | SSForRange _ | SSWhile _ -> false

and stmt_list_must_assign target body =
  List.exists (stmt_must_assign target) body

let validate_observer_body observer_names (obs : S.observer_decl) phase body =
  let context =
    Printf.sprintf "observer '%s' %s block" obs.observer_name phase
  in
  let rec reject_unsupported_stmt (s : S.stmt) =
    match s.sstmt with
    | SSAssign _ | SSSkip -> ()
    | SSIf (_, then_branch, else_branch) ->
        List.iter reject_unsupported_stmt (then_branch @ else_branch)
    | SSWhile _ ->
        failwith
          (Printf.sprintf "%s cannot contain a while loop; observer updates must be scalar" context)
    | SSMatch (_, branches, default_branch) ->
        List.iter reject_unsupported_stmt (List.concat_map snd branches @ default_branch)
    | SSCall _ ->
        failwith
          (Printf.sprintf "%s cannot call a node; observer updates must be local" context)
    | SSActionCall _ ->
        failwith
          (Printf.sprintf "%s cannot call an action; observer updates must be explicit" context)
    | SSFor _ ->
        failwith
          (Printf.sprintf "%s cannot contain a for loop; observer updates must be scalar" context)
    | SSForRange _ ->
        failwith
          (Printf.sprintf "%s cannot contain a for loop; observer updates must be scalar" context)
  in
  List.iter reject_unsupported_stmt body;
  let targets = List.concat_map stmt_assignment_targets body in
  List.iter
    (fun target ->
      if not (String.equal target obs.observer_name) then
        failwith
          (Printf.sprintf
             "%s assigns '%s'; an observer block may only assign its own variable"
             context target))
    targets;
  if not (stmt_list_must_assign obs.observer_name body) then
    failwith
      (Printf.sprintf "%s must assign observer '%s' on every path" context obs.observer_name);
  let refs = List.concat_map stmt_refs body in
  let forbidden_observer_ref name =
    List.mem name observer_names
    && (String.equal phase "init" || not (String.equal name obs.observer_name))
  in
  match List.find_opt forbidden_observer_ref refs with
  | None -> ()
  | Some name ->
      failwith
        (Printf.sprintf
           "%s reads observer '%s'; init blocks cannot read observers and step blocks may only read their own observer"
           context name)

let validate_observers (n : S.node) =
  validate_unique_named_decls "observer" (fun (o : S.observer_decl) -> o.observer_name) n.observers;
  if n.observers <> [] then (
    List.iter
      (fun (t : S.transition) ->
        if String.equal t.dst n.state_decls.init_state then
          failwith
            (Printf.sprintf
               "observer initialization in node '%s' requires a dedicated init state; transition %s -> %s returns to init state '%s'"
               n.node_name t.src t.dst n.state_decls.init_state))
      n.transitions;
    let observer_names = List.map (fun (o : S.observer_decl) -> o.observer_name) n.observers in
    List.iter
      (fun (obs : S.observer_decl) ->
        validate_observer_body observer_names obs "init" obs.observer_init;
        validate_observer_body observer_names obs "step" obs.observer_step)
      n.observers;
    let reject_observer_read context refs =
      match List.find_opt (fun name -> List.mem name observer_names) refs with
      | Some name ->
          failwith
            (Printf.sprintf
               "%s reads observer '%s'; observers are proof-only and cannot drive source behavior"
               context name)
      | None -> ()
    in
    let check_body context body =
      match List.find_map (stmt_assigns_to observer_names) body with
      | Some name ->
          failwith
            (Printf.sprintf
               "%s assigns observer '%s'; observer variables are generated by the frontend"
               context name)
      | None -> reject_observer_read context (List.concat_map stmt_refs body)
    in
    List.iter
      (fun (t : S.transition) ->
        Option.iter
          (fun guard ->
            reject_observer_read
              (Printf.sprintf "guard of transition %s -> %s in node '%s'" t.src t.dst
                 n.node_name)
              (expr_refs guard))
          t.guard;
        check_body
          (Printf.sprintf "transition %s -> %s in node '%s'" t.src t.dst n.node_name)
          t.body)
      n.transitions;
	List.iter
	  (fun (a : S.action_decl) ->
	    check_body (Printf.sprintf "action '%s' in node '%s'" a.action_name n.node_name)
	      a.action_body)
	  n.actions)

let validate_action_contracts (n : S.node) =
  let rec check_formula context (h : S.hexpr) =
    match h.shexpr with
    | SHLitInt _ | SHLitBool _ | SHVar _ -> ()
    | SHPreK _ | SHPast _ | SHHistoryCall _ | SHHistoryAlias _ ->
        failwith
          (Printf.sprintf
             "%s cannot use temporal or history operators; action contracts are local block contracts"
             context)
    | SHCall _ ->
        failwith
          (Printf.sprintf
             "%s cannot call predicates yet; action contracts must expose their local formula directly"
             context)
    | SHExpr _ -> ()
    | SHBin (_, a, b) | SHCmp (_, a, b) ->
        check_formula context a;
        check_formula context b
    | SHUn (_, inner) -> check_formula context inner
    | SHForall (_, _, body) | SHExists (_, _, body)
    | SHRangeForall (_, _, _, body) | SHRangeExists (_, _, _, body) ->
        check_formula context body
  in
  List.iter
    (fun (a : S.action_decl) ->
      List.iter
        (check_formula
           (Printf.sprintf "requires clause of action '%s' in node '%s'" a.action_name
              n.node_name))
        a.action_requires;
      List.iter
        (check_formula
           (Printf.sprintf "ensures clause of action '%s' in node '%s'" a.action_name
              n.node_name))
        a.action_ensures)
    n.actions

let validate_history_def_decl (d : S.history_def_decl) =
  let context = Printf.sprintf "history definition '%s'" d.history_def_name in
  let rec validate_update_hexpr phase (h : S.hexpr) =
    let validate_expr e =
      if List.mem "self" (expr_refs e) then
        failwith
          (Printf.sprintf
             "%s %s expression reads bare self inside executable braces; use pre(self)"
             context phase)
    in
    match h.shexpr with
    | SHLitInt _ | SHLitBool _ -> ()
    | SHVar r when is_scalar_ref_named "self" r ->
        failwith
          (Printf.sprintf "%s %s expression reads bare self; use pre(self)" context phase)
    | SHVar _ -> ()
    | SHPreK (r, _) when is_scalar_ref_named "self" r ->
        if String.equal phase "init" then
          failwith (Printf.sprintf "%s init expression cannot read pre(self)" context)
    | SHPreK (r, _) when is_scalar_ref_named d.history_param r ->
        failwith
          (Printf.sprintf
             "%s %s expression cannot read pre(%s); use %s for the current sample"
             context phase d.history_param d.history_param)
    | SHPreK _ | SHPast _ ->
        failwith
          (Printf.sprintf "%s %s expression can only use bounded past on self"
             context phase)
    | SHHistoryCall _ ->
        failwith
          (Printf.sprintf "%s %s expression cannot call another history definition"
             context phase)
    | SHHistoryAlias _ ->
        failwith
          (Printf.sprintf "%s %s expression cannot use a history alias" context phase)
    | SHCall (name, _) ->
        failwith
          (Printf.sprintf "%s %s expression cannot call predicate '%s'" context phase name)
    | SHExpr e -> validate_expr e
    | SHBin (_, a, b) | SHCmp (_, a, b) ->
        validate_update_hexpr phase a;
        validate_update_hexpr phase b
    | SHUn (_, inner) -> validate_update_hexpr phase inner
    | SHForall _ | SHExists _ | SHRangeForall _ | SHRangeExists _ ->
        failwith
          (Printf.sprintf "%s %s expression cannot contain quantifiers" context phase)
  in
  let rec validate_update_expr phase (h : S.history_expr) =
    match h.shistory_expr with
    | SHValue formula -> validate_update_hexpr phase formula
    | SHIf (cond, then_value, else_value) ->
        validate_update_hexpr phase cond;
        validate_update_expr phase then_value;
        validate_update_expr phase else_value
  in
  let rec ensure_contains_history_call (formula : S.hexpr) =
    match formula.shexpr with
    | SHHistoryCall _ | SHHistoryAlias _ -> true
    | SHLitInt _ | SHLitBool _ | SHVar _ | SHPreK _ | SHCall _ | SHExpr _ -> false
    | SHPast (inner, _) | SHUn (_, inner) -> ensure_contains_history_call inner
    | SHBin (_, a, b) | SHCmp (_, a, b) ->
        ensure_contains_history_call a || ensure_contains_history_call b
    | SHForall (_, _, body) | SHExists (_, _, body) -> ensure_contains_history_call body
    | SHRangeForall (_, _, _, body) | SHRangeExists (_, _, _, body) ->
        ensure_contains_history_call body
  in
  let validate_ensures phase formulas =
    List.iter
      (fun formula ->
        if ensure_contains_history_call formula then
          failwith
            (Printf.sprintf "%s %s ensures cannot call history definitions or aliases"
               context phase))
      formulas
  in
  validate_update_expr "init" d.history_init;
  validate_update_expr "step" d.history_step;
  validate_ensures "init" d.history_init_ensures;
  validate_ensures "step" d.history_step_ensures

let expand_observers_in_transition ~init_state observers (t : S.transition) =
  { t with body = t.body @ observer_updates_for_transition ~init_state observers t }

let expand_histories_in_transition ~input_names ~init_state histories (t : S.transition) =
  {
    t with
	body = t.body @ history_updates_for_transition ~init_state histories t;
	ensures =
	  t.ensures @ history_ensures_for_transition ~input_names ~init_state histories t;
      }

let observer_locals observers = List.map observer_raw_vdecl observers

let history_ghosts histories =
  List.concat_map generated_history_raw_vdecls histories

let lower_contracts env contracts =
  let assumes, guarantees =
    List.fold_left
      (fun (assumes, guarantees) -> function
        | S.SCRequires f -> (List.rev_append (lower_contract_ltls env f) assumes, guarantees)
        | S.SCEnsures f -> (assumes, List.rev_append (lower_contract_ltls env f) guarantees))
      ([], []) contracts
  in
  (List.rev assumes, List.rev guarantees)

let lower_transition env (t : S.transition) : Kx_ast.transition =
  Kx_ast_builders.mk_transition ~src:t.src ~dst:t.dst
    ~guard:(Option.map (lower_expr env) t.guard)
    ~body:(lower_stmt_list env [] t.body)
    ~ensures:(List.map (lower_hexpr env empty_spec_context []) t.ensures)
    ()

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
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.spec_defs then
        failwith
          (Printf.sprintf "predicate '%s' conflicts with a spec definition of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.history_defs then
        failwith
          (Printf.sprintf "predicate '%s' conflicts with a history definition of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.functions then
        failwith
          (Printf.sprintf "action '%s' conflicts with a pure function of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.spec_defs then
        failwith
          (Printf.sprintf "action '%s' conflicts with a spec definition of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.history_defs then
        failwith
          (Printf.sprintf "action '%s' conflicts with a history definition of the same name" a.action_name))
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

let state_mem name states =
  List.exists (String.equal name) states

let state_ordered_filter states selected =
  List.filter (fun state -> state_mem state selected) states

let first_duplicate names =
  let seen = Hashtbl.create 17 in
  List.find_opt
    (fun name ->
      if Hashtbl.mem seen name then true
      else (
        Hashtbl.add seen name ();
        false))
    names

let resolve_state_selector ~node_name ~states selector =
  let validate_state state =
    if not (state_mem state states) then
      failwith
        (Printf.sprintf "unknown invariant state '%s' in node '%s'" state node_name)
  in
  let rec resolve = function
    | S.SSelState state ->
        validate_state state;
        [ state ]
    | S.SSelSet selected ->
        (match first_duplicate selected with
        | Some state ->
            failwith
              (Printf.sprintf "duplicate invariant state '%s' in node '%s'" state node_name)
        | None -> ());
        List.iter validate_state selected;
        state_ordered_filter states selected
    | S.SSelAll -> states
    | S.SSelDiff (a, b) ->
        let a = resolve a in
        let b = resolve b in
        List.filter (fun state -> state_mem state a && not (state_mem state b)) states
  in
  resolve selector

let expand_state_invariants (n : S.node) =
  List.concat_map
    (fun (inv : S.state_invariant) ->
      let states =
        resolve_state_selector ~node_name:n.node_name ~states:n.state_decls.states inv.selector
      in
      if states = [] then
        failwith
          (Printf.sprintf
             "state selector for an invariant in node '%s' does not select any state"
             n.node_name);
      List.map (fun state -> (state, inv.formula)) states)
    n.state_invariants

let lower_node base_env (n : S.node) : Kx_ast.node =
  let env = node_env base_env n in
  validate_observers n;
  validate_action_contracts n;
  let contracts = n.contracts in
  let generated_histories = collect_node_histories env n contracts in
  let generated_history_ghosts = history_ghosts generated_histories in
  let generated_observer_ghosts = observer_locals n.observers in
  let public_ghosts = List.map (fun (o : S.observer_decl) -> o.observer_name) n.observers in
  let input_names = List.map (fun (v : vdecl) -> v.vname) (lower_raw_vdecls env n.inputs) in
  let transitions =
    List.map
      (expand_histories_in_transition ~input_names ~init_state:n.state_decls.init_state
         generated_histories)
      n.transitions
    |> List.map
         (expand_observers_in_transition ~init_state:n.state_decls.init_state n.observers)
  in
  let assumes, guarantees = lower_contracts env contracts in
  let state_invariants = expand_state_invariants n in
  let node =
    Kx_ast_builders.mk_node ~nname:n.node_name ~inputs:(lower_raw_vdecls env n.inputs)
	  ~outputs:(lower_raw_vdecls env n.outputs) ~assumes ~guarantees ~instances:n.instances
	  ~locals:(lower_raw_vdecls env n.locals)
	  ~ghosts:(lower_raw_vdecls env (n.ghosts @ generated_history_ghosts @ generated_observer_ghosts))
	  ~public_ghosts
      ~states:n.state_decls.states ~init_state:n.state_decls.init_state
      ~trans:(List.map (lower_transition env) transitions)
  in
  {
    node with
    specification =
      {
        node.specification with
        spec_invariants_state_rel =
          List.map
            (fun (state, formula) ->
              { Kx_ast.state; formula = lower_hexpr env empty_spec_context [] formula })
            state_invariants;
      };
  }

let lower_function_decl env (f : S.function_decl) : pure_function_decl =
  {
    function_name = f.function_name;
    function_params = lower_raw_vdecls env f.function_params;
    function_return = f.function_return;
    function_requires = List.map (lower_hexpr env empty_spec_context []) f.function_requires;
    function_ensures = List.map (lower_hexpr env empty_spec_context []) f.function_ensures;
    function_body = lower_expr env f.function_body;
  }

let validate_spec_def_decl (d : S.spec_def_decl) =
  validate_unique_named_decls "spec definition parameter" (fun p -> p.S.spec_param_name) d.spec_def_params

let elaborate_frontend_decl (env, type_decls, function_decls) = function
  | S.STypeDecl decl ->
      let env = add_enum_set env decl.enum_name decl.enum_constructors in
      (env, decl :: type_decls, function_decls)
	  | S.SFunctionDecl f ->
	      if List.mem_assoc f.function_name env.functions then
	        failwith (Printf.sprintf "duplicate pure function '%s'" f.function_name);
	      if List.mem_assoc f.function_name env.spec_defs then
	        failwith
	          (Printf.sprintf "pure function '%s' conflicts with a spec definition of the same name" f.function_name);
	      if List.mem_assoc f.function_name env.history_defs then
	        failwith
	          (Printf.sprintf "pure function '%s' conflicts with a history definition of the same name" f.function_name);
	      let lowered = lower_function_decl env f in
	      let signature = (lowered.function_params, lowered.function_return) in
	      let env = { env with functions = (lowered.function_name, signature) :: env.functions } in
	      (env, type_decls, lowered :: function_decls)
	  | S.SSpecDefDecl d ->
      validate_spec_def_decl d;
      if List.mem_assoc d.spec_def_name env.spec_defs then
        failwith (Printf.sprintf "duplicate spec definition '%s'" d.spec_def_name);
	      if List.mem_assoc d.spec_def_name env.functions then
	        failwith
	          (Printf.sprintf "spec definition '%s' conflicts with a pure function of the same name" d.spec_def_name);
	      if List.mem_assoc d.spec_def_name env.history_defs then
	        failwith
	          (Printf.sprintf "spec definition '%s' conflicts with a history definition of the same name" d.spec_def_name);
	      let env = { env with spec_defs = (d.spec_def_name, d) :: env.spec_defs } in
	      (env, type_decls, function_decls)
	  | S.SHistoryDefDecl d ->
	      validate_history_def_decl d;
	      if List.mem_assoc d.history_def_name env.history_defs then
	        failwith (Printf.sprintf "duplicate history definition '%s'" d.history_def_name);
	      if List.mem_assoc d.history_def_name env.functions then
	        failwith
	          (Printf.sprintf "history definition '%s' conflicts with a pure function of the same name" d.history_def_name);
	      if List.mem_assoc d.history_def_name env.spec_defs then
	        failwith
	          (Printf.sprintf "history definition '%s' conflicts with a spec definition of the same name" d.history_def_name);
	      let env = { env with history_defs = (d.history_def_name, d) :: env.history_defs } in
	      (env, type_decls, function_decls)

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
