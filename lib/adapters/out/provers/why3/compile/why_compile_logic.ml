(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Why3
open Ptree
open Core_syntax
open Why_compile_expr
open Why_compile_ptree_helpers

module StringSet = Why_compile_ptree_helpers.StringSet

let balance_boolean_hexpr (formula : Core_syntax.hexpr) : Core_syntax.hexpr =
  let build_balanced op formulas =
    match formulas with
    | [] -> invalid_arg "balance_boolean_hexpr: empty boolean formula list"
    | [ formula ] -> formula
    | _ ->
        let arr = Array.of_list formulas in
        let rec build lo hi =
          if hi - lo = 1 then arr.(lo)
          else
            let mid = lo + ((hi - lo) / 2) in
            Core_syntax_builders.mk_hexpr (HBin (op, build lo mid, build mid hi))
        in
        build 0 (Array.length arr)
  in
  let rec flatten op acc h =
    match h.hexpr with
    | HBin (op', a, b) when op = op' -> flatten op (flatten op acc b) a
    | _ -> h :: acc
  in
  let rec normalize h =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> h
    | HUn (op, inner) -> Core_syntax_builders.with_hexpr_desc h (HUn (op, normalize inner))
    | HPred (id, hs) -> Core_syntax_builders.with_hexpr_desc h (HPred (id, List.map normalize hs))
    | HFunCall (fn, hs) ->
        Core_syntax_builders.with_hexpr_desc h (HFunCall (fn, List.map normalize hs))
    | HBin ((And | Or as op), _, _) ->
        flatten op [] h |> List.rev |> List.map normalize |> build_balanced op
    | HBin (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h (HBin (op, normalize a, normalize b))
    | HCmp (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h (HCmp (op, normalize a, normalize b))
  in
  normalize formula

let logic_getter_decl ~(env : Why_compile_expr.env) (vname : ident) (vty : ty) :
    Ptree.decl =
  let field_name = vname in
  let getter_name = ident ("logic_" ^ field_name) in
  let param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let body = term_of_var { env with rec_name = "self" } field_name in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = getter_name;
        ld_params = [ param ];
        ld_type = Some (default_pty vty);
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl ~(env : Why_compile_expr.env)
    ~(input_ports : Why_runtime_view.port_view list) ~(name : string)
    ~(formula : Core_syntax.hexpr) : Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let input_params =
    List.map
      (fun (p : Why_runtime_view.port_view) ->
        (loc, Some (ident p.port_name), false, default_pty p.port_type))
      input_ports
  in
  let body = Why_compile_expr.compile_local_fo_formula_term env (balance_boolean_hexpr formula) in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = self_param :: input_params;
        ld_type = None;
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl_with_params ~(env : Why_compile_expr.env)
    ~(params : (ident * Ptree.pty) list) ~(name : string)
    ~(formula : Core_syntax.hexpr) : Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let params =
    List.map (fun (name, pty) -> (loc, Some (ident name), false, pty)) params
  in
  let body = Why_compile_expr.compile_local_fo_formula_term env (balance_boolean_hexpr formula) in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = self_param :: params;
        ld_type = None;
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl_with_body ~use_self
    ~(params : (ident * Ptree.pty) list) ~(name : string) ~(body : Ptree.term) :
    Ptree.decl =
  let self_param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let params =
    List.map (fun (name, pty) -> (loc, Some (ident name), false, pty)) params
  in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = (if use_self then self_param :: params else params);
        ld_type = None;
        ld_def = Some body;
      };
    ]

let rec hexpr_size (h : Core_syntax.hexpr) : int =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> 1
  | HUn (_, inner) -> 1 + hexpr_size inner
  | HPred (_, hs) | HFunCall (_, hs) ->
      1 + List.fold_left (fun acc h -> acc + hexpr_size h) 0 hs
  | HBin (_, a, b) | HCmp (_, a, b) -> 1 + hexpr_size a + hexpr_size b

let rec vars_of_hexpr (acc : StringSet.t) (h : Core_syntax.hexpr) : StringSet.t =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ -> acc
  | HVar name | HPreK (name, _) -> StringSet.add name acc
  | HUn (_, inner) -> vars_of_hexpr acc inner
  | HPred (_, hs) | HFunCall (_, hs) -> List.fold_left vars_of_hexpr acc hs
  | HBin (_, a, b) | HCmp (_, a, b) -> vars_of_hexpr (vars_of_hexpr acc a) b

let port_view_to_vdecl (p : Why_runtime_view.port_view) : vdecl =
  { vname = p.port_name; vty = p.port_type }

let is_definition_postcondition (body : Core_syntax.hexpr) (ens : Core_syntax.hexpr) :
    bool =
  match ens.hexpr with
  | HCmp (REq, { hexpr = HVar "result"; _ }, rhs)
  | HCmp (REq, rhs, { hexpr = HVar "result"; _ }) ->
      Core_fo_simplifier.simplify rhs = Core_fo_simplifier.simplify body
  | _ -> false

let compile_pure_function_decl (f : pure_function_decl) : Ptree.decl =
  let env = { rec_name = ""; rec_vars = []; links = [] } in
  let binders =
    List.map
      (fun (v : vdecl) -> (loc, Some (ident v.vname), false, Some (default_pty v.vty)))
      f.function_params
  in
  let body_hexpr = Core_syntax_builders.hexpr_of_expr f.function_body in
  let drop_definition_contract =
    f.function_requires = []
    && List.for_all (is_definition_postcondition body_hexpr) f.function_ensures
  in
  let mk_post t = (loc, [ ({ pat_desc = Pvar (ident "result"); pat_loc = loc }, t) ]) in
  let spc =
    if drop_definition_contract then empty_spec ()
    else
      {
        Ptree.sp_pre = List.map (compile_local_fo_formula_term env) f.function_requires;
        sp_post =
          List.map
            (fun ens -> mk_post (compile_local_fo_formula_term env ens))
            f.function_ensures;
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      }
  in
  let fn =
    mk_expr
      (Efun
         ( binders,
           Some (default_pty f.function_return),
           { pat_desc = Pwild; pat_loc = loc },
           Ity.MaskVisible,
           spc,
           compile_expr env f.function_body ))
  in
  Ptree.Dlet (ident f.function_name, false, Expr.RKfunc, fn)
