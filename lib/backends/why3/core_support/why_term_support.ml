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

open Why3
open Ptree
open Ast

type env = {
  rec_name : string;
  rec_vars : string list;
  var_map : (ident * ident) list;
  links : (hexpr * ident) list;
  pre_k : (hexpr * Temporal_support.pre_k_info) list;
  inst_map : (ident * ident) list;
  inputs : ident list;
}

let loc : Why3.Loc.position = Why3.Loc.dummy_position
let ident (s : string) : Ptree.ident = { Ptree.id_str = s; id_ats = []; id_loc = loc }

let infix_ident (s : string) : Ptree.ident =
  { Ptree.id_str = Ident.op_infix s; id_ats = []; id_loc = loc }

let qid1 (s : string) : Ptree.qualid = Ptree.Qident (ident s)
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

let term_old (t : Ptree.term) : Ptree.term = mk_term (Tapply (mk_term (Tident (qid1 "old")), t))

let apply_expr (fn : Ptree.expr) (args : Ptree.expr list) : Ptree.expr =
  List.fold_left (fun acc arg -> mk_expr (Eapply (acc, arg))) fn args

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

let rec_var_name (env : env) (name : ident) : ident =
  match List.assoc_opt name env.var_map with Some mapped -> mapped | None -> name

let field (env : env) (name : ident) : Ptree.expr =
  mk_expr (Eident (qdot (qid1 env.rec_name) (rec_var_name env name)))

let is_rec_var (env : env) (x : ident) : bool = List.exists (( = ) x) env.rec_vars

let term_var (env : env) (x : ident) : Ptree.term_desc =
  if is_rec_var env x then Tident (qdot (qid1 env.rec_name) (rec_var_name env x)) else Tident (qid1 x)

