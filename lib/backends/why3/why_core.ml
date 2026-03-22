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

let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tbinop (a, Dterm.DTand, b))

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

let empty_spec () : Ptree.spec =
  {
    Ptree.sp_pre = [];
    sp_post = [];
    sp_xpost = [];
    sp_reads = [];
    sp_writes = [];
    sp_alias = [];
    sp_variant = [];
    sp_checkrw = false;
    sp_diverge = false;
    sp_partial = false;
  }

let rec strip_term_attrs (term : Ptree.term) : Ptree.term =
  match term.term_desc with Tattr (_, inner) -> strip_term_attrs inner | _ -> term

let rec term_mentions_qid_name (name : string) (term : Ptree.term) : bool =
  let term = strip_term_attrs term in
  match term.term_desc with
  | Tident q -> String.equal (string_of_qid q) name
  | Tapply (fn, arg) -> term_mentions_qid_name name fn || term_mentions_qid_name name arg
  | Tbinop (lhs, _, rhs) | Tinnfix (lhs, _, rhs) ->
      term_mentions_qid_name name lhs || term_mentions_qid_name name rhs
  | Tnot inner -> term_mentions_qid_name name inner
  | Tidapp (_q, args) -> List.exists (term_mentions_qid_name name) args
  | Tif (c, t_then, t_else) ->
      term_mentions_qid_name name c || term_mentions_qid_name name t_then
      || term_mentions_qid_name name t_else
  | Ttuple terms -> List.exists (term_mentions_qid_name name) terms
  | Tattr (_attr, inner) -> term_mentions_qid_name name inner
  | Tconst _ | Ttrue | Tfalse -> false
  | _ -> false

