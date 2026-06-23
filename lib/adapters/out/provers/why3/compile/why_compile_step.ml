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
open Core_syntax
open Why_compile_expr

let is_unit_expr (e : Ptree.expr) : bool = match e.expr_desc with Etuple [] -> true | _ -> false

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

let rec strip_term_attrs (term : Ptree.term) : Ptree.term =
  match term.term_desc with Tattr (_, inner) -> strip_term_attrs inner | _ -> term

let rec term_mentions_qid_name (name : string) (term : Ptree.term) : bool =
  let term = strip_term_attrs term in
  match term.term_desc with
  | Tident q -> String.equal (string_of_qid q) name
  | Tasref q -> String.equal (string_of_qid q) name
  | Tapply (fn, arg) -> term_mentions_qid_name name fn || term_mentions_qid_name name arg
  | Tbinnop (lhs, _, rhs) | Tinnfix (lhs, _, rhs) ->
      term_mentions_qid_name name lhs || term_mentions_qid_name name rhs
  | Tnot inner -> term_mentions_qid_name name inner
  | Tidapp (q, args) ->
      String.equal (string_of_qid q) name || List.exists (term_mentions_qid_name name) args
  | Tif (c, t_then, t_else) ->
      term_mentions_qid_name name c || term_mentions_qid_name name t_then
      || term_mentions_qid_name name t_else
  | Ttuple terms -> List.exists (term_mentions_qid_name name) terms
  | Tattr (_attr, inner) -> term_mentions_qid_name name inner
  | Tconst _ | Ttrue | Tfalse -> false
  | _ -> false

let rec compile_seq (env : env) (sticky_asserts : Ptree.term list)
    (lst : Why_runtime_view.runtime_action_view list) : Ptree.expr =
  let assert_terms terms = List.map (fun term -> mk_expr (Eassert (Expr.Assert, term))) terms in
  let qid_name_for_var x = x in
  let preserved_asserts_after_assign x =
    let qid_name = qid_name_for_var x in
    List.filter (fun term -> not (term_mentions_qid_name qid_name term)) sticky_asserts
  in
  let compile_assignment x rhs =
    let assign =
      if is_rec_var env x then
        mk_expr
          (Eassign
             [
               ( mk_expr (Eident (qid1 env.rec_name)),
                 Some (qid1 x),
                 rhs );
             ])
      else
        mk_expr (Eassign [ (mk_expr (Eident (qid1 x)), None, rhs) ])
    in
    let reassert = preserved_asserts_after_assign x |> assert_terms |> seq_exprs in
    seq_exprs [ assign; reassert ]
  in
  let compile_action (a : Why_runtime_view.runtime_action_view) : Ptree.expr =
    match a with
    | Why_runtime_view.ActionSkip -> mk_expr (Etuple [])
    | Why_runtime_view.ActionAssign (x, e) ->
        compile_assignment x (compile_expr env e)
    | Why_runtime_view.ActionAssert formula ->
        mk_expr (Eassert (Expr.Assert, compile_local_fo_formula_term env formula))
    | Why_runtime_view.ActionIf (c, tbr, fbr) ->
        let cond = compile_expr env c in
        begin
          match (tbr, fbr) with
          | ( [ Why_runtime_view.ActionAssign (x_then, e_then) ],
              [ Why_runtime_view.ActionAssign (x_else, e_else) ] )
            when String.equal x_then x_else ->
              let rhs =
                mk_expr
                  (Eif
                     ( cond,
                       compile_expr env e_then,
                       compile_expr env e_else ))
              in
              compile_assignment x_then rhs
          | _ ->
              let else_branch =
                if fbr = [] then explicit_noop () else compile_seq env sticky_asserts fbr
              in
              mk_expr (Eif (cond, compile_seq env sticky_asserts tbr, else_branch))
        end
    | Why_runtime_view.ActionWhile (cond, invariants, variant, body) ->
        let invariants =
          List.map (compile_local_fo_formula_term env) invariants
        in
        let variant =
          match variant with
          | None -> []
          | Some term -> [ (compile_term env term, None) ]
        in
        mk_expr
          (Ewhile
             ( compile_expr env cond,
               invariants,
               variant,
               compile_seq env sticky_asserts body ))
    | Why_runtime_view.ActionMatch (e, branches, default) ->
        let scrut = compile_expr env e in
        let branches =
          List.map
            (fun (ctor, body) ->
              let pat = { pat_desc = Papp (qid1 ctor, []); pat_loc = loc } in
              (pat, compile_seq env sticky_asserts body))
            branches
        in
        let branches =
          if default = [] then branches
          else
            branches @ [ ({ pat_desc = Pwild; pat_loc = loc }, compile_seq env sticky_asserts default) ]
        in
        mk_expr (Ematch (scrut, branches, []))
  in
  match lst with
  | [] -> mk_expr (Etuple [])
  | [ s ] -> compile_action s
  | s :: rest -> mk_expr (Esequence (compile_action s, compile_seq env sticky_asserts rest))

let compile_action_block (env : env) (sticky_asserts : Ptree.term list)
    (block : Why_runtime_view.action_block_view) : Ptree.expr =
  match block.block_kind with
  | Why_runtime_view.ActionUser -> compile_seq env sticky_asserts block.block_actions

let compile_transition_body (env : env) (sticky_asserts : Ptree.term list)
    (t : Why_runtime_view.runtime_transition_view) : Ptree.expr =
  let assign_dst =
    mk_expr
      (Eassign
         [
           ( mk_expr (Eident (qid1 env.rec_name)),
             Some (qid1 "st"),
             mk_expr (Eident (qid1 t.dst_state)) );
         ])
  in
  let block_exprs = List.map (compile_action_block env sticky_asserts) t.action_blocks in
  seq_exprs (block_exprs @ [ assign_dst ])
