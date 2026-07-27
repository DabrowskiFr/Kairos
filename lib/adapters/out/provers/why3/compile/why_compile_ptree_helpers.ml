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


(** Shared constructors and structural operations over Why3 [Ptree]. *)

open Why3
open Ptree
open Why_compile_expr

let empty_spec () = Why3.Ptree_helpers.empty_spec

let import_module name =
  Why3.Ptree_helpers.use ~loc ~import:false (String.split_on_char '.' name)

let term_and (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tbinnop (a, Dterm.DTand, b))

let term_and_list (terms : Ptree.term list) : Ptree.term =
  match terms with
  | [] -> mk_term Ttrue
  | [ term ] -> term
  | first :: rest -> List.fold_left term_and first rest

let term_or (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tbinnop (a, Dterm.DTor, b))

let term_or_list (terms : Ptree.term list) : Ptree.term =
  match terms with
  | [] -> mk_term Tfalse
  | [ term ] -> term
  | first :: rest -> List.fold_left term_or first rest

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

let binder_term ((_, id_opt, _, _) : Ptree.binder) : Ptree.term option =
  Option.map (fun id -> mk_term (Tident (qid1 id.id_str))) id_opt

let param_of_binder ((bloc, id_opt, ghost, pty_opt) : Ptree.binder) :
    Ptree.param option =
  Option.map (fun pty -> (bloc, id_opt, ghost, pty)) pty_opt

let binders_used_by (used : used_inputs) (binders : Ptree.binder list) :
    Ptree.binder list =
  List.filter
    (fun (_, id_opt, _, _) ->
      match id_opt with
      | None -> true
      | Some id -> StringSet.mem id.id_str used)
    binders
