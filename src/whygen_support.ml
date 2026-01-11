[@@@ocaml.warning "-8-26-27-32-33"]
open Why3
open Ptree
open Ast

type fold_info = { h: hexpr; acc: string; init_flag: string option }
type pre_k_info = { h: hexpr; expr: iexpr; init: iexpr; names: string list; vty: ty }
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

let loc = Loc.dummy_position
let ident s = { Ptree.id_str = s; id_ats = []; id_loc = loc }
let infix_ident s = { Ptree.id_str = Ident.op_infix s; id_ats = []; id_loc = loc }
let qid1 s = Ptree.Qident (ident s)
let qdot q s = Ptree.Qdot (q, ident s)
let module_name_of_node name = String.capitalize_ascii name
let prefix_for_node name = "__" ^ String.lowercase_ascii name ^ "_"
let pre_input_name name = "__pre_in_" ^ name
let pre_input_old_name name = "__pre_old_" ^ name

let mk_expr desc = { Ptree.expr_desc = desc; expr_loc = loc }
let mk_term desc = { Ptree.term_desc = desc; term_loc = loc }

let term_eq a b = mk_term (Tinnfix (a, infix_ident "=", b))
let term_neq a b = mk_term (Tinnfix (a, infix_ident "<>", b))
let term_implies a b = mk_term (Tbinop (a, Dterm.DTimplies, b))
let term_old t = mk_term (Tapply (mk_term (Tident (qid1 "old")), t))
let apply_expr fn args =
  List.fold_left (fun acc arg -> mk_expr (Eapply (acc, arg))) fn args

let default_pty = function
  | TInt -> Ptree.PTtyapp(qid1 "int", [])
  | TBool -> Ptree.PTtyapp(qid1 "bool", [])
  | TReal -> Ptree.PTtyapp(qid1 "real", [])
  | TCustom s -> Ptree.PTtyapp(qid1 s, [])

let binop_id = function
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/"
  | Eq -> "=" | Neq -> "<>" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="
  | And -> "&&" | Or -> "||"

let rec_var_name env name =
  match List.assoc_opt name env.var_map with
  | Some mapped -> mapped
  | None -> name
let field env name = mk_expr (Eident (qdot (qid1 env.rec_name) (rec_var_name env name)))
let is_rec_var env x = List.exists ((=) x) env.rec_vars
let term_var env x =
  if is_rec_var env x
  then Tident (qdot (qid1 env.rec_name) (rec_var_name env x))
  else Tident (qid1 x)
let find_fold (env:env) h =
  List.find_map (fun (fi:fold_info) -> if fi.h = h then Some fi.acc else None) env.ghosts
let find_link env h =
  List.find_map (fun (h', id) -> if h' = h then Some id else None) env.links
let find_pre_k env h =
  List.find_map (fun (h', info) -> if h' = h then Some info else None) env.pre_k

let rec string_of_qid = function
  | Ptree.Qident id -> id.id_str
  | Ptree.Qdot (q,id) -> string_of_qid q ^ "." ^ id.id_str

let string_of_const c = Format.asprintf "%a" Constant.print_def c

let string_of_op = function
  | OMin -> "min"
  | OMax -> "max"
  | OAdd -> "add"
  | OMul -> "mul"
  | OAnd -> "and"
  | OOr -> "or"
  | OFirst -> "first"

let string_of_wop = function
  | WMin -> "min"
  | WMax -> "max"
  | WSum -> "add"
  | WCount -> "mul"

let string_of_relop = function
  | REq -> "="
  | RNeq -> "<>"
  | RLt -> "<"
  | RLe -> "<="
  | RGt -> ">"
  | RGe -> ">="

type ltl_norm = { ltl: ltl; k_guard: int option }

let rec max_x_depth = function
  | LX a -> 1 + max_x_depth a
  | LTrue | LFalse | LAtom _ -> 0
  | LNot a | LG a -> max_x_depth a
  | LAnd (a,b) | LOr (a,b) | LImp (a,b) ->
      max (max_x_depth a) (max_x_depth b)

let is_const_iexpr = function
  | ILitInt _ | ILitBool _ -> true
  | _ -> false

let rec shift_hexpr_by ~init_for_var shift h =
  if shift <= 0 then Some h
  else
    match h with
    | HNow (IVar v) ->
        Some (HPreK (IVar v, init_for_var v, shift))
    | HNow e when is_const_iexpr e ->
        Some (HNow e)
    | HPre (IVar v, init_opt) ->
        let init = match init_opt with Some i -> i | None -> init_for_var v in
        Some (HPreK (IVar v, init, shift + 1))
    | HPreK (IVar v, init, k) ->
        Some (HPreK (IVar v, init, k + shift))
    | HLet (id, h1, h2) ->
        begin match shift_hexpr_by ~init_for_var shift h1,
                    shift_hexpr_by ~init_for_var shift h2 with
        | Some h1', Some h2' -> Some (HLet (id, h1', h2'))
        | _ -> None
        end
    | _ -> None

let normalize_ltl_for_k ~init_for_var (f:ltl) : ltl_norm =
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
    | LAtom (ARel (h1,r,h2)) ->
        let shift = k - depth in
        begin match shift_hexpr_by ~init_for_var shift h1,
                    shift_hexpr_by ~init_for_var shift h2 with
        | Some h1', Some h2' -> Some (LAtom (ARel (h1', r, h2')))
        | _ -> None
        end
    | LAtom (APred (id,hs)) ->
        let shift = k - depth in
        let rec map acc = function
          | [] -> Some (List.rev acc)
          | h :: rest ->
              match shift_hexpr_by ~init_for_var shift h with
              | Some h' -> map (h' :: acc) rest
              | None -> None
        in
        begin match map [] hs with
        | Some hs' -> Some (LAtom (APred (id, hs')))
        | None -> None
        end
  in
  match f with
  | LG a ->
      let k = max_x_depth a in
      if k <= 1 then { ltl = f; k_guard = None }
      else
        begin match shift_ltl_with_depth k 0 a with
        | Some a' -> { ltl = LG a'; k_guard = Some k }
        | None -> { ltl = f; k_guard = None }
        end
  | _ -> { ltl = f; k_guard = None }

