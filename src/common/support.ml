(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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
open Ast

type fold_info = { h: hexpr; acc: string; init_flag: string option }
type pre_k_info = { h: hexpr; expr: iexpr; names: string list; vty: ty }
type env = {
  rec_name: string;
  rec_vars: string list;
  var_map: (ident * ident) list;
  ghosts: fold_info list;
  links: (hexpr * ident) list;
  pre_k: (hexpr * pre_k_info) list;
  inst_map: (ident * ident) list;
  inputs: ident list;
}

let loc : Why3.Loc.position = Why3.Loc.dummy_position
let ident (s:string) : Ptree.ident = { Ptree.id_str = s; id_ats = []; id_loc = loc }
let infix_ident (s:string) : Ptree.ident = { Ptree.id_str = Ident.op_infix s; id_ats = []; id_loc = loc }
let qid1 (s:string) : Ptree.qualid = Ptree.Qident (ident s)
let qdot (q:Ptree.qualid) (s:string) : Ptree.qualid = Ptree.Qdot (q, ident s)
let module_name_of_node (name:ident) : string = String.capitalize_ascii name
let prefix_for_node (name:ident) : string = "__" ^ String.lowercase_ascii name ^ "_"
let pre_input_name (name:ident) : string = "__pre_in_" ^ name
let pre_input_old_name (name:ident) : string = "__pre_old_" ^ name

let mk_expr (desc:Ptree.expr_desc) : Ptree.expr = { Ptree.expr_desc = desc; expr_loc = loc }
let mk_term (desc:Ptree.term_desc) : Ptree.term = { Ptree.term_desc = desc; term_loc = loc }

let term_eq (a:Ptree.term) (b:Ptree.term) : Ptree.term =
  mk_term (Tinnfix (a, infix_ident "=", b))
let term_neq (a:Ptree.term) (b:Ptree.term) : Ptree.term =
  mk_term (Tinnfix (a, infix_ident "<>", b))
let term_implies (a:Ptree.term) (b:Ptree.term) : Ptree.term =
  mk_term (Tbinop (a, Dterm.DTimplies, b))
let term_old (t:Ptree.term) : Ptree.term =
  mk_term (Tapply (mk_term (Tident (qid1 "old")), t))
let apply_expr (fn:Ptree.expr) (args:Ptree.expr list) : Ptree.expr =
  List.fold_left (fun acc arg -> mk_expr (Eapply (acc, arg))) fn args

let default_pty (t:ty) : Ptree.pty =
  match t with
  | TInt -> Ptree.PTtyapp(qid1 "int", [])
  | TBool -> Ptree.PTtyapp(qid1 "bool", [])
  | TReal -> Ptree.PTtyapp(qid1 "real", [])
  | TCustom s -> Ptree.PTtyapp(qid1 s, [])

let binop_id (op:binop) : string =
  match op with
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/"
  | Eq -> "=" | Neq -> "<>" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="
  | And -> "&&" | Or -> "||"

let rec_var_name (env:env) (name:ident) : ident =
  match List.assoc_opt name env.var_map with
  | Some mapped -> mapped
  | None -> name
let field (env:env) (name:ident) : Ptree.expr =
  mk_expr (Eident (qdot (qid1 env.rec_name) (rec_var_name env name)))
let is_rec_var (env:env) (x:ident) : bool = List.exists ((=) x) env.rec_vars
let term_var (env:env) (x:ident) : Ptree.term_desc =
  if is_rec_var env x
  then Tident (qdot (qid1 env.rec_name) (rec_var_name env x))
  else Tident (qid1 x)
let find_fold (env:env) (h:hexpr) : ident option =
  List.find_map (fun (fi:fold_info) -> if fi.h = h then Some fi.acc else None) env.ghosts
let find_link (env:env) (h:hexpr) : ident option =
  List.find_map (fun (h', id) -> if h' = h then Some id else None) env.links
let find_pre_k (env:env) (h:hexpr) : pre_k_info option =
  List.find_map (fun (h', info) -> if h' = h then Some info else None) env.pre_k

let rec string_of_qid (q:Ptree.qualid) : string =
  match q with
  | Ptree.Qident id -> id.id_str
  | Ptree.Qdot (q,id) -> string_of_qid q ^ "." ^ id.id_str

let string_of_const (c:Constant.constant) : string =
  Format.asprintf "%a" Constant.print_def c

let string_of_op (op:op) : string =
  match op with
  | OMin -> "min"
  | OMax -> "max"
  | OAdd -> "add"
  | OMul -> "mul"
  | OAnd -> "and"
  | OOr -> "or"
  | OFirst -> "first"

let string_of_relop (op:relop) : string =
  match op with
  | REq -> "="
  | RNeq -> "<>"
  | RLt -> "<"
  | RLe -> "<="
  | RGt -> ">"
  | RGe -> ">="

type ltl_norm = { ltl: fo_ltl; k_guard: int option }

let rec max_x_depth (f:fo_ltl) : int =
  match f with
  | LX a -> 1 + max_x_depth a
  | LTrue | LFalse | LAtom _ -> 0
  | LNot a | LG a -> max_x_depth a
  | LAnd (a,b) | LOr (a,b) | LImp (a,b) ->
      max (max_x_depth a) (max_x_depth b)

let rec ltl_of_fo (f:fo) : fo_ltl =
  match f with
  | FTrue -> LTrue
  | FFalse -> LFalse
  | FRel _ | FPred _ -> LAtom f
  | FNot a -> LNot (ltl_of_fo a)
  | FAnd (a,b) -> LAnd (ltl_of_fo a, ltl_of_fo b)
  | FOr (a,b) -> LOr (ltl_of_fo a, ltl_of_fo b)
  | FImp (a,b) -> LImp (ltl_of_fo a, ltl_of_fo b)

let rec fo_of_ltl (f:fo_ltl) : fo =
  match f with
  | LTrue -> FTrue
  | LFalse -> FFalse
  | LAtom a -> a
  | LNot a -> FNot (fo_of_ltl a)
  | LAnd (a,b) -> FAnd (fo_of_ltl a, fo_of_ltl b)
  | LOr (a,b) -> FOr (fo_of_ltl a, fo_of_ltl b)
  | LImp (a,b) -> FImp (fo_of_ltl a, fo_of_ltl b)
  | LX _ | LG _ -> failwith "fo_of_ltl: LTL operator in FO formula"

let is_const_iexpr (e:iexpr) : bool =
  match e.iexpr with
  | ILitInt _ | ILitBool _ -> true
  | IVar name ->
      let len = String.length name in
      len >= 4
      && String.sub name 0 3 = "Mon"
      && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))
  | _ -> false

let shift_hexpr_by ~(init_for_var:ident -> iexpr) (shift:int) (h:hexpr)
  : hexpr option =
  if shift <= 0 then Some h
  else
    match h with
    | HNow e when is_const_iexpr e ->
        Some (HNow e)
    | HNow e ->
        begin match as_var e with
        | Some v -> Some (HPreK (mk_var v, 1))
        | None -> None
        end
    | HPreK (e, k) ->
      begin match as_var e with
      | Some v -> Some (HPreK (mk_var v, k + shift))
      | None -> None
      end
    | _ -> None

let normalize_ltl_for_k ~(init_for_var:ident -> iexpr) (f:fo_ltl) : ltl_norm =
  let rec shift_ltl_with_depth k depth f =
    match f with
    | LX a -> shift_ltl_with_depth k (depth + 1) a
    | LTrue | LFalse -> Some f
    | LNot a ->
        begin match shift_ltl_with_depth k depth a with
        | Some a' -> Some (LNot a')
        | None -> None
        end
    | LAnd (a,b) ->
        begin match shift_ltl_with_depth k depth a,
                    shift_ltl_with_depth k depth b with
        | Some a', Some b' -> Some (LAnd (a', b'))
        | _ -> None
        end
    | LOr (a,b) ->
        begin match shift_ltl_with_depth k depth a,
                    shift_ltl_with_depth k depth b with
        | Some a', Some b' -> Some (LOr (a', b'))
        | _ -> None
        end
    | LImp (a,b) ->
        begin match shift_ltl_with_depth k depth a,
                    shift_ltl_with_depth k depth b with
        | Some a', Some b' -> Some (LImp (a', b'))
        | _ -> None
        end
    | LG a ->
        begin match shift_ltl_with_depth k depth a with
        | Some a' -> Some (LG a')
        | None -> None
        end
    | LAtom (FRel (h1,r,h2)) ->
        let shift = k - depth in
        begin match shift_hexpr_by ~init_for_var shift h1,
                    shift_hexpr_by ~init_for_var shift h2 with
        | Some h1', Some h2' -> Some (LAtom (FRel (h1', r, h2')))
        | _ -> None
        end
    | LAtom (FPred (id,hs)) ->
        let shift = k - depth in
        let rec map acc = function
          | [] -> Some (List.rev acc)
          | h :: rest ->
              match shift_hexpr_by ~init_for_var shift h with
              | Some h' -> map (h' :: acc) rest
              | None -> None
        in
        begin match map [] hs with
        | Some hs' -> Some (LAtom (FPred (id, hs')))
        | None -> None
        end
  in
  let k = max_x_depth f in
  if k = 0 then { ltl = f; k_guard = None }
  else { ltl = f; k_guard = Some k }

