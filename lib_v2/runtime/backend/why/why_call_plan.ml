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

type compiled_call_plan = {
  let_bindings : (Why3.Ptree.ident * Why3.Ptree.expr) list;
  pre_asserts : Why3.Ptree.term list;
  output_post_terms : (Why3.Ptree.ident * Why3.Ptree.term list) list;
  any_pattern : Why3.Ptree.pattern;
  any_return_pty : Why3.Ptree.pty option;
  any_post : (Why3.Loc.position * (Why3.Ptree.pattern * Why3.Ptree.term) list) list;
  next_instance_id : Why3.Ptree.ident;
  output_ids : Why3.Ptree.ident list;
  callee_outputs : Why_runtime_view.port_view list;
  callee_output_names : Ast.ident list;
}

type call_fact_phase =
  | EntryPhase
  | PostPhase

let index_of name lst =
  let rec loop i = function
    | [] -> None
    | x :: xs -> if x = name then Some i else loop (i + 1) xs
  in
  loop 0 lst

let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tbinop (a, Dterm.DTand, b))

let port_names (ports : Why_runtime_view.port_view list) =
  List.map (fun (port : Why_runtime_view.port_view) -> port.port_name) ports

let combine_prefix xs ys =
  let rec aux acc xs ys =
    match (xs, ys) with
    | x :: xs, y :: ys -> aux ((x, y) :: acc) xs ys
    | _, _ -> List.rev acc
  in
  aux [] xs ys

let current_call_lookup ~(env : env) ~(node_name : Ast.ident) ~(access_name : Ast.ident)
    ~(next_instance_name : Ast.ident) ~(input_bindings : (Ast.ident * Ast.iexpr) list)
    ~(output_bindings : (Ast.ident * Ast.ident) list)
    (name : Ast.ident) : Ptree.term =
  match List.assoc_opt name input_bindings with
  | Some actual -> compile_term env actual
  | None -> (
      match List.assoc_opt name output_bindings with
      | Some out_id -> mk_term (Tident (qid1 out_id))
      | None -> term_of_instance_var env next_instance_name node_name name)

let previous_call_lookup ~(env : env) ~(node_name : Ast.ident) ~(access_name : Ast.ident)
    ~(input_bindings : (Ast.ident * Ast.iexpr) list) (name : Ast.ident) : Ptree.term =
  match List.assoc_opt name input_bindings with
  | Some actual -> term_old (compile_term env actual)
  | None -> term_old (term_of_instance_var env access_name node_name name)

let rec compile_call_iexpr_term lookup (e : Ast.iexpr) : Ptree.term =
  match e.iexpr with
  | ILitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_term (if b then Ttrue else Tfalse)
  | IVar x -> lookup x
  | IPar inner -> compile_call_iexpr_term lookup inner
  | IUn (Neg, inner) -> mk_term (Tidapp (qid1 "(-)", [ compile_call_iexpr_term lookup inner ]))
  | IUn (Not, inner) -> mk_term (Tnot (compile_call_iexpr_term lookup inner))
  | IBin (op, a, b) ->
      mk_term
        (Tinnfix
           (compile_call_iexpr_term lookup a, infix_ident (binop_id op), compile_call_iexpr_term lookup b))

let compile_call_hexpr_term lookup (summary : Why_runtime_view.callee_summary_view) (h : Ast.hexpr) :
    Ptree.term =
  match h with
  | HNow e -> compile_call_iexpr_term lookup e
  | HPreK (_, _) -> (
      match Kernel_guided_contract.latest_slot_name_for_hexpr summary.callee_contract h with
      | None -> failwith "pre_k not registered (call summary contract)"
      | Some name -> lookup name)

let rec compile_call_fo_term lookup (summary : Why_runtime_view.callee_summary_view) (f : Ast.fo) :
    Ptree.term =
  match f with
  | FTrue -> mk_term Ttrue
  | FFalse -> mk_term Tfalse
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_call_hexpr_term lookup summary h1,
             infix_ident (relop_id r),
             compile_call_hexpr_term lookup summary h2 ))
  | FPred (id, hs) ->
      mk_term (Tidapp (qid1 id, List.map (compile_call_hexpr_term lookup summary) hs))
  | FNot a -> mk_term (Tnot (compile_call_fo_term lookup summary a))
  | FAnd (a, b) ->
      mk_term
        (Tbinop
           (compile_call_fo_term lookup summary a, Dterm.DTand, compile_call_fo_term lookup summary b))
  | FOr (a, b) ->
      mk_term
        (Tbinop
           (compile_call_fo_term lookup summary a, Dterm.DTor, compile_call_fo_term lookup summary b))
  | FImp (a, b) ->
      mk_term
        (Tbinop
           ( compile_call_fo_term lookup summary a,
             Dterm.DTimplies,
             compile_call_fo_term lookup summary b ))

