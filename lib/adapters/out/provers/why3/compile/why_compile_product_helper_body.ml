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
open Why_compile_expr

let seq_exprs (exprs : Ptree.expr list) =
  let exprs =
    List.filter
      (fun expr -> match expr.expr_desc with Etuple [] -> false | _ -> true)
      exprs
  in
  match exprs with
  | [] -> mk_expr (Etuple [])
  | first :: rest ->
      List.fold_left
        (fun acc expr -> mk_expr (Esequence (acc, expr)))
        first rest

let helper_function helper_inputs spc helper_body =
  mk_expr
    (Efun
       ( helper_inputs,
         None,
         { pat_desc = Pwild; pat_loc = loc },
         Ity.MaskVisible,
         spc,
         helper_body ))

let individual_body ~env transition ~local_cuts =
  let local_cut_asserts =
    local_cuts
    |> List.map (fun term -> mk_expr (Eassert (Expr.Assert, term)))
  in
  seq_exprs
    (Why_compile_step.compile_transition_body env [] transition
    :: local_cut_asserts)

let grouped_body ~env transition ~post_call =
  let pre_snapshot_name = "__pre_snapshot" in
  let snapshot_expr =
    env.rec_vars
    |> List.map (fun field_name -> (qid1 field_name, field env field_name))
    |> fun fields -> mk_expr (Erecord fields)
  in
  let proof_assert =
    mk_expr (Eassert (Expr.Assert, post_call ~pre_snapshot_name))
  in
  let body =
    seq_exprs
      [
        Why_compile_step.compile_transition_body env [] transition;
        proof_assert;
      ]
  in
  mk_expr
    (Elet (ident pre_snapshot_name, true, Expr.RKnone, snapshot_expr, body))
