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
open Ast_builders
open Logic_pretty

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
  | Eq -> "="
  | Neq -> "<>"
  | Lt -> "<"
  | Le -> "<="
  | Gt -> ">"
  | Ge -> ">="
  | And -> "&&"
  | Or -> "||"

let relop_id (r : relop) : string =
  match r with REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="

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

let rec compile_iexpr (env : env) (e : iexpr) : Ptree.expr =
  match e.iexpr with
  | ILitInt n -> mk_expr (Econst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_expr (if b then Etrue else Efalse)
  | IVar x ->
      if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
  | IPar e -> compile_iexpr env e
  | IUn (Neg, a) -> mk_expr (Eidapp (qid1 "(-)", [ compile_iexpr env a ]))
  | IUn (Not, a) -> mk_expr (Enot (compile_iexpr env a))
  | IBin (And, a, b) -> mk_expr (Eand (compile_iexpr env a, compile_iexpr env b))
  | IBin (Or, a, b) -> mk_expr (Eor (compile_iexpr env a, compile_iexpr env b))
  | IBin (op, a, b) ->
      mk_expr (Einnfix (compile_iexpr env a, infix_ident (binop_id op), compile_iexpr env b))

let rec compile_term (env : env) (e : iexpr) : Ptree.term =
  match e.iexpr with
  | ILitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_term (if b then Ttrue else Tfalse)
  | IVar x -> mk_term (term_var env x)
  | IPar e -> compile_term env e
  | IUn (Neg, a) -> mk_term (Tidapp (qid1 "(-)", [ compile_term env a ]))
  | IUn (Not, a) -> mk_term (Tnot (compile_term env a))
  | IBin (And, a, b) -> term_bool_binop Dterm.DTand (compile_term env a) (compile_term env b)
  | IBin (Or, a, b) -> term_bool_binop Dterm.DTor (compile_term env a) (compile_term env b)
  | IBin (op, a, b) ->
      mk_term (Tinnfix (compile_term env a, infix_ident (binop_id op), compile_term env b))

let term_of_outputs (env : env) (outputs : vdecl list) : Ptree.term option =
  match outputs with
  | [] -> None
  | [ v ] -> Some (term_of_var env v.vname)
  | vs -> Some (mk_term (Ttuple (List.map (fun v -> term_of_var env v.vname) vs)))

let compile_hexpr ?(old = false) ?(prefer_link = false) ?(in_post = false) (env : env) (h : hexpr) :
    Ptree.term =
  let is_const_iexpr (e : iexpr) =
    match e.iexpr with
    | ILitInt _ | ILitBool _ -> true
    | IVar name ->
        let len = String.length name in
        len >= 4
        && String.sub name 0 3 = "Aut"
        && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))
    | _ -> false
  in
  match (find_link env h, prefer_link) with
  | Some id, true ->
      let t = mk_term (term_var env id) in
      if old then term_old t else t
  | _ -> begin
      match h with
      | HNow e ->
          let t = compile_term env e in
          let use_old = old && not (is_const_iexpr e) in
          if use_old then term_old t else t
      | HPreK (_e, k) -> begin
          let _ = (env, k) in
          failwith
            "compile_hexpr: residual HPreK in Why3 emission input (temporal lowering must run in IR)"
        end
    end

let compile_fo_term ?(prefer_link = false) (env : env) (f : fo_atom) : Ptree.term =
  match f with
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr ~prefer_link env h1,
             infix_ident (relop_id r),
             compile_hexpr ~prefer_link env h2 ))
  | FPred (id, hs) -> mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~prefer_link env) hs))

let compile_fo_term_shift ?(prefer_link = false) ?(in_post = false) (env : env) (old : bool)
    (f : fo_atom) : Ptree.term =
  match f with
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr ~old ~prefer_link ~in_post env h1,
             infix_ident (relop_id r),
             compile_hexpr ~old ~prefer_link ~in_post env h2 ))
  | FPred (id, hs) ->
      mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~old ~prefer_link ~in_post env) hs))

let rec compile_local_fo_formula_term ?(prefer_link = false) ?(in_post = false) (env : env)
    (f : Fo_formula.t) : Ptree.term =
  match f with
  | Fo_formula.FTrue -> mk_term Ttrue
  | Fo_formula.FFalse -> mk_term Tfalse
  | Fo_formula.FAtom fo -> compile_fo_term_shift ~prefer_link ~in_post env false fo
  | Fo_formula.FNot a ->
      mk_term (Tnot (compile_local_fo_formula_term ~prefer_link ~in_post env a))
  | Fo_formula.FAnd (a, b) ->
      term_bool_binop Dterm.DTand
        (compile_local_fo_formula_term ~prefer_link ~in_post env a)
        (compile_local_fo_formula_term ~prefer_link ~in_post env b)
  | Fo_formula.FOr (a, b) ->
      term_bool_binop Dterm.DTor
        (compile_local_fo_formula_term ~prefer_link ~in_post env a)
        (compile_local_fo_formula_term ~prefer_link ~in_post env b)
  | Fo_formula.FImp (a, b) ->
      term_bool_binop Dterm.DTimplies
        (compile_local_fo_formula_term ~prefer_link ~in_post env a)
        (compile_local_fo_formula_term ~prefer_link ~in_post env b)

let pre_k_source_expr (env : env) (e : iexpr) : Ptree.expr =
  match e.iexpr with
  | IVar x -> field env x
  | _ -> failwith "pre_k expects a variable as first argument"

let pre_k_source_term (env : env) (e : iexpr) : Ptree.term =
  match e.iexpr with
  | IVar x -> term_of_var env x
  | _ -> failwith "pre_k expects a variable as first argument"
