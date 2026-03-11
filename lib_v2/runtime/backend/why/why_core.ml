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

let is_unit_expr (e : Ptree.expr) : bool = match e.expr_desc with Etuple [] -> true | _ -> false
let fresh_if_id =
  let c = ref 0 in
  fun () ->
    incr c;
    ident (Printf.sprintf "__if_cond_%d" !c)

let explicit_noop () =
  let noop = ident "__noop" in
  mk_expr
    (Elet
       ( noop,
         false,
         Expr.RKnone,
         mk_expr (Econst (Constant.int_const (Why3.BigInt.of_int 0))),
         mk_expr (Etuple []) ))

let seq_exprs (es : Ptree.expr list) : Ptree.expr =
  let es = List.filter (fun e -> not (is_unit_expr e)) es in
  match es with
  | [] -> mk_expr (Etuple [])
  | e :: rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) e rest

let rec compile_seq (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list ->
      (Ptree.ident * Ptree.expr) list * Ptree.term list * Ptree.expr list)
    (lst : Why_runtime_view.runtime_action_view list) : Ptree.expr =
  let compile_action (a : Why_runtime_view.runtime_action_view) : Ptree.expr =
    match a with
    | Why_runtime_view.ActionSkip -> mk_expr (Etuple [])
    | Why_runtime_view.ActionAssign (x, e) ->
        let is_ghost_local name =
          (String.length name >= 7 && String.sub name 0 7 = "__atom_")
          || (String.length name >= 5 && String.sub name 0 5 = "atom_")
          || (String.length name >= 6 && String.sub name 0 6 = "__aut_")
          || (String.length name >= 6 && String.sub name 0 6 = "__pre_")
        in
        let tgt = if is_rec_var env x then field env x else mk_expr (Eident (qid1 x)) in
        let assign = mk_expr (Eassign [ (tgt, None, compile_iexpr env e) ]) in
        if is_ghost_local x then mk_expr (Eghost assign) else assign
    | Why_runtime_view.ActionIf (c, tbr, fbr) ->
        let cond = compile_iexpr env c in
        let else_branch =
          if fbr = [] then explicit_noop () else compile_seq env call_asserts fbr
        in
        mk_expr (Eif (cond, compile_seq env call_asserts tbr, else_branch))
    | Why_runtime_view.ActionMatch (e, branches, default) ->
        let scrut = compile_iexpr env e in
        let branches =
          List.map
            (fun (ctor, body) ->
              let pat = { pat_desc = Papp (qid1 ctor, []); pat_loc = loc } in
              (pat, compile_seq env call_asserts body))
            branches
        in
        let branches =
          if default = [] then branches
          else
            branches
            @ [ ({ pat_desc = Pwild; pat_loc = loc }, compile_seq env call_asserts default) ]
        in
        mk_expr (Ematch (scrut, branches, []))
    | Why_runtime_view.ActionCall { call_instance = inst; call_args = args; call_outputs = outs } ->
        let node_name =
          match List.assoc_opt inst env.inst_map with
          | Some n -> n
          | None -> failwith ("unknown instance: " ^ inst)
        in
        let module_name = module_name_of_node node_name in
        let inst_var = field env inst in
        let inst_tmp = ident (Printf.sprintf "__call_inst_%s" inst) in
        let inst_tmp_expr = mk_expr (Eident (qid1 inst_tmp.id_str)) in
        let call_args = inst_tmp_expr :: List.map (compile_iexpr env) args in
        let call_expr = apply_expr (mk_expr (Eident (qdot (qid1 module_name) "step"))) call_args in
        let let_bindings, _asserts, output_exprs = call_asserts (inst, inst_tmp.id_str, args, outs) in
        let call_with_asserts =
          match outs with
          | [] -> call_expr
          | [ out_var ] ->
              let call_res = ident (Printf.sprintf "__call_res_%s" inst) in
              let tgt =
                if is_rec_var env out_var then field env out_var else mk_expr (Eident (qid1 out_var))
              in
              let assign = mk_expr (Eassign [ (tgt, None, mk_expr (Eident (qid1 call_res.id_str))) ]) in
              mk_expr (Elet (call_res, false, Expr.RKnone, call_expr, assign))
          | _ ->
              let output_assigns =
                List.map2
                  (fun x rhs ->
                    let tgt =
                      if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
                    in
                    mk_expr (Eassign [ (tgt, None, rhs) ]))
                  outs output_exprs
              in
              seq_exprs (call_expr :: output_assigns)
        in
        let wrap_let (id, pre_expr) acc = mk_expr (Elet (id, false, Expr.RKnone, pre_expr, acc)) in
        let with_tmp = mk_expr (Elet (inst_tmp, false, Expr.RKnone, inst_var, call_with_asserts)) in
        List.fold_right wrap_let let_bindings with_tmp
  in
  match lst with
  | [] -> mk_expr (Etuple [])
  | [ s ] -> compile_action s
  | s :: rest -> mk_expr (Esequence (compile_action s, compile_seq env call_asserts rest))

