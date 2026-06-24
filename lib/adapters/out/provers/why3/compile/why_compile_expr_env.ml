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
open Why_compile_expr_primitives

type env = {
  rec_name : string;
  rec_vars : string list;
  links : (hexpr * ident) list;
}

let field (env : env) (name : ident) : Ptree.expr =
  mk_expr (Eidapp (qid1 name, [ mk_expr (Eident (qid1 env.rec_name)) ]))

let is_rec_var (env : env) (x : ident) : bool =
  List.exists (( = ) x) env.rec_vars

let term_var (env : env) (x : ident) : Ptree.term_desc =
  if is_rec_var env x then
    Tidapp (qid1 x, [ mk_term (Tident (qid1 env.rec_name)) ])
  else Tident (qid1 x)

let find_link (env : env) (h : hexpr) : ident option =
  List.find_map (fun (h', id) -> if h' = h then Some id else None) env.links

let term_of_var (env : env) (name : ident) : Ptree.term =
  mk_term (term_var env name)
