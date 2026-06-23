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

module StringSet = Set.Make (String)

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

let binder_expr ((_, id_opt, _, _) : Ptree.binder) : Ptree.expr =
  match id_opt with
  | Some id -> mk_expr (Eident (qid1 id.id_str))
  | None -> mk_expr (Etuple [])

let binder_term ((_, id_opt, _, _) : Ptree.binder) : Ptree.term option =
  Option.map (fun id -> mk_term (Tident (qid1 id.id_str))) id_opt

let param_of_binder ((bloc, id_opt, ghost, pty_opt) : Ptree.binder) :
    Ptree.param option =
  Option.map (fun pty -> (bloc, id_opt, ghost, pty)) pty_opt

let rec names_of_qualid (qid : Ptree.qualid) (acc : StringSet.t) :
    StringSet.t =
  match qid with
  | Qident id -> StringSet.add id.id_str acc
  | Qdot (parent, id) -> StringSet.add id.id_str (names_of_qualid parent acc)

let rec names_of_term (term : Ptree.term) (acc : StringSet.t) : StringSet.t =
  match term.term_desc with
  | Ttrue | Tfalse | Tconst _ -> acc
  | Tident qid | Tasref qid -> names_of_qualid qid acc
  | Tidapp (qid, terms) ->
      List.fold_left
        (fun acc term -> names_of_term term acc)
        (names_of_qualid qid acc) terms
  | Tapply (fn, arg) -> names_of_term arg (names_of_term fn acc)
  | Tinfix (lhs, _, rhs)
  | Tinnfix (lhs, _, rhs)
  | Tbinop (lhs, _, rhs)
  | Tbinnop (lhs, _, rhs) ->
      names_of_term rhs (names_of_term lhs acc)
  | Tnot inner | Tcast (inner, _) | Tscope (_, inner) | Tat (inner, _)
  | Tattr (_, inner) ->
      names_of_term inner acc
  | Tif (cond, t_then, t_else) ->
      names_of_term t_else (names_of_term t_then (names_of_term cond acc))
  | Tquant (_, _, triggers, body) ->
      let acc =
        List.fold_left
          (fun acc trigger ->
            List.fold_left (fun acc term -> names_of_term term acc) acc trigger)
          acc triggers
      in
      names_of_term body acc
  | Teps (_, _, body) -> names_of_term body acc
  | Tlet (_, value, body) -> names_of_term body (names_of_term value acc)
  | Tcase (scrutinee, branches) ->
      List.fold_left
        (fun acc (_pattern, body) -> names_of_term body acc)
        (names_of_term scrutinee acc) branches
  | Ttuple terms ->
      List.fold_left (fun acc term -> names_of_term term acc) acc terms
  | Trecord fields ->
      List.fold_left (fun acc (_field, term) -> names_of_term term acc) acc fields
  | Tupdate (base, fields) ->
      List.fold_left
        (fun acc (_field, term) -> names_of_term term acc)
        (names_of_term base acc) fields

let names_of_variant (variant : Ptree.variant) (acc : StringSet.t) :
    StringSet.t =
  List.fold_left (fun acc (term, _rel) -> names_of_term term acc) acc variant

let rec term_has_old (term : Ptree.term) : bool =
  match term.term_desc with
  | Tapply (fn, arg) -> (
      match fn.term_desc with
      | Tident qid when String.equal (string_of_qid qid) "old" -> true
      | _ -> term_has_old fn || term_has_old arg)
  | Tat (_, id) when String.equal id.id_str "old" -> true
  | Tinfix (lhs, _, rhs)
  | Tinnfix (lhs, _, rhs)
  | Tbinop (lhs, _, rhs)
  | Tbinnop (lhs, _, rhs) ->
      term_has_old lhs || term_has_old rhs
  | Tnot inner | Tcast (inner, _) | Tscope (_, inner) | Tat (inner, _)
  | Tattr (_, inner) ->
      term_has_old inner
  | Tif (cond, t_then, t_else) ->
      term_has_old cond || term_has_old t_then || term_has_old t_else
  | Tquant (_, _, triggers, body) ->
      List.exists (List.exists term_has_old) triggers || term_has_old body
  | Teps (_, _, body) -> term_has_old body
  | Tlet (_, value, body) -> term_has_old value || term_has_old body
  | Tcase (scrutinee, branches) ->
      term_has_old scrutinee
      || List.exists (fun (_pattern, body) -> term_has_old body) branches
  | Tidapp (_, terms) | Ttuple terms -> List.exists term_has_old terms
  | Trecord fields -> List.exists (fun (_field, term) -> term_has_old term) fields
  | Tupdate (base, fields) ->
      term_has_old base || List.exists (fun (_field, term) -> term_has_old term) fields
  | Ttrue | Tfalse | Tconst _ | Tident _ | Tasref _ -> false