let rec shift_ltl_by ~(init_for_var:ident -> iexpr) (shift:int) (f:fo_ltl)
  : fo_ltl option =
  if shift <= 0 then Some f
  else
    match f with
    | LX a ->
        shift_ltl_by ~init_for_var (shift + 1) a
    | LTrue | LFalse -> Some f
    | LNot a ->
        begin match shift_ltl_by ~init_for_var shift a with
        | Some a' -> Some (LNot a')
        | None -> None
        end
    | LAnd (a,b) ->
        begin match shift_ltl_by ~init_for_var shift a,
                    shift_ltl_by ~init_for_var shift b with
        | Some a', Some b' -> Some (LAnd (a', b'))
        | _ -> None
        end
    | LOr (a,b) ->
        begin match shift_ltl_by ~init_for_var shift a,
                    shift_ltl_by ~init_for_var shift b with
        | Some a', Some b' -> Some (LOr (a', b'))
        | _ -> None
        end
    | LImp (a,b) ->
        begin match shift_ltl_by ~init_for_var shift a,
                    shift_ltl_by ~init_for_var shift b with
        | Some a', Some b' -> Some (LImp (a', b'))
        | _ -> None
        end
    | LG a ->
        begin match shift_ltl_by ~init_for_var shift a with
        | Some a' -> Some (LG a')
        | None -> None
        end
    | LAtom (FRel (h1,r,h2)) ->
        begin match shift_hexpr_by ~init_for_var shift h1,
                    shift_hexpr_by ~init_for_var shift h2 with
        | Some h1', Some h2' -> Some (LAtom (FRel (h1', r, h2')))
        | _ -> None
        end
    | LAtom (FPred (id,hs)) ->
        let rec map acc = function
          | [] -> Some (List.rev acc)
          | h :: rest ->
              match shift_hexpr_by ~init_for_var shift h with
              | Some h' -> map (h' :: acc) rest
              | None -> None
        in
        begin match map [] hs with
        | Some hs' -> Some (LAtom (FPred (id, hs')))
        | None -> None
        end

