open Why3
open Ptree
open Ast

let string_of_qid (q : Ptree.qualid) : string =
  let rec aux = function
    | Ptree.Qident id -> id.id_str
    | Ptree.Qdot (q, id) -> aux q ^ "." ^ id.id_str
  in
  aux q

let string_of_const (c : Constant.constant) : string = Format.asprintf "%a" Constant.print_def c

let string_of_relop (op : relop) : string =
  match op with REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="

let string_of_binop = function
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

let rec string_of_iexpr ?(ctx = 0) (e : iexpr) : string =
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
  | IUn (Neg, a) -> wrap 6 ("-" ^ string_of_iexpr ~ctx:6 a)
  | IUn (Not, a) -> wrap 6 ("not " ^ string_of_iexpr ~ctx:6 a)
  | IBin (op, a, b) ->
      let prec = prec_of_binop op in
      let op_str = string_of_binop op in
      wrap prec (string_of_iexpr ~ctx:prec a ^ " " ^ op_str ^ " " ^ string_of_iexpr ~ctx:prec b)

let string_of_hexpr (h : hexpr) : string =
  match h with
  | HNow e -> "{" ^ string_of_iexpr e ^ "}"
  | HPreK (e, k) ->
      if k = 1 then "pre(" ^ string_of_iexpr e ^ ")" else "pre_k(" ^ string_of_iexpr e ^ ", " ^ string_of_int k ^ ")"

let string_of_fo ?(ctx = 0) (f : fo) : string =
  ignore ctx;
  match f with
  | FRel (h1, r, h2) -> string_of_hexpr h1 ^ " " ^ string_of_relop r ^ " " ^ string_of_hexpr h2
  | FPred (id, hs) -> id ^ "(" ^ String.concat ", " (List.map string_of_hexpr hs) ^ ")"

let rec string_of_ltl ?(ctx = 0) (f : ltl) : string =
  let wrap prec s = if prec < ctx then "(" ^ s ^ ")" else s in
  match f with
  | LTrue -> "true"
  | LFalse -> "false"
  | LAtom a -> string_of_fo a
  | LNot a -> wrap 5 ("not " ^ string_of_ltl ~ctx:5 a)
  | LX a -> "X(" ^ string_of_ltl a ^ ")"
  | LG a -> "G(" ^ string_of_ltl a ^ ")"
  | LW (a, b) -> wrap 2 (string_of_ltl ~ctx:2 a ^ " W " ^ string_of_ltl ~ctx:2 b)
  | LAnd (a, b) -> wrap 3 (string_of_ltl ~ctx:3 a ^ " and " ^ string_of_ltl ~ctx:3 b)
  | LOr (a, b) -> wrap 2 (string_of_ltl ~ctx:2 a ^ " or " ^ string_of_ltl ~ctx:2 b)
  | LImp (a, b) -> wrap 1 (string_of_ltl ~ctx:1 a ^ " -> " ^ string_of_ltl ~ctx:1 b)
