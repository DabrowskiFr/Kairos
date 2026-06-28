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
open Kx_elaborate_logic

module S = Kx_surface_syntax
module Names = Kx_elaborate_names
module Subst = Kx_elaborate_subst

let indexed_ref_name = Names.indexed_ref_name
let same_indexed_ref = Names.same_indexed_ref
let generated_history_name = Names.generated_history_name
let subst_expr = Subst.subst_expr
let subst_hexpr = Subst.subst_hexpr
let subst_ltl = Subst.subst_ltl

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
      max (max_self_pre_depth_hexpr self_name a)
        (max_self_pre_depth_hexpr self_name b)
  | SHUn (_, inner) -> max_self_pre_depth_hexpr self_name inner
  | SHForall (_, _, body) | SHExists (_, _, body) ->
      max_self_pre_depth_hexpr self_name body
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
      (fun h ->
        String.equal
          (generated_history_key h.hist_def.S.history_def_name h.hist_source)
          key)
      acc
  then acc
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
     |> List.map (fun raw_vname ->
            ({ raw_vname; raw_indices = None; raw_vty = h.hist_ty } : S.raw_vdecl)))

let history_ghosts histories =
  List.concat_map generated_history_raw_vdecls histories

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
        failwith
          "history elaboration check uses non-constant pre_k depth on an input"
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

let expand_histories_in_transition ~input_names ~init_state histories (t : S.transition) =
  {
    t with
    body = t.body @ history_updates_for_transition ~init_state histories t;
    ensures =
      t.ensures @ history_ensures_for_transition ~input_names ~init_state histories t;
  }