let rec compile_seq (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (sticky_asserts : Ptree.term list)
    (lst : Why_runtime_view.runtime_action_view list) : Ptree.expr =
  let assert_terms terms = List.map (fun term -> mk_expr (Eassert (Expr.Assert, term))) terms in
  let qid_name_for_var x =
    if is_rec_var env x then string_of_qid (qdot (qid1 env.rec_name) (rec_var_name env x)) else x
  in
  let preserved_asserts_after_assign x =
    let qid_name = qid_name_for_var x in
    List.filter (fun term -> not (term_mentions_qid_name qid_name term)) sticky_asserts
  in
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
        let assign = if is_ghost_local x then mk_expr (Eghost assign) else assign in
        let reassert = preserved_asserts_after_assign x |> assert_terms |> seq_exprs in
        seq_exprs [ assign; reassert ]
    | Why_runtime_view.ActionIf (c, tbr, fbr) ->
        let cond = compile_iexpr env c in
        let else_branch =
          if fbr = [] then explicit_noop () else compile_seq env call_asserts sticky_asserts fbr
        in
        mk_expr (Eif (cond, compile_seq env call_asserts sticky_asserts tbr, else_branch))
    | Why_runtime_view.ActionMatch (e, branches, default) ->
        let scrut = compile_iexpr env e in
        let branches =
          List.map
            (fun (ctor, body) ->
              let pat = { pat_desc = Papp (qid1 ctor, []); pat_loc = loc } in
              (pat, compile_seq env call_asserts sticky_asserts body))
            branches
        in
        let branches =
          if default = [] then branches
          else
            branches
            @ [ ({ pat_desc = Pwild; pat_loc = loc }, compile_seq env call_asserts sticky_asserts default) ]
        in
        mk_expr (Ematch (scrut, branches, []))
    | Why_runtime_view.ActionCall { call_instance = inst; call_args = args; call_outputs = outs } ->
        let node_name =
          match List.assoc_opt inst env.inst_map with
          | Some n -> n
          | None -> failwith ("unknown instance: " ^ inst)
        in
        let inst_var = field env inst in
        let inst_tmp = ident (Printf.sprintf "__call_inst_%s" inst) in
        let call_plan = call_asserts (inst, inst_tmp.id_str, args, outs) in
        let with_tmp_body =
          match call_plan with
          | None -> mk_expr (Etuple [])
          | Some plan ->
              let any_spec = { (empty_spec ()) with sp_post = plan.any_post } in
              let any_expr =
                mk_expr
                  (Eany
                     ( [],
                       Expr.RKnone,
                       plan.any_return_pty,
                       plan.any_pattern,
                       Ity.MaskVisible,
                       any_spec ))
              in
              let pre_assert_exprs =
                List.map (fun term -> mk_expr (Eassert (Expr.Assert, term))) plan.pre_asserts
              in
              let bind_outputs body =
                List.fold_right
                  (fun (out_id, (port : Why_runtime_view.port_view)) acc ->
                    let out_pty =
                      Some (default_pty port.port_type)
                    in
                    let out_post_terms =
                      match List.assoc_opt out_id plan.output_post_terms with
                      | None | Some [] -> []
                      | Some (first :: rest) ->
                          let body = List.fold_left term_and first rest in
                          [ (loc, [ ({ pat_desc = Pvar out_id; pat_loc = loc }, body) ]) ]
                    in
                    let any_out =
                      mk_expr
                        (Eany
                           ( [],
                             Expr.RKnone,
                             out_pty,
                             { pat_desc = Pvar out_id; pat_loc = loc },
                             Ity.MaskVisible,
                             { (empty_spec ()) with sp_post = out_post_terms } ))
                    in
                    mk_expr (Elet (out_id, false, Expr.RKnone, any_out, acc)))
                  (List.combine plan.output_ids plan.callee_outputs)
                  body
              in
              let inst_assign =
                mk_expr
                  (Eassign
                     [
                       ( field env inst,
                         None,
                         mk_expr (Eident (qid1 plan.next_instance_id.id_str)) );
                     ])
              in
              let output_assigns =
                let rec build_with_ids acc caller_outs output_ids =
                  match (caller_outs, output_ids) with
                  | out_var :: caller_outs, out_id :: output_ids ->
                      let tgt =
                        if is_rec_var env out_var then field env out_var else mk_expr (Eident (qid1 out_var))
                      in
                      let assign =
                        mk_expr (Eassign [ (tgt, None, mk_expr (Eident (qid1 out_id.id_str))) ])
                      in
                      build_with_ids (assign :: acc) caller_outs output_ids
                  | _, _ -> List.rev acc
                in
                build_with_ids [] outs plan.output_ids
              in
              let assigns = seq_exprs (pre_assert_exprs @ (inst_assign :: output_assigns)) in
              bind_outputs (mk_expr (Elet (plan.next_instance_id, false, Expr.RKnone, any_expr, assigns)))
        in
        let wrap_let (id, pre_expr) acc = mk_expr (Elet (id, false, Expr.RKnone, pre_expr, acc)) in
        let with_tmp = mk_expr (Elet (inst_tmp, false, Expr.RKnone, inst_var, with_tmp_body)) in
        match call_plan with
        | None -> with_tmp
        | Some plan -> List.fold_right wrap_let plan.let_bindings with_tmp
  in
  match lst with
  | [] -> mk_expr (Etuple [])
  | [ s ] -> compile_action s
  | s :: rest -> mk_expr (Esequence (compile_action s, compile_seq env call_asserts sticky_asserts rest))

let compile_action_block (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (sticky_asserts : Ptree.term list)
    (block : Why_runtime_view.action_block_view) : Ptree.expr =
  match block.block_kind with
  | Why_runtime_view.ActionGhost ->
      mk_expr (Eghost (compile_seq env call_asserts sticky_asserts block.block_actions))
  | Why_runtime_view.ActionUser | Why_runtime_view.ActionInstrumentation ->
      compile_seq env call_asserts sticky_asserts block.block_actions

let compile_transition_body (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (sticky_asserts : Ptree.term list)
    (t : Why_runtime_view.runtime_transition_view) : Ptree.expr =
  let assign_dst =
    mk_expr
      (Eassign
         [
           (field env "st", None, mk_expr (Eident (qid1 t.dst_state)));
         ])
  in
  let block_exprs =
    List.map (compile_action_block env call_asserts sticky_asserts) t.action_blocks
  in
  seq_exprs (block_exprs @ [ assign_dst ])

let compile_state_body (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (branch_entry_asserts : (Ast.ident * Ptree.term list) list)
    (branch_sticky_asserts : (Ast.ident * Ptree.term list) list)
    (dst_inv_asserts : (Ast.ident * Ptree.term list) list)
    (st : ident) (trs : Why_runtime_view.runtime_transition_view list) : Ptree.expr =
  let entry_asserts =
    match List.assoc_opt st branch_entry_asserts with
    | None -> []
    | Some terms -> List.map (fun term -> mk_expr (Eassert (Expr.Assert, term))) terms
  in
  let sticky_asserts =
    match List.assoc_opt st branch_sticky_asserts with
    | None -> []
    | Some terms -> List.map (fun term -> mk_expr (Eassert (Expr.Assert, term))) terms
  in
  let local_assert_terms =
    List.map
      (function { expr_desc = Eassert (_, term); _ } -> term | _ -> assert false)
      sticky_asserts
  in
  let rec chain (trs : Why_runtime_view.runtime_transition_view list) =
    match trs with
    | [] -> mk_expr (Etuple [])
    | (t : Why_runtime_view.runtime_transition_view) :: rest ->
        let guard = match t.guard with None -> mk_expr Etrue | Some g -> compile_iexpr env g in
        let trans_body = compile_transition_body env call_asserts local_assert_terms t in
        mk_expr (Eif (guard, trans_body, chain rest))
  in
  seq_exprs (entry_asserts @ sticky_asserts @ [ chain trs ])

let compile_state_branch_ast (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (branch_entry_asserts : (Ast.ident * Ptree.term list) list)
    (branch_sticky_asserts : (Ast.ident * Ptree.term list) list)
    (dst_inv_asserts : (Ast.ident * Ptree.term list) list)
    (st : ident) (trs : Why_runtime_view.runtime_transition_view list) : Ptree.reg_branch =
  let pat = { pat_desc = Papp (qid1 st, []); pat_loc = loc } in
  let body = compile_state_body env call_asserts branch_entry_asserts branch_sticky_asserts dst_inv_asserts st trs in
  (pat, body)

let compile_state_branch (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (branch_entry_asserts : (Ast.ident * Ptree.term list) list)
    (branch_sticky_asserts : (Ast.ident * Ptree.term list) list)
    (dst_inv_asserts : (Ast.ident * Ptree.term list) list)
    (st : ident) (trs : Why_runtime_view.runtime_transition_view list) : Ptree.reg_branch =
  compile_state_branch_ast env call_asserts branch_entry_asserts branch_sticky_asserts dst_inv_asserts st trs

let compile_transitions (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (branch_entry_asserts : (Ast.ident * Ptree.term list) list)
    (branch_sticky_asserts : (Ast.ident * Ptree.term list) list)
    (dst_inv_asserts : (Ast.ident * Ptree.term list) list)
    (branches_view : Why_runtime_view.state_branch_view list) : Ptree.expr =
  let branches =
    List.map
      (fun (branch : Why_runtime_view.state_branch_view) ->
        compile_state_branch_ast env call_asserts branch_entry_asserts branch_sticky_asserts
          dst_inv_asserts
          branch.branch_state
          branch.branch_transitions)
      branches_view
  in
  mk_expr
    (Ematch
       ( field env "st",
         branches @ [ ({ pat_desc = Pwild; pat_loc = loc }, mk_expr (Etuple [])) ],
         [] ))

let compile_runtime_view (env : env)
    (call_asserts :
      ident * ident * iexpr list * ident list -> Why_call_plan.compiled_call_plan option)
    (branch_entry_asserts : (Ast.ident * Ptree.term list) list)
    (branch_sticky_asserts : (Ast.ident * Ptree.term list) list)
    (dst_inv_asserts : (Ast.ident * Ptree.term list) list)
    (runtime_view : Why_runtime_view.t) : Ptree.expr =
  compile_transitions env call_asserts branch_entry_asserts branch_sticky_asserts dst_inv_asserts
    runtime_view.state_branches
