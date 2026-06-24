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
open Why_compile_logic
open Why_compile_ptree_helpers

let compile_getter_decls env locals_and_outputs =
  let mk_getter (v : vdecl) =
    let field_name = v.vname in
    let getter_name = ident ("get_" ^ field_name) in
    let arg =
      (loc, Some (ident "self"), false, Some (PTtyapp (qid1 "vars", [])))
    in
    let body =
      compile_expr
        { env with rec_name = "self" }
        { expr = EVar field_name; loc = None }
    in
    let fn =
      mk_expr
        (Efun
           ( [ arg ],
             Some (default_pty v.vty),
             { pat_desc = Pwild; pat_loc = loc },
             Ity.MaskVisible,
             empty_spec (),
             body ))
    in
    Dlet (getter_name, false, Expr.RKnone, fn)
  in
  List.map mk_getter locals_and_outputs

let compile_logic_getter_decls env locals_and_outputs =
  let mk (v : vdecl) = logic_getter_decl ~env v.vname v.vty in
  logic_getter_decl ~env "st" (TCustom "state")
  :: List.map mk locals_and_outputs
