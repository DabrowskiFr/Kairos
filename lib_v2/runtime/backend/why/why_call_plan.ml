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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

open Why3
open Ptree
open Ast
open Support
open Why_compile_expr

let index_of name lst =
  let rec loop i = function
    | [] -> None
    | x :: xs -> if x = name then Some i else loop (i + 1) xs
  in
  loop 0 lst

let build_call_asserts ~(env : env) ~(caller_runtime : Why_runtime_view.t) =
  let has_instance_calls = Why_runtime_view.has_instance_calls caller_runtime in
  let instance_invariant_terms ?(in_post = false) (inst_name : string)
      (summary : Why_runtime_view.callee_summary_view) =
    let node_name = summary.callee_node_name in
    let input_names = summary.callee_input_names in
    let pre_k_map = summary.callee_pre_k_map in
    let from_user =
      List.filter_map
        (fun inv ->
          let lhs = term_of_instance_var env inst_name node_name inv.inv_id in
          let rhs =
            compile_hexpr_instance ~in_post env inst_name node_name input_names pre_k_map
              inv.inv_expr
          in
          Some (term_eq lhs rhs))
        summary.callee_user_invariants
    in
    let from_state_rel =
      if has_instance_calls then []
      else
        List.filter_map
          (fun inv ->
            let st = term_of_instance_var env inst_name node_name "st" in
            let rhs = mk_term (Tident (qid1 inv.state)) in
            let cond = (if inv.is_eq then term_eq else term_neq) st rhs in
            let body =
              compile_fo_term_instance ~in_post env inst_name node_name input_names pre_k_map
                inv.formula
            in
            Some (term_implies cond body))
          summary.callee_state_invariants
    in
    from_user @ from_state_rel
  in
  fun (inst_name, access_name, _args, outs) ->
    match
      List.find_opt
        (fun (inst : Why_runtime_view.instance_view) -> inst.instance_name = inst_name)
        caller_runtime.instances
    with
    | None -> ([], [], [])
    | Some { Why_runtime_view.callee_node_name = node_name; _ } -> (
        match Why_runtime_view.find_callee_summary caller_runtime node_name with
        | None -> ([], [], [])
        | Some summary ->
            let inv_terms = instance_invariant_terms access_name summary in
            let output_exprs =
              let rec pair acc out_names outs =
                match (out_names, outs) with
                | callee_out :: rest_outs, _caller_out :: rest_callers ->
                    pair
                      (expr_of_instance_var env access_name node_name callee_out :: acc)
                      rest_outs rest_callers
                | _, _ -> List.rev acc
              in
              pair [] summary.callee_output_names outs
            in
            match summary.callee_delay_spec with
            | None -> ([], inv_terms, output_exprs)
            | Some (out_name, in_name) -> (
                let output_names = summary.callee_output_names in
                match index_of out_name output_names with
                | None -> ([], inv_terms, output_exprs)
                | Some out_idx ->
                    if out_idx >= List.length outs then ([], inv_terms, output_exprs)
                    else
                      let out_var = List.nth outs out_idx in
                      let pre_id = ident (Printf.sprintf "__call_pre_%s_%s" inst_name in_name) in
                      let pre_k_map = summary.callee_pre_k_map in
                      let pre_name =
                        List.find_map
                          (fun (_, info) ->
                            match (info.expr.iexpr, info.names) with
                            | IVar x, name :: _ when x = in_name -> Some name
                            | _ -> None)
                          pre_k_map
                      in
                      let pre_expr =
                        match pre_name with
                        | None -> expr_of_instance_var env access_name node_name in_name
                        | Some name -> expr_of_instance_var env access_name node_name name
                      in
                      let lhs = term_of_var env out_var in
                      let rhs = mk_term (Tident (qid1 pre_id.id_str)) in
                      ([ (pre_id, pre_expr) ], term_eq lhs rhs :: inv_terms, output_exprs)))
