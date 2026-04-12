(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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

[@@@ocaml.warning "-8-26-27-32-33"]

open Why3
open Ptree
open Core_syntax
open Pretty

(* ---- Compilation environment ---- *)

type env = {
  rec_name : string;
  rec_vars : string list;
  links : (hexpr * ident) list;
}

(* ---- Why3 Ptree primitives ---- *)

let loc : Why3.Loc.position = Why3.Loc.dummy_position
let ident (s : string) : Ptree.ident = { Ptree.id_str = s; id_ats = []; id_loc = loc }

let infix_ident (s : string) : Ptree.ident =
  { Ptree.id_str = Ident.op_infix s; id_ats = []; id_loc = loc }

let qid1 (s : string) : Ptree.qualid =
  match String.split_on_char '.' s with
  | [] -> Ptree.Qident (ident s)
  | hd :: tl ->
      List.fold_left (fun acc part -> Ptree.Qdot (acc, ident part)) (Ptree.Qident (ident hd)) tl
let qdot (q : Ptree.qualid) (s : string) : Ptree.qualid = Ptree.Qdot (q, ident s)
let mk_expr (desc : Ptree.expr_desc) : Ptree.expr = { Ptree.expr_desc = desc; expr_loc = loc }
let mk_term (desc : Ptree.term_desc) : Ptree.term = { Ptree.term_desc = desc; term_loc = loc }

let term_eq (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tinnfix (a, infix_ident "=", b))

let term_neq (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tinnfix (a, infix_ident "<>", b))

let term_bool_binop (op : Dterm.dbinop) (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  mk_term (Tbinnop (a, op, b))

let term_implies (a : Ptree.term) (b : Ptree.term) : Ptree.term =
  term_bool_binop Dterm.DTimplies a b

(* Wraps [t] with the WhyML [old] keyword using the [Tat] constructor so that
   [Mlw_printer] emits [old t] rather than the function-application form
   [(old t)] which would require a text post-processing fixup. *)
let term_old (t : Ptree.term) : Ptree.term = mk_term (Tat (t, ident "old"))

let apply_expr (fn : Ptree.expr) (args : Ptree.expr list) : Ptree.expr =
  List.fold_left (fun acc arg -> mk_expr (Eapply (acc, arg))) fn args

(* ---- Kairos → Why3 type and operator mappings ---- *)

let default_pty (t : ty) : Ptree.pty =
  match t with
  | TInt -> Ptree.PTtyapp (qid1 "int", [])
  | TBool -> Ptree.PTtyapp (qid1 "bool", [])
  | TReal -> Ptree.PTtyapp (qid1 "real", [])
  | TCustom s -> Ptree.PTtyapp (qid1 s, [])

let binop_id (op : binop) : string =
  match op with
  | Add -> "+"
  | Sub -> "-"
  | Mul -> "*"
  | Div -> "/"
  | And | Or -> invalid_arg "binop_id: expected arithmetic operator"

let relop_id (r : relop) : string =
  match r with REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="

(* let ibinop_id (op : ibinop) : string =
  match op with IAdd -> "+" | ISub -> "-" | IMul -> "*" | IDiv -> "/"

let ibool_binop_id (op : ibool_binop) : string =
  match op with IAnd -> "&&" | IOr -> "||" *)

(* ---- Env operations ---- *)

let field (env : env) (name : ident) : Ptree.expr =
  mk_expr (Eidapp (qid1 name, [ mk_expr (Eident (qid1 env.rec_name)) ]))

let is_rec_var (env : env) (x : ident) : bool = List.exists (( = ) x) env.rec_vars

let term_var (env : env) (x : ident) : Ptree.term_desc =
  if is_rec_var env x then Tidapp (qid1 x, [ mk_term (Tident (qid1 env.rec_name)) ])
  else Tident (qid1 x)

let find_link (env : env) (h : hexpr) : ident option =
  List.find_map (fun (h', id) -> if h' = h then Some id else None) env.links

let term_of_var (env : env) (name : ident) : Ptree.term = mk_term (term_var env name)

(* ---- Term serialisation (used for deduplication) ---- *)

let normalize_infix (s : string) : string =
  let prefix = "infix " in
  if String.length s > String.length prefix && String.sub s 0 (String.length prefix) = prefix then
    String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

let string_of_qid (q : Ptree.qualid) : string =
  let rec aux = function
    | Ptree.Qident id -> id.id_str
    | Ptree.Qdot (q, id) -> aux q ^ "." ^ id.id_str
  in
  aux q

let string_of_const (c : Why3.Constant.constant) : string =
  Format.asprintf "%a" Why3.Constant.print_def c

let rec string_of_term (t : Ptree.term) : string =
  let aux = string_of_term in
  match t.term_desc with
  | Tconst c -> string_of_const c
  | Ttrue -> "true"
  | Tfalse -> "false"
  | Tident q -> string_of_qid q
  | Tinnfix (a, op, b) ->
      let op_str = normalize_infix op.id_str in
      "(" ^ aux a ^ " " ^ op_str ^ " " ^ aux b ^ ")"
  | Tbinnop (a, d, b) ->
      let op =
        match d with
        | Dterm.DTand -> "/\\"
        | Dterm.DTor -> "\\/"
        | Dterm.DTimplies -> "->"
        | _ -> "?"
      in
      "(" ^ aux a ^ " " ^ op ^ " " ^ aux b ^ ")"
  | Tnot a -> "not " ^ aux a
  | Tidapp (q, args) -> string_of_qid q ^ "(" ^ String.concat ", " (List.map aux args) ^ ")"
  | Tat (t', id) -> if id.id_str = "old" then "old(" ^ aux t' ^ ")" else aux t' ^ "@" ^ id.id_str
  | Tapply (f, a) -> begin
      match f.term_desc with
      | Tident q when string_of_qid q = "old" -> "old(" ^ aux a ^ ")"
      | _ -> aux f ^ "(" ^ aux a ^ ")"
    end
  | _ -> "?"

let uniq_terms (terms : Ptree.term list) : Ptree.term list =
  let rec aux seen acc = function
    | [] -> List.rev acc
    | t :: ts ->
        let key = string_of_term t in
        if List.mem key seen then aux seen acc ts else aux (key :: seen) (t :: acc) ts
  in
  aux [] [] terms

(* ---- Expression and formula compilation ---- *)

let rec compile_expr (env : env) (e : expr) : Ptree.expr =
  match e.expr with
  | ELitInt n -> mk_expr (Econst (Constant.int_const (BigInt.of_int n)))
  | ELitBool b -> mk_expr (if b then Etrue else Efalse)
  | EVar x ->
      if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
  | EUn (Neg, a) -> mk_expr (Eidapp (qid1 "(-)", [ compile_expr env a ]))
  | EUn (Not, a) -> mk_expr (Enot (compile_expr env a))
  | EBin (op, a, b) -> (
      match op with
      | And -> mk_expr (Eand (compile_expr env a, compile_expr env b))
      | Or -> mk_expr (Eor (compile_expr env a, compile_expr env b))
      | Add | Sub | Mul | Div ->
          mk_expr (Einnfix (compile_expr env a, infix_ident (binop_id op), compile_expr env b)))
  | ECmp (op, a, b) ->
      mk_expr (Einnfix (compile_expr env a, infix_ident (relop_id op), compile_expr env b))

let rec compile_term (env : env) (e : expr) : Ptree.term =
  match e.expr with
  | ELitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ELitBool b -> mk_term (if b then Ttrue else Tfalse)
  | EVar x -> mk_term (term_var env x)
  | EUn (Neg, a) -> mk_term (Tidapp (qid1 "(-)", [ compile_term env a ]))
  | EUn (Not, a) -> mk_term (Tnot (compile_term env a))
  | EBin (op, a, b) -> (
      match op with
      | And -> term_bool_binop Dterm.DTand (compile_term env a) (compile_term env b)
      | Or -> term_bool_binop Dterm.DTor (compile_term env a) (compile_term env b)
      | Add | Sub | Mul | Div ->
          mk_term (Tinnfix (compile_term env a, infix_ident (binop_id op), compile_term env b)))
  | ECmp (op, a, b) ->
      mk_term (Tinnfix (compile_term env a, infix_ident (relop_id op), compile_term env b))

let term_of_outputs (env : env) (outputs : vdecl list) : Ptree.term option =
  match outputs with
  | [] -> None
  | [ v ] -> Some (term_of_var env v.vname)
  | vs -> Some (mk_term (Ttuple (List.map (fun v -> term_of_var env v.vname) vs)))

let compile_hexpr ?(old = false) ?(prefer_link = false) ?(in_post = false) (env : env) (h : hexpr) :
    Ptree.term =
  let is_const_var_name (name : string) =
    let len = String.length name in
    len >= 4
    && String.sub name 0 3 = "Aut"
    && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))
  in
  let rec is_const_hexpr (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> true
    | HVar name -> is_const_var_name name
    | HPreK _ -> false
    | HPred _ -> false
    | HUn (_, inner) -> is_const_hexpr inner
    | HBin (_, a, b) | HCmp (_, a, b) ->
        is_const_hexpr a && is_const_hexpr b
  in
  let rec compile_hexpr_term (h : hexpr) =
    match h.hexpr with
    | HLitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
    | HLitBool b -> mk_term (if b then Ttrue else Tfalse)
    | HVar x -> mk_term (term_var env x)
    | HUn (Neg, a) -> mk_term (Tidapp (qid1 "(-)", [ compile_hexpr_term a ]))
    | HUn (Not, a) -> mk_term (Tnot (compile_hexpr_term a))
    | HBin (op, a, b) -> (
        match op with
        | And -> term_bool_binop Dterm.DTand (compile_hexpr_term a) (compile_hexpr_term b)
        | Or -> term_bool_binop Dterm.DTor (compile_hexpr_term a) (compile_hexpr_term b)
        | Add | Sub | Mul | Div ->
            mk_term
              (Tinnfix
                 ( compile_hexpr_term a,
                   infix_ident
                     (binop_id op),
                   compile_hexpr_term b )))
    | HCmp (op, a, b) ->
        mk_term
          (Tinnfix
             ( compile_hexpr_term a,
               infix_ident
                 (relop_id op),
               compile_hexpr_term b ))
    | HPreK (_e, _k) ->
        failwith
          "compile_hexpr: residual HPreK in Why3 emission input (temporal lowering must run in IR)"
    | HPred (id, hs) ->
        mk_term (Tidapp (qid1 id, List.map compile_hexpr_term hs))
  in
  let _ = in_post in
  match (find_link env h, prefer_link) with
  | Some id, true ->
      let t = mk_term (term_var env id) in
      if old then term_old t else t
  | _ ->
      let t = compile_hexpr_term h in
      let use_old = old && not (is_const_hexpr h) in
      if use_old then term_old t else t

let compile_local_fo_formula_term ?(prefer_link = false) ?(in_post = false) (env : env)
    (f : Core_syntax.hexpr) : Ptree.term =
  compile_hexpr ~old:false ~prefer_link ~in_post env f

let pre_k_source_expr (env : env) (x : ident) : Ptree.expr =
  field env x

let pre_k_source_term (env : env) (x : ident) : Ptree.term =
  term_of_var env x