let compile_call_fact_term ~(env : env) ~(summary : Why_runtime_view.callee_summary_view)
    ~(phase : call_fact_phase) ~(access_name : Ast.ident) ~(next_instance_name : Ast.ident)
    ~(input_bindings : (Ast.ident * Ast.iexpr) list)
    ~(output_bindings : (Ast.ident * Ast.ident) list) (fact : Product_kernel_ir.call_fact_ir) :
    Ptree.term option =
  let current_instance_name =
    match phase with
    | EntryPhase -> access_name
    | PostPhase -> next_instance_name
  in
  let output_bindings = if phase = EntryPhase then [] else output_bindings in
  let current_lookup =
    current_call_lookup ~env ~node_name:summary.callee_node_name ~access_name
      ~next_instance_name:current_instance_name
      ~input_bindings ~output_bindings
  in
  let previous_lookup =
    previous_call_lookup ~env ~node_name:summary.callee_node_name ~access_name ~input_bindings
  in
  let lookup =
    match fact.fact.time with
    | Product_kernel_ir.CurrentTick -> current_lookup
    | Product_kernel_ir.PreviousTick -> previous_lookup
  in
  match fact.fact.desc with
  | Product_kernel_ir.FactProgramState state_name ->
      Some
        (term_eq
           (lookup "st")
           (mk_term (Tident (qid1 (instance_state_ctor_name summary.callee_node_name state_name)))))
  | Product_kernel_ir.FactFormula fo -> Some (compile_call_fo_term lookup summary fo)
  | Product_kernel_ir.FactGuaranteeState _ -> None
  | Product_kernel_ir.FactFalse -> Some (mk_term Tfalse)

let build_call_asserts ~(env : env) ~(caller_runtime : Why_runtime_view.t) =
  let has_instance_calls = Why_runtime_view.has_instance_calls caller_runtime in
  let caller_kernel_relations =
    match caller_runtime.kernel_contract with
    | Some contract -> contract.instance_relations
    | None -> []
  in
  let instance_invariant_terms ?(in_post = false) (inst_name : string)
      (summary : Why_runtime_view.callee_summary_view) =
    let node_name = summary.callee_node_name in
    let input_names = summary.callee_input_names in
    let contract = summary.callee_contract in
    let from_user =
      List.filter_map
        (fun inv ->
          let lhs = term_of_instance_var env inst_name node_name inv.inv_id in
          let rhs =
            compile_hexpr_instance_contract ~in_post env inst_name node_name input_names contract
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
            let rhs = mk_term (Tident (qid1 (instance_state_ctor_name node_name inv.state))) in
            let cond = (if inv.is_eq then term_eq else term_neq) st rhs in
            let body =
              compile_fo_term_instance_contract ~in_post env inst_name node_name input_names
                contract
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
    | None -> None
    | Some { Why_runtime_view.callee_node_name = node_name; _ } -> (
        match Why_runtime_view.find_callee_summary caller_runtime node_name with
        | None -> None
        | Some summary ->
            let next_instance_id = ident (Printf.sprintf "__call_next_%s" inst_name) in
            let inv_terms = instance_invariant_terms access_name summary in
            let output_ids =
              List.mapi
                (fun idx _ -> ident (Printf.sprintf "__call_out_%s_%d" inst_name idx))
                summary.callee_outputs
            in
            let input_bindings = combine_prefix (port_names summary.callee_inputs) _args in
            let output_bindings =
              combine_prefix summary.callee_output_names (List.map (fun id -> id.id_str) output_ids)
            in
            let delay_output_post_terms =
              caller_kernel_relations
              |> List.filter_map (function
                   | Product_kernel_ir.InstanceDelayCallerPreLink
                       { caller_output; caller_pre_name }
                     when List.mem caller_output outs ->
                       begin
                         match index_of caller_output outs with
                         | None -> None
                         | Some out_idx ->
                             if out_idx >= List.length output_ids then None
                             else
                               let out_id = List.nth output_ids out_idx in
                               Some
                                 ( out_id,
                                   term_eq
                                     (mk_term (Tident (qid1 out_id.id_str)))
                                     (term_of_var env caller_pre_name) )
                       end
                   | _ -> None)
            in
            let let_bindings, pre_asserts = ([], inv_terms) in
            let output_post_terms =
              delay_output_post_terms
              |> List.map (fun (out_id, term) -> (out_id, [ term ]))
            in
            let any_return_pty =
              Some (Ptree.PTtyapp (qid1 (instance_vars_type_name node_name), []))
            in
            let any_pattern = { pat_desc = Pvar next_instance_id; pat_loc = loc } in
            let any_post =
              let tick_posts =
                match summary.callee_tick_summary with
                | None -> []
                | Some tick_summary ->
                    tick_summary.cases
                    |> List.filter_map (fun (case : Product_kernel_ir.callee_summary_case_ir) ->
                           let premise =
                             case.entry_facts
                             |> List.filter_map
                                  (compile_call_fact_term ~env ~summary ~phase:EntryPhase ~access_name
                                     ~next_instance_name:next_instance_id.id_str ~input_bindings
                                     ~output_bindings)
                           in
                           let conclusion =
                             (case.transition_facts @ case.exported_post_facts)
                             |> List.filter_map
                                  (compile_call_fact_term ~env ~summary ~phase:PostPhase ~access_name
                                     ~next_instance_name:next_instance_id.id_str ~input_bindings
                                     ~output_bindings)
                           in
                           match conclusion with
                           | [] -> None
                           | first :: rest ->
                               let concl = List.fold_left term_and first rest in
                               let body =
                                 match premise with
                                 | [] -> concl
                                 | first_pre :: rest_pre ->
                                     term_implies (List.fold_left term_and first_pre rest_pre) concl
                               in
                               Some
                                 ( loc,
                                   [
                                     ( { pat_desc = Pvar next_instance_id; pat_loc = loc },
                                       body );
                                   ] ))
              in
              tick_posts
            in
            Some
              {
                let_bindings;
                pre_asserts;
                output_post_terms;
                any_pattern;
                any_return_pty;
                any_post;
                next_instance_id;
                output_ids;
                callee_outputs = summary.callee_outputs;
                callee_output_names = summary.callee_output_names;
              })
