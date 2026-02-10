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

let rec compile_seq (env:env)
  (call_asserts:(ident * iexpr list * ident list) -> (Ptree.ident * Ptree.expr) list * Ptree.term list)
  (lst:stmt list) : Ptree.expr =
  let compile_stmt (s:stmt) : Ptree.expr =
    match s.stmt with
    | SSkip -> mk_expr (Etuple [])
    | SAssign (x,e) ->
        let is_ghost_local name =
          (String.length name >= 7 && String.sub name 0 7 = "__atom_")
          || (String.length name >= 5 && String.sub name 0 5 = "atom_")
          || (String.length name >= 6 && String.sub name 0 6 = "__mon_")
          || (String.length name >= 6 && String.sub name 0 6 = "__pre_")
        in
        let tgt =
          if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
        in
        let assign = mk_expr (Eassign [(tgt, None, compile_iexpr env e)]) in
        if is_ghost_local x then mk_expr (Eghost assign) else assign
    | SIf (c, tbr, fbr) ->
        mk_expr (Eif (compile_iexpr env c, compile_seq env call_asserts tbr, compile_seq env call_asserts fbr))
    | SMatch (e, branches, default) ->
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
          else branches @ [({pat_desc=Pwild; pat_loc=loc}, compile_seq env call_asserts default)]
        in
        mk_expr (Ematch (scrut, branches, []))
    | SCall (inst, args, outs) ->
        let node_name =
          match List.assoc_opt inst env.inst_map with
          | Some n -> n
          | None -> failwith ("unknown instance: " ^ inst)
        in
        let module_name = module_name_of_node node_name in
        let inst_var = field env inst in
        let call_args = inst_var :: List.map (compile_iexpr env) args in
        let call_expr =
          apply_expr (mk_expr (Eident (qdot (qid1 module_name) "step"))) call_args
        in
        let call_expr =
          begin match outs with
        | [] ->
            let tmp = ident "__call" in
            mk_expr (Elet (tmp, false, Expr.RKnone, call_expr, mk_expr (Etuple [])))
        | [x] ->
            let tgt =
              if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
            in
            mk_expr (Eassign [(tgt, None, call_expr)])
        | xs ->
            let tmp_ids = List.mapi (fun i _ -> ident (Printf.sprintf "__call%d" i)) xs in
            let pat =
              { pat_desc = Ptuple (List.map (fun id -> { pat_desc = Pvar id; pat_loc = loc }) tmp_ids);
                pat_loc = loc }
            in
            let assigns =
              List.map2
                (fun x id ->
                   let tgt =
                     if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
                   in
                   mk_expr (Eassign [(tgt, None, mk_expr (Eident (Ptree.Qident id))) ]))
                xs tmp_ids
            in
            let body =
              match assigns with
              | [] -> mk_expr (Etuple [])
              | [a] -> a
              | a::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) a rest
            in
            mk_expr (Ematch (call_expr, [(pat, body)], []))
          end
        in
        let let_bindings, _asserts = call_asserts (inst, args, outs) in
        let call_with_asserts = call_expr in
        let wrap_let (id, pre_expr) acc =
          mk_expr (Elet (id, false, Expr.RKnone, pre_expr, acc))
        in
        List.fold_right wrap_let let_bindings call_with_asserts
  in
  match lst with
  | [] -> mk_expr (Etuple [])
  | [s] -> compile_stmt s
  | s::rest ->
      mk_expr (Esequence (compile_stmt s, compile_seq env call_asserts rest))

let is_unit_expr (e:Ptree.expr) : bool =
  match e.expr_desc with
  | Etuple [] -> true
  | _ -> false

let seq_exprs (es:Ptree.expr list) : Ptree.expr =
  let es = List.filter (fun e -> not (is_unit_expr e)) es in
  match es with
  | [] -> mk_expr (Etuple [])
  | e :: rest ->
      List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) e rest

let compile_state_branch_ast (env:env)
  (call_asserts:(ident * iexpr list * ident list) -> (Ptree.ident * Ptree.expr) list * Ptree.term list)
  (st:ident)
  (trs:transition list) : Ptree.reg_branch =
  let st_expr = field env "st" in
  let pat = { pat_desc = Papp (qid1 st, []); pat_loc = loc } in
  let rec chain = function
    | [] -> mk_expr (Etuple [])
    | t::rest ->
        let guard =
          match t.guard with
          | None -> mk_expr Etrue
          | Some g -> compile_iexpr env g
        in
        let assign_dst = mk_expr (Etuple []) in
        let ghost_expr =
          match t.attrs.ghost with
          | [] -> mk_expr (Etuple [])
          | _ -> mk_expr (Eghost (compile_seq env call_asserts (t.attrs.ghost)))
        in
        let user_expr = compile_seq env call_asserts (t.body) in
        let mon_expr = compile_seq env call_asserts (t.attrs.monitor) in
        let body = seq_exprs [ghost_expr; user_expr; mon_expr; assign_dst] in
        let trans_body = body in
        mk_expr (Eif (guard, trans_body, chain rest))
  in
  let body = chain trs in
  (pat, body)

let compile_state_branch (env:env)
  (call_asserts:(ident * iexpr list * ident list) -> (Ptree.ident * Ptree.expr) list * Ptree.term list)
  (st:ident)
  (trs:Ast.transition list) : Ptree.reg_branch =
  let trs = trs in
  compile_state_branch_ast env call_asserts st trs

let compile_transitions (env:env)
  (call_asserts:(ident * iexpr list * ident list) -> (Ptree.ident * Ptree.expr) list * Ptree.term list)
  (ts:Ast.transition list)
  : Ptree.expr =
  let ts = ts in
  let by_state =
    List.fold_left
      (fun m t ->
         let src = t.src in
         let prev = Option.value ~default:[] (List.assoc_opt src m) in
         (src, prev @ [t]) :: List.remove_assoc src m)
      [] ts
  in
  let branches = List.map (fun (st,trs) -> compile_state_branch_ast env call_asserts st trs) by_state in
  mk_expr (Ematch (field env "st", branches @ [({pat_desc=Pwild; pat_loc=loc}, mk_expr (Etuple []))], []))
