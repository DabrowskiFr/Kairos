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
open Why_compile_logic
open Why_compile_ptree_helpers

type context = {
  env : Why_compile_expr.env;
  inputs : Ptree.binder list;
  runtime_view : Why_runtime_view.t;
}

let build ctx =
  let goals = ctx.runtime_view.init_invariant_goals in
  if goals = [] then []
  else
    let init_guard =
      term_eq (term_of_var ctx.env "st")
        (mk_term (Tident (qid1 ctx.runtime_view.init_control_state)))
    in
    let vars_only =
      match ctx.inputs with vars_param :: _ -> [ vars_param ] | [] -> ctx.inputs
    in
    List.mapi
      (fun i (f : Ir.summary_formula) ->
        let base = compile_local_fo_formula_term ctx.env f.logic in
        let coherent_initial_state = term_and init_guard base in
        let quantified =
          mk_term
            (Tquant (Dterm.DTexists, vars_only, [], coherent_initial_state))
        in
        Dprop
          ( Decl.Pgoal,
            ident (Printf.sprintf "coherency_goal_%d" (i + 1)),
            quantified ))
      goals