let rec string_of_iexpr ?(ctx=0) (e:iexpr) =
  let prec_of_binop = function
    | Or -> 1
    | And -> 2
    | Eq | Neq | Lt | Le | Gt | Ge -> 3
    | Add | Sub -> 4
    | Mul | Div -> 5
  in
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match e with
  | ILitInt n -> string_of_int n
  | ILitBool b -> if b then "true" else "false"
  | IVar x -> x
  | IScan1 (op, inner) ->
      "scan1(" ^ string_of_op op ^ ", " ^ string_of_iexpr inner ^ ")"
  | IScan (op, init, inner) ->
      "scan(" ^ string_of_op op ^ ", " ^ string_of_iexpr init ^ ", " ^ string_of_iexpr inner ^ ")"
  | IPar inner -> "(" ^ string_of_iexpr inner ^ ")"
  | IUn (Neg, a) ->
      wrap 6 ("-" ^ string_of_iexpr ~ctx:6 a)
  | IUn (Not, a) ->
      wrap 6 ("not " ^ string_of_iexpr ~ctx:6 a)
  | IBin (op, a, b) ->
      let prec = prec_of_binop op in
      let op_str = binop_id op in
      wrap prec (string_of_iexpr ~ctx:prec a ^ " " ^ op_str ^ " " ^ string_of_iexpr ~ctx:prec b)

let rec string_of_hexpr (h:hexpr) =
  match h with
  | HNow e -> "{" ^ string_of_iexpr e ^ "}"
  | HPre (e, None) -> "pre(" ^ string_of_iexpr e ^ ")"
  | HPre (e, Some init) -> "pre(" ^ string_of_iexpr e ^ ", " ^ string_of_iexpr init ^ ")"
  | HPreK (e, init, k) ->
      "pre_k(" ^ string_of_iexpr e ^ ", " ^ string_of_iexpr init ^ ", " ^ string_of_int k ^ ")"
  | HScan1 (op, e) -> "scan1(" ^ string_of_op op ^ ", " ^ string_of_iexpr e ^ ")"
  | HScan (op, init, e) ->
      "scan(" ^ string_of_op op ^ ", " ^ string_of_iexpr init ^ ", " ^ string_of_iexpr e ^ ")"
  | HFold (op, init, e) ->
      "fold(" ^ string_of_op op ^ ", " ^ string_of_iexpr init ^ ", " ^ string_of_iexpr e ^ ")"
  | HWindow (k, wop, e) ->
      "window(" ^ string_of_int k ^ ", " ^ string_of_wop wop ^ ", " ^ string_of_iexpr e ^ ")"
  | HLet (id, h1, h2) ->
      "let " ^ id ^ " = " ^ string_of_hexpr h1 ^ " in " ^ string_of_hexpr h2

let string_of_atom = function
  | ARel (h1, r, h2) ->
      string_of_hexpr h1 ^ " " ^ string_of_relop r ^ " " ^ string_of_hexpr h2
  | APred (id, hs) ->
      id ^ "(" ^ String.concat ", " (List.map string_of_hexpr hs) ^ ")"

let rec string_of_ltl ?(ctx=0) (f:ltl) =
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match f with
  | LTrue -> "true"
  | LFalse -> "false"
  | LAtom a -> string_of_atom a
  | LNot a -> wrap 5 ("not " ^ string_of_ltl ~ctx:5 a)
  | LX a -> "X(" ^ string_of_ltl a ^ ")"
  | LG a -> "G(" ^ string_of_ltl a ^ ")"
  | LAnd (a,b) -> wrap 3 (string_of_ltl ~ctx:3 a ^ " and " ^ string_of_ltl ~ctx:3 b)
  | LOr (a,b) -> wrap 2 (string_of_ltl ~ctx:2 a ^ " or " ^ string_of_ltl ~ctx:2 b)
  | LImp (a,b) -> wrap 1 (string_of_ltl ~ctx:1 a ^ " -> " ^ string_of_ltl ~ctx:1 b)

let normalize_infix s =
  let prefix = "infix " in
  if String.length s > String.length prefix && String.sub s 0 (String.length prefix) = prefix
  then String.sub s (String.length prefix) (String.length s - String.length prefix)
  else s

let rec string_of_term t =
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

let uniq_terms terms =
  let rec aux seen acc = function
    | [] -> List.rev acc
    | t::ts ->
        let key = string_of_term t in
        if List.mem key seen then aux seen acc ts
        else aux (key :: seen) (t :: acc) ts
  in
  aux [] [] terms

let term_of_var env name = mk_term (term_var env name)
let relop_id = function
  | REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="
let term_of_instance_var env inst_name node_name var_name =
  let inst_field = rec_var_name env inst_name in
  let inst_prefix = prefix_for_node node_name in
  let inner_field = inst_prefix ^ var_name in
  let base = qdot (qid1 env.rec_name) inst_field in
  mk_term (Tident (qdot base inner_field))

let expr_of_instance_var env inst_name node_name var_name =
  let inst_field = rec_var_name env inst_name in
  let inst_prefix = prefix_for_node node_name in
  let inner_field = inst_prefix ^ var_name in
  let base = qdot (qid1 env.rec_name) inst_field in
  mk_expr (Eident (qdot base inner_field))
