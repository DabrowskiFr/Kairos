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

let loc : Why3.Loc.position = Why3.Loc.dummy_position
let ident (s : string) : Ptree.ident = { id_str = s; id_ats = []; id_loc = loc }

let infix_ident (s : string) : Ptree.ident =
  { id_str = Ident.op_infix s; id_ats = []; id_loc = loc }

let qid1 (s : string) : Ptree.qualid =
  match String.split_on_char '.' s with
  | [] -> Ptree.Qident (ident s)
  | hd :: tl ->
      List.fold_left
        (fun acc part -> Ptree.Qdot (acc, ident part))
        (Ptree.Qident (ident hd)) tl

let qdot (q : Ptree.qualid) (s : string) : Ptree.qualid =
  Ptree.Qdot (q, ident s)

let mk_expr (desc : Ptree.expr_desc) : Ptree.expr =
  { Ptree.expr_desc = desc; expr_loc = loc }

let mk_term (desc : Ptree.term_desc) : Ptree.term =
  { Ptree.term_desc = desc; term_loc = loc }

let term_eq (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tinnfix (a, infix_ident "=", b))

let term_neq (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tinnfix (a, infix_ident "<>", b))

let term_bool_binop (op : Dterm.dbinop) (a : Ptree.term) (b : Ptree.term) :
    Ptree.term =
  mk_term (Tbinnop (a, op, b))

let term_implies (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  term_bool_binop Dterm.DTimplies a b

(* Use [Tat] so [Mlw_printer] emits [old t] directly. *)
let term_old (t : Ptree.term) : Ptree.term = mk_term (Tat (t, ident "old"))

let apply_expr (fn : Ptree.expr) (args : Ptree.expr list) : Ptree.expr =
  List.fold_left (fun acc arg -> mk_expr (Eapply (acc, arg))) fn args

let apply_term (fn : Ptree.term) (args : Ptree.term list) : Ptree.term =
  List.fold_left (fun acc arg -> mk_term (Tapply (acc, arg))) fn args
