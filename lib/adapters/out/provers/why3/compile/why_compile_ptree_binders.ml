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
open Why_compile_ptree_names

module StringSet = Why_compile_ptree_names.StringSet

let binder_expr ((_, id_opt, _, _) : Ptree.binder) : Ptree.expr =
  match id_opt with
  | Some id -> mk_expr (Eident (qid1 id.id_str))
  | None -> mk_expr (Etuple [])

let binder_term ((_, id_opt, _, _) : Ptree.binder) : Ptree.term option =
  Option.map (fun id -> mk_term (Tident (qid1 id.id_str))) id_opt

let param_of_binder ((bloc, id_opt, ghost, pty_opt) : Ptree.binder) :
    Ptree.param option =
  Option.map (fun pty -> (bloc, id_opt, ghost, pty)) pty_opt

let mark_unused_binders (used : StringSet.t) (binders : Ptree.binder list) :
    Ptree.binder list =
  let should_mark_unused id =
    (not (StringSet.mem id.id_str used))
    && not (String.starts_with ~prefix:"_" id.id_str)
  in
  List.map
    (fun (bloc, id_opt, ghost, pty_opt) ->
      match id_opt with
      | Some id when should_mark_unused id ->
          (bloc, Some (ident ("_" ^ id.id_str)), ghost, pty_opt)
      | _ -> (bloc, id_opt, ghost, pty_opt))
    binders

let helper_binders_without_unused_warnings (binders : Ptree.binder list)
    (spc : Ptree.spec) (body : Ptree.expr) : Ptree.binder list =
  let used = names_of_expr body (names_of_spec spc StringSet.empty) in
  mark_unused_binders used binders

let helper_binders_without_unused_parameters (binders : Ptree.binder list)
    (spc : Ptree.spec) (body : Ptree.expr) : Ptree.binder list =
  let used = names_of_expr body (names_of_spec spc StringSet.empty) in
  List.filter
    (fun (_, id_opt, _, _) ->
      match id_opt with
      | None -> true
      | Some id -> StringSet.mem id.id_str used)
    binders