let find_link (env : env) (h : hexpr) : ident option =
  List.find_map (fun (h', id) -> if h' = h then Some id else None) env.links

let find_pre_k (env : env) (h : hexpr) : Temporal_support.pre_k_info option =
  List.find_map (fun (h', info) -> if h' = h then Some info else None) env.pre_k

let normalize_infix (s : string) : string =
  let prefix = "infix " in
  if String.length s > String.length prefix && String.sub s 0 (String.length prefix) = prefix then
    String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

let rec string_of_term (t : Ptree.term) : string =
  let aux = string_of_term in
  match t.term_desc with
  | Tconst c -> Ast_pretty.string_of_const c
  | Ttrue -> "true"
  | Tfalse -> "false"
  | Tident q -> Ast_pretty.string_of_qid q
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
  | Tidapp (q, args) -> Ast_pretty.string_of_qid q ^ "(" ^ String.concat ", " (List.map aux args) ^ ")"
  | Tat (t', id) -> if id.id_str = "old" then "old(" ^ aux t' ^ ")" else aux t' ^ "@" ^ id.id_str
  | Tapply (f, a) -> begin
      match f.term_desc with
      | Tident q when Ast_pretty.string_of_qid q = "old" -> "old(" ^ aux a ^ ")"
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

let why3_optimizations_enabled_ref = ref true
let set_why3_optimizations_enabled enabled = why3_optimizations_enabled_ref := enabled
let why3_optimizations_enabled () = !why3_optimizations_enabled_ref

let rec simplify_term_bool (t : Ptree.term) : Ptree.term =
  if not !why3_optimizations_enabled_ref then t
  else
  let rebuild_with_attrs attrs body =
    List.fold_right (fun attr acc -> mk_term (Tattr (attr, acc))) attrs body
  in
  let rec strip_attrs acc (term : Ptree.term) =
    match term.term_desc with
    | Tattr (attr, inner) -> strip_attrs (attr :: acc) inner
    | _ -> (List.rev acc, term)
  in
  let attrs, core = strip_attrs [] t in
  let simplified_core =
    match core.term_desc with
    | Tattr _ -> assert false
    | Tnot a -> begin
        match (simplify_term_bool a).term_desc with
        | Ttrue -> mk_term Tfalse
        | Tfalse -> mk_term Ttrue
        | Tnot inner -> inner
        | _ -> mk_term (Tnot (simplify_term_bool a))
      end
    | Tbinnop (a, Dterm.DTand, b) ->
        let a = simplify_term_bool a in
        let b = simplify_term_bool b in
        begin
          match (a.term_desc, b.term_desc) with
          | Tfalse, _ | _, Tfalse -> mk_term Tfalse
          | Ttrue, _ -> b
          | _, Ttrue -> a
          | _ when string_of_term a = string_of_term b -> a
          | _ -> term_bool_binop Dterm.DTand a b
        end
    | Tbinnop (a, Dterm.DTor, b) ->
        let a = simplify_term_bool a in
        let b = simplify_term_bool b in
        begin
          match (a.term_desc, b.term_desc) with
          | Ttrue, _ | _, Ttrue -> mk_term Ttrue
          | Tfalse, _ -> b
          | _, Tfalse -> a
          | _ when string_of_term a = string_of_term b -> a
          | _ -> term_bool_binop Dterm.DTor a b
        end
    | Tbinnop (a, Dterm.DTimplies, b) ->
        let a = simplify_term_bool a in
        let b = simplify_term_bool b in
        begin
          match (a.term_desc, b.term_desc) with
          | Tfalse, _ | _, Ttrue -> mk_term Ttrue
          | Ttrue, _ -> b
          | _, Tfalse -> mk_term (Tnot a) |> simplify_term_bool
          | _ when string_of_term a = string_of_term b -> mk_term Ttrue
          | _ -> term_bool_binop Dterm.DTimplies a b
        end
    | Tbinnop (a, op, b) -> mk_term (Tbinnop (simplify_term_bool a, op, simplify_term_bool b))
    | Tinnfix (a, op, b) -> mk_term (Tinnfix (simplify_term_bool a, op, simplify_term_bool b))
    | Tapply (f, a) -> mk_term (Tapply (simplify_term_bool f, simplify_term_bool a))
    | Tidapp (q, args) -> mk_term (Tidapp (q, List.map simplify_term_bool args))
    | Tif (c, t1, t2) ->
        let c = simplify_term_bool c in
        let t1 = simplify_term_bool t1 in
        let t2 = simplify_term_bool t2 in
        begin
          match c.term_desc with
          | Ttrue -> t1
          | Tfalse -> t2
          | _ when string_of_term t1 = string_of_term t2 -> t1
          | _ -> mk_term (Tif (c, t1, t2))
        end
    | Ttuple ts -> mk_term (Ttuple (List.map simplify_term_bool ts))
    | _ -> core
  in
  rebuild_with_attrs attrs simplified_core

let term_of_var (env : env) (name : ident) : Ptree.term = mk_term (term_var env name)

let relop_id (r : relop) : string =
  match r with REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="

let term_of_instance_var (env : env) (inst_name : ident) (node_name : ident) (var_name : ident) :
    Ptree.term =
  let inst_prefix = Generated_names.prefix_for_node node_name in
  let inner_field = inst_prefix ^ var_name in
  let inst_term =
    if List.mem inst_name env.rec_vars then term_of_var env inst_name else mk_term (Tident (qid1 inst_name))
  in
  mk_term (Tapply (mk_term (Tident (qid1 ("logic_" ^ inner_field))), inst_term))

let expr_of_instance_var (env : env) (inst_name : ident) (node_name : ident) (var_name : ident) :
    Ptree.expr =
  let inst_prefix = Generated_names.prefix_for_node node_name in
  let inner_field = inst_prefix ^ var_name in
  let inst_expr =
    if List.mem inst_name env.rec_vars then field env inst_name else mk_expr (Eident (qid1 inst_name))
  in
  apply_expr (mk_expr (Eident (qid1 ("get_" ^ inner_field)))) [ inst_expr ]