let rec string_of_iexpr ?(ctx=0) (e:iexpr) : string =
  let prec_of_binop = function
    | Or -> 1
    | And -> 2
    | Eq | Neq | Lt | Le | Gt | Ge -> 3
    | Add | Sub -> 4
    | Mul | Div -> 5
  in
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match e.iexpr with
  | ILitInt n -> string_of_int n
  | ILitBool b -> if b then "true" else "false"
  | IVar x -> x
  | IPar inner -> "(" ^ string_of_iexpr inner ^ ")"
  | IUn (Neg, a) ->
      wrap 6 ("-" ^ string_of_iexpr ~ctx:6 a)
  | IUn (Not, a) ->
      wrap 6 ("not " ^ string_of_iexpr ~ctx:6 a)
  | IBin (op, a, b) ->
      let prec = prec_of_binop op in
      let op_str = binop_id op in
      wrap prec (string_of_iexpr ~ctx:prec a ^ " " ^ op_str ^ " " ^ string_of_iexpr ~ctx:prec b)

let string_of_hexpr (h:hexpr) : string =
  match h with
  | HNow e -> "{" ^ string_of_iexpr e ^ "}"
  | HPreK (e, k) ->
      if k = 1 then
        "pre(" ^ string_of_iexpr e ^ ")"
      else
        "pre_k(" ^ string_of_iexpr e ^ ", " ^ string_of_int k ^ ")"
  | HFold (op, init, e) ->
      "fold(" ^ string_of_op op ^ ", " ^ string_of_iexpr init ^ ", " ^ string_of_iexpr e ^ ")"