let names_of_spec (spc : Ptree.spec) (acc : StringSet.t) : StringSet.t =
  let acc = List.fold_left (fun acc term -> names_of_term term acc) acc spc.sp_pre in
  let acc =
    List.fold_left
      (fun acc (_loc, posts) ->
        List.fold_left
          (fun acc (_pat, term) -> names_of_term term acc)
          acc posts)
      acc spc.sp_post
  in
  let acc =
    List.fold_left
      (fun acc (_loc, posts) ->
        List.fold_left
          (fun acc (_qid, post_opt) ->
            match post_opt with
            | None -> acc
            | Some (_pat, term) -> names_of_term term acc)
          acc posts)
      acc spc.sp_xpost
  in
  let acc = List.fold_left (fun acc term -> names_of_term term acc) acc spc.sp_writes in
  let acc =
    List.fold_left
      (fun acc (lhs, rhs) -> names_of_term rhs (names_of_term lhs acc))
      acc spc.sp_alias
  in
  names_of_variant spc.sp_variant acc

let rec names_of_expr (expr : Ptree.expr) (acc : StringSet.t) : StringSet.t =
  match expr.expr_desc with
  | Eref | Etrue | Efalse | Econst _ | Eabsurd -> acc
  | Eident qid | Easref qid | Eidpur qid -> names_of_qualid qid acc
  | Eidapp (qid, args) ->
      List.fold_left
        (fun acc expr -> names_of_expr expr acc)
        (names_of_qualid qid acc) args
  | Eapply (fn, arg) | Einfix (fn, _, arg) | Einnfix (fn, _, arg) ->
      names_of_expr arg (names_of_expr fn acc)
  | Elet (_, _, _, value, body) ->
      names_of_expr body (names_of_expr value acc)
  | Erec (defs, body) ->
      let acc =
        List.fold_left
          (fun acc (_id, _ghost, _kind, _binders, _pty, _pat, _mask, spc, body) ->
            names_of_expr body (names_of_spec spc acc))
          acc defs
      in
      names_of_expr body acc
  | Efun (_binders, _pty, _pat, _mask, spc, body) ->
      names_of_expr body (names_of_spec spc acc)
  | Eany (_params, _kind, _pty, _pat, _mask, spc) -> names_of_spec spc acc
  | Etuple exprs -> List.fold_left (fun acc expr -> names_of_expr expr acc) acc exprs
  | Erecord fields ->
      List.fold_left (fun acc (_field, expr) -> names_of_expr expr acc) acc fields
  | Eupdate (base, fields) ->
      List.fold_left
        (fun acc (_field, expr) -> names_of_expr expr acc)
        (names_of_expr base acc) fields
  | Eassign assigns ->
      List.fold_left
        (fun acc (lhs, _field, rhs) -> names_of_expr rhs (names_of_expr lhs acc))
        acc assigns
  | Esequence (first, second)
  | Eand (first, second)
  | Eor (first, second) ->
      names_of_expr second (names_of_expr first acc)
  | Eif (cond, t_then, t_else) ->
      names_of_expr t_else (names_of_expr t_then (names_of_expr cond acc))
  | Ewhile (cond, invariant, variant, body) ->
      let acc = List.fold_left (fun acc term -> names_of_term term acc) acc invariant in
      names_of_expr body (names_of_variant variant (names_of_expr cond acc))
  | Enot inner | Ecast (inner, _) | Eghost inner | Eattr (_, inner) | Elabel (_, inner)
  | Escope (_, inner) ->
      names_of_expr inner acc
  | Ematch (scrutinee, branches, exn_branches) ->
      let acc =
        List.fold_left
          (fun acc (_pat, body) -> names_of_expr body acc)
          (names_of_expr scrutinee acc) branches
      in
      List.fold_left
        (fun acc (_qid, _pattern_opt, body) -> names_of_expr body acc)
        acc exn_branches
  | Epure term | Eassert (_, term) -> names_of_term term acc
  | Eraise (_qid, expr_opt) ->
      Option.fold ~none:acc ~some:(fun expr -> names_of_expr expr acc) expr_opt
  | Eexn (_, _, _, body) | Eoptexn (_, _, body) -> names_of_expr body acc
  | Efor (_, start, _dir, stop, invariant, body) ->
      let acc = List.fold_left (fun acc term -> names_of_term term acc) acc invariant in
      names_of_expr body (names_of_expr stop (names_of_expr start acc))

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