let compile_action_block (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list ->
      (Ptree.ident * Ptree.expr) list * Ptree.term list * Ptree.expr list)
    (block : Why_runtime_view.action_block_view) : Ptree.expr =
  match block.block_kind with
  | Why_runtime_view.ActionGhost -> mk_expr (Eghost (compile_seq env call_asserts block.block_actions))
  | Why_runtime_view.ActionUser | Why_runtime_view.ActionInstrumentation ->
      compile_seq env call_asserts block.block_actions

let compile_state_branch_ast (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list ->
      (Ptree.ident * Ptree.expr) list * Ptree.term list * Ptree.expr list)
    (st : ident) (trs : Why_runtime_view.runtime_transition_view list) : Ptree.reg_branch =
  let pat = { pat_desc = Papp (qid1 st, []); pat_loc = loc } in
  let rec chain (trs : Why_runtime_view.runtime_transition_view list) =
    match trs with
    | [] -> mk_expr (Etuple [])
    | (t : Why_runtime_view.runtime_transition_view) :: rest ->
        let guard = match t.guard with None -> mk_expr Etrue | Some g -> compile_iexpr env g in
        let assign_dst =
          mk_expr
            (Eassign
               [
                 ( field env "st",
                   None,
                   mk_expr (Eident (qid1 t.dst_state)) );
               ])
        in
        let block_exprs =
          List.map (compile_action_block env call_asserts) t.action_blocks
        in
        let body = seq_exprs (block_exprs @ [ assign_dst ]) in
        let trans_body = body in
        mk_expr (Eif (guard, trans_body, chain rest))
  in
  let body = chain trs in
  (pat, body)

let compile_state_branch (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list ->
      (Ptree.ident * Ptree.expr) list * Ptree.term list * Ptree.expr list)
    (st : ident) (trs : Why_runtime_view.runtime_transition_view list) : Ptree.reg_branch =
  compile_state_branch_ast env call_asserts st trs

let compile_transitions (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list ->
      (Ptree.ident * Ptree.expr) list * Ptree.term list * Ptree.expr list)
    (branches_view : Why_runtime_view.state_branch_view list) : Ptree.expr =
  let branches =
    List.map
      (fun (branch : Why_runtime_view.state_branch_view) ->
        compile_state_branch_ast env call_asserts branch.branch_state branch.branch_transitions)
      branches_view
  in
  mk_expr
    (Ematch
       ( field env "st",
         branches @ [ ({ pat_desc = Pwild; pat_loc = loc }, mk_expr (Etuple [])) ],
         [] ))

let compile_runtime_view (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list ->
      (Ptree.ident * Ptree.expr) list * Ptree.term list * Ptree.expr list)
    (runtime_view : Why_runtime_view.t) : Ptree.expr =
  compile_transitions env call_asserts runtime_view.state_branches