let rec string_of_fo ?(ctx=0) (f:fo) : string =
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match f with
  | FTrue -> "true"
  | FFalse -> "false"
  | FRel (h1, r, h2) ->
      string_of_hexpr h1 ^ " " ^ string_of_relop r ^ " " ^ string_of_hexpr h2
  | FPred (id, hs) ->
      id ^ "(" ^ String.concat ", " (List.map string_of_hexpr hs) ^ ")"
  | FNot a -> wrap 5 ("not " ^ string_of_fo ~ctx:5 a)
  | FAnd (a,b) -> wrap 3 (string_of_fo ~ctx:3 a ^ " and " ^ string_of_fo ~ctx:3 b)
  | FOr (a,b) -> wrap 2 (string_of_fo ~ctx:2 a ^ " or " ^ string_of_fo ~ctx:2 b)
  | FImp (a,b) -> wrap 1 (string_of_fo ~ctx:1 a ^ " -> " ^ string_of_fo ~ctx:1 b)

let rec string_of_ltl ?(ctx=0) (f:fo_ltl) : string =
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match f with
  | LTrue -> "true"
  | LFalse -> "false"
  | LAtom a -> string_of_fo a
  | LNot a -> wrap 5 ("not " ^ string_of_ltl ~ctx:5 a)
  | LX a -> "X(" ^ string_of_ltl a ^ ")"
  | LG a -> "G(" ^ string_of_ltl a ^ ")"
  | LAnd (a,b) -> wrap 3 (string_of_ltl ~ctx:3 a ^ " and " ^ string_of_ltl ~ctx:3 b)
  | LOr (a,b) -> wrap 2 (string_of_ltl ~ctx:2 a ^ " or " ^ string_of_ltl ~ctx:2 b)
  | LImp (a,b) -> wrap 1 (string_of_ltl ~ctx:1 a ^ " -> " ^ string_of_ltl ~ctx:1 b)

let normalize_infix (s:string) : string =
  let prefix = "infix " in
  if String.length s > String.length prefix && String.sub s 0 (String.length prefix) = prefix
  then String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

let rec string_of_term (t:Ptree.term) : string =
  let open Ptree in
  let aux = string_of_term in
  match t.term_desc with
  | Tconst c -> string_of_const c
  | Ttrue -> "true"
  | Tfalse -> "false"
  | Tident q -> string_of_qid q
  | Tinnfix (a, op, b) ->
      let op_str = normalize_infix op.id_str in
      "(" ^ aux a ^ " " ^ op_str ^ " " ^ aux b ^ ")"
  | Tbinop (a, d, b) ->
      let op = match d with
        | Dterm.DTand -> "/\\"
        | Dterm.DTor -> "\\/"
        | Dterm.DTimplies -> "->"
      in "(" ^ aux a ^ " " ^ op ^ " " ^ aux b ^ ")"
  | Tnot a -> "not " ^ aux a
  | Tidapp (q, args) ->
      string_of_qid q ^ "(" ^ String.concat ", " (List.map aux args) ^ ")"
  | Tat (t', id) ->
      if id.id_str = "old" then
        "old(" ^ aux t' ^ ")"
      else
        aux t' ^ "@" ^ id.id_str
  | Tapply (f, a) ->
      begin match f.term_desc with
      | Tident q when string_of_qid q = "old" ->
          "old(" ^ aux a ^ ")"
      | _ ->
          aux f ^ "(" ^ aux a ^ ")"
      end
  | _ -> "?"

let uniq_terms (terms:Ptree.term list) : Ptree.term list =
  let rec aux seen acc = function
    | [] -> List.rev acc
    | t::ts ->
        let key = string_of_term t in
        if List.mem key seen then aux seen acc ts
        else aux (key :: seen) (t :: acc) ts
  in
  aux [] [] terms

let term_of_var (env:env) (name:ident) : Ptree.term = mk_term (term_var env name)
let relop_id (r:relop) : string =
  match r with
  | REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="
let term_of_instance_var (env:env) (inst_name:ident) (node_name:ident)
  (var_name:ident) : Ptree.term =
  let inst_field = rec_var_name env inst_name in
  let inst_prefix = prefix_for_node node_name in
  let inner_field = inst_prefix ^ var_name in
  let base = qdot (qid1 env.rec_name) inst_field in
  mk_term (Tident (qdot base inner_field))

let expr_of_instance_var (env:env) (inst_name:ident) (node_name:ident)
  (var_name:ident) : Ptree.expr =
  let inst_field = rec_var_name env inst_name in
  let inst_prefix = prefix_for_node node_name in
  let inner_field = inst_prefix ^ var_name in
  let base = qdot (qid1 env.rec_name) inst_field in
  mk_expr (Eident (qdot base inner_field))
