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
open Kx_elaborate_env

module B = Kx_core_syntax_builders
module S = Kx_surface_syntax
module Names = Kx_elaborate_names
module Subst = Kx_elaborate_subst

let indexed_ref_name = Names.indexed_ref_name
let generated_history_name = Names.generated_history_name
let nat_literal_of_ident = Subst.nat_literal_of_ident
let subst_hexpr = Subst.subst_hexpr
let subst_ltl = Subst.subst_ltl

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
    | HPreK _ -> Kx_frontend_error.elaboration "historical predicate cannot be used in executable expressions"
    | HPred _ -> Kx_frontend_error.elaboration "unexpanded predicate cannot be used in executable expressions"
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
      Kx_frontend_error.elaboration
        (Printf.sprintf
           "historical expression operator expects variable argument '%s' to be a variable reference"
           r.ref_base)
  | _ -> r

let rec shift_hexpr_past k (h : hexpr) : hexpr =
  if k < 0 then
    Kx_frontend_error.well_formedness "past offset must be non-negative";
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

let ident_args_of_exprs ~(context : string) (args : S.expr list) : ident list =
  List.map
    (fun arg ->
      match arg.sexpr with
      | SEVar { ref_base; ref_indices = [] } -> ref_base
      | _ -> Kx_frontend_error.elaboration (Printf.sprintf "%s expects identifier arguments" context))
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
      | None -> Kx_frontend_error.elaboration (Printf.sprintf "unknown history alias '%s'" alias))

let rec ident_arg_of_surface_hexpr ctx (h : S.hexpr) : ident =
  match h.shexpr with
  | SHVar ({ ref_base; ref_indices = [] } as r) -> (
      match List.assoc_opt ref_base ctx.hexpr_params with
      | Some actual -> ident_arg_of_surface_hexpr ctx actual
      | None -> indexed_ref_name r)
  | _ -> Kx_frontend_error.elaboration "predicate arguments must be identifiers"

let ident_arg_of_name ctx id =
  match List.assoc_opt id ctx.hexpr_params with
  | Some actual -> ident_arg_of_surface_hexpr ctx actual
  | None -> id

let spec_arg_as_ident ctx = function
  | SAHExpr h -> ident_arg_of_surface_hexpr ctx h
  | SAFormula _ -> Kx_frontend_error.elaboration "predicate arguments must be identifiers"

let formula_arg_of_spec_arg _ctx = function
  | SAFormula f -> f
  | SAHExpr _ -> Kx_frontend_error.elaboration "Formula parameter expects a formula argument"

let hexpr_arg_of_spec_arg ctx = function
  | SAHExpr ({ shexpr = SHVar { ref_base; ref_indices = [] }; _ }) as arg -> (
      match List.assoc_opt ref_base ctx.hexpr_params with
      | Some h -> h
      | None -> (
          match arg with SAHExpr h -> h | SAFormula _ -> assert false))
  | SAHExpr h -> h
  | SAFormula _ -> Kx_frontend_error.elaboration "HExpr parameter expects a historical expression argument"

let nat_arg_of_spec_arg ctx = function
  | SAHExpr { shexpr = SHLitInt n; _ } ->
      if n < 0 then
        Kx_frontend_error.well_formedness
          "Nat parameter expects a non-negative integer";
      n
  | SAHExpr { shexpr = SHVar { ref_base; ref_indices = [] }; _ } -> eval_nat ctx (SNVar ref_base)
  | _ -> Kx_frontend_error.elaboration "Nat parameter expects an integer literal or Nat parameter"

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
        Kx_frontend_error.elaboration (Printf.sprintf "unknown history definition '%s'" name);
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
  match List.assoc_opt name env.predicates with
  | None -> Kx_frontend_error.elaboration (Printf.sprintf "unknown predicate '%s'" name)
  | Some pred ->
      if List.mem name stack then
        Kx_frontend_error.elaboration (Printf.sprintf "cyclic predicate expansion involving '%s'" name);
      if List.length pred.predicate_params <> List.length args then
        Kx_frontend_error.elaboration
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
        Kx_frontend_error.elaboration (Printf.sprintf "cyclic spec definition expansion involving '%s'" name);
      if List.length def.spec_def_params <> List.length args then
        Kx_frontend_error.elaboration
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
      | None -> Kx_frontend_error.elaboration (Printf.sprintf "unknown Formula parameter '%s'" name))
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
