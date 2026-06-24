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

let empty_spec () : Ptree.spec =
  {
    Ptree.sp_pre = [];
    sp_post = [];
    sp_xpost = [];
    sp_reads = [];
    sp_writes = [];
    sp_alias = [];
    sp_variant = [];
    sp_checkrw = false;
    sp_diverge = false;
    sp_partial = false;
  }

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
