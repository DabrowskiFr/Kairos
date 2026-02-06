(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

let test_compile_term_var () : unit =
  let env : Support.env =
    { rec_name = "vars";
      rec_vars = ["x"];
      var_map = ["x", "x"];
      ghosts = [];
      links = [];
      pre_k = [];
      inst_map = [];
      inputs = [] }
  in
  let term = Why_compile_expr.compile_term env (Ast.mk_var "x") in
  let rendered = Support.string_of_term term in
  assert (rendered = "vars.x")

let test_progress_ltl_true_atom () : unit =
  let atom =
    Ast.FRel
      (Ast.HNow (Ast.mk_var "a"), Ast.REq, Ast.HNow (Ast.mk_bool true))
  in
  let formula = Ast.LG (Ast.LAtom atom) in
  let progressed =
    Automaton_core.progress_ltl [] [("a", true)] formula
  in
  let expected = Ast.LG (Ast.LAtom atom) in
  let rendered = Support.string_of_ltl progressed in
  let expected_rendered = Support.string_of_ltl expected in
  assert (rendered = expected_rendered)

let test_pre_k_infos_for_pre () : unit =
  let n : Ast.node =
    Ast.mk_node
      ~nname:"n"
      ~inputs:[ { Ast.vname = "x"; vty = Ast.TInt } ]
      ~outputs:[]
      ~assumes:
        [ Ast.LAtom
            (Ast.FRel
               (Ast.HPreK (Ast.mk_var "x", 1),
                Ast.REq,
                Ast.HNow (Ast.mk_int 0))) ]
      ~guarantees:[]
      ~instances:[]
      ~locals:[]
      ~states:[ "S" ]
      ~init_state:"S"
      ~trans:[]
  in
  let infos = Collect.build_pre_k_infos n in
  match infos with
  | [ (_h, info) ] ->
      assert (info.names = [ "__pre_k1_x" ])
  | _ -> assert false

let test_collect_empty_folds () : unit =
  let folds = Collect.collect_folds_from_specs ~fo:[] ~ltl:[] ~invariants_mon:[] in
  assert (folds = [])

let () =
  test_compile_term_var ();
  test_progress_ltl_true_atom ();
  test_pre_k_infos_for_pre ();
  test_collect_empty_folds ()
