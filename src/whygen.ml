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

let rec compile_iexpr env (e:iexpr) : Ptree.expr =
  match e with
  | ILitInt n -> mk_expr (Econst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_expr (if b then Etrue else Efalse)
  | IVar x ->
      if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
  | IScan1 (_,e) -> compile_iexpr env e
  | IScan (_,init,e) ->
      (* conservative: compile current value *)
      compile_iexpr env e
  | IPar e -> compile_iexpr env e
  | IUn (Neg, a) -> mk_expr (Eidapp (qid1 "(-)", [compile_iexpr env a]))
  | IUn (Not, a) -> mk_expr (Enot (compile_iexpr env a))
  | IBin (op,a,b) ->
      mk_expr (Einnfix (compile_iexpr env a, infix_ident (binop_id op), compile_iexpr env b))

let rec compile_term env (e:iexpr) : Ptree.term =
  match e with
  | ILitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_term (if b then Ttrue else Tfalse)
  | IVar x -> mk_term (term_var env x)
  | IScan1 (_,e) -> compile_term env e
  | IScan (_,_,e) -> compile_term env e
  | IPar e -> compile_term env e
  | IUn (Neg,a) -> mk_term (Tidapp (qid1 "(-)", [compile_term env a]))
  | IUn (Not,a) -> mk_term (Tnot (compile_term env a))
  | IBin (op,a,b) -> mk_term (Tinnfix (compile_term env a, infix_ident (binop_id op), compile_term env b))

let term_apply_op op t1 t2 =
  match op with
  | OMin ->
      mk_term (Tif (mk_term (Tinnfix (t1, infix_ident "<=", t2)), t1, t2))
  | OMax ->
      mk_term (Tif (mk_term (Tinnfix (t1, infix_ident ">=", t2)), t1, t2))
  | OAdd -> mk_term (Tinnfix (t1, infix_ident "+", t2))
  | OMul -> mk_term (Tinnfix (t1, infix_ident "*", t2))
  | OAnd -> mk_term (Tinnfix (t1, infix_ident "&&", t2))
  | OOr -> mk_term (Tinnfix (t1, infix_ident "||", t2))

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

let rec compile_term_instance env inst_name node_name inputs (e:iexpr) : Ptree.term =
  match e with
  | ILitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_term (if b then Ttrue else Tfalse)
  | IVar x ->
      if List.mem x inputs
      then term_of_instance_var env inst_name node_name (pre_input_name x)
      else term_of_instance_var env inst_name node_name x
  | IScan1 (_,e) -> compile_term_instance env inst_name node_name inputs e
  | IScan (_,_,e) -> compile_term_instance env inst_name node_name inputs e
  | IPar e -> compile_term_instance env inst_name node_name inputs e
  | IUn (Neg,a) ->
      mk_term (Tidapp (qid1 "(-)", [compile_term_instance env inst_name node_name inputs a]))
  | IUn (Not,a) ->
      mk_term (Tnot (compile_term_instance env inst_name node_name inputs a))
  | IBin (op,a,b) ->
      mk_term (Tinnfix (compile_term_instance env inst_name node_name inputs a,
                        infix_ident (binop_id op),
                        compile_term_instance env inst_name node_name inputs b))

let rec compile_hexpr_instance ?(in_post=false) env inst_name node_name inputs pre_k_map (h:hexpr) : Ptree.term =
  match h with
  | HNow e -> compile_term_instance env inst_name node_name inputs e
  | HPre (IVar x,_) when List.mem x inputs ->
      let t = term_of_instance_var env inst_name node_name (pre_input_name x) in
      if in_post then term_old t else t
  | HPre (e,_) -> term_old (compile_term_instance env inst_name node_name inputs e)
  | HPreK (_e,_,_) ->
      begin match List.find_map (fun (h', info) -> if h' = h then Some info else None) pre_k_map with
      | None -> failwith "pre_k not registered (instance)"
      | Some info ->
          let name = List.nth info.names (List.length info.names - 1) in
          term_of_instance_var env inst_name node_name name
      end
  | HScan1 (_,e) -> compile_term_instance env inst_name node_name inputs e
  | HScan (_,_,e) -> compile_term_instance env inst_name node_name inputs e
  | HWindow (_,_,e) -> compile_term_instance env inst_name node_name inputs e
  | HLet (_id,_h1,h2) -> compile_hexpr_instance ~in_post env inst_name node_name inputs pre_k_map h2

let rec compile_ltl_term_instance ?(in_post=false) env inst_name node_name inputs pre_k_map (f:ltl) : Ptree.term =
  match f with
  | LTrue -> mk_term Ttrue
  | LFalse -> mk_term Tfalse
  | LNot a ->
      mk_term (Tnot (compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map a))
  | LAnd (a,b) ->
      mk_term (Tbinop (compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map a,
                       Dterm.DTand,
                       compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map b))
  | LOr (a,b) ->
      mk_term (Tbinop (compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map a,
                       Dterm.DTor,
                       compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map b))
  | LImp (a,b) ->
      mk_term (Tbinop (compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map a,
                       Dterm.DTimplies,
                       compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map b))
  | LX a -> compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map a
  | LG a -> compile_ltl_term_instance ~in_post env inst_name node_name inputs pre_k_map a
  | LAtom (ARel (h1,r,h2)) ->
      mk_term (Tinnfix (compile_hexpr_instance ~in_post env inst_name node_name inputs pre_k_map h1,
                        infix_ident (relop_id r),
                        compile_hexpr_instance ~in_post env inst_name node_name inputs pre_k_map h2))
  | LAtom (APred (id,hs)) ->
      mk_term (Tidapp (qid1 id, List.map (compile_hexpr_instance ~in_post env inst_name node_name inputs pre_k_map) hs))
let term_of_outputs env outputs =
  match outputs with
  | [] -> None
  | [v] -> Some (term_of_var env v.vname)
  | vs -> Some (mk_term (Ttuple (List.map (fun v -> term_of_var env v.vname) vs)))

let rec stmt_list_has_assign name expr = function
  | [] -> false
  | SAssign (x,e) :: _ when x = name && e = expr -> true
  | _ :: rest -> stmt_list_has_assign name expr rest

let stmt_list_is_assign name expr = function
  | [] -> false
  | [SAssign (x,e)] -> x = name && e = expr
  | [SAssign (x,e); SSkip] -> x = name && e = expr
  | [SSkip; SAssign (x,e)] -> x = name && e = expr
  | _ -> false

let is_skip_list lst =
  lst = [] || List.for_all (function SSkip -> true | _ -> false) lst

let scan1_cond op x acc cond =
  match op, cond with
  | OMin, IBin (Le, IVar x1, IVar acc1) -> x = x1 && acc = acc1
  | OMax, IBin (Ge, IVar x1, IVar acc1) -> x = x1 && acc = acc1
  | _ -> false

let op_to_binop = function
  | OAdd -> Some Add
  | OMul -> Some Mul
  | OAnd -> Some And
  | OOr -> Some Or
  | OMin | OMax -> None

let rec find_scan1_init_flag op x acc = function
  | [] -> None
  | SIf (cond, tbr, fbr) :: rest ->
      begin match cond with
      | IUn (Not, IVar init_done) ->
          let has_init = stmt_list_has_assign acc (IVar x) tbr
                         && stmt_list_has_assign init_done (ILitBool true) tbr in
          let has_step =
            match fbr with
            | [SIf (cond2, t2, f2)] ->
                scan1_cond op x acc cond2
                && stmt_list_has_assign acc (IVar x) t2
                && is_skip_list f2
            | _ -> false
          in
          if has_init && has_step then Some init_done else find_scan1_init_flag op x acc rest
      | _ -> find_scan1_init_flag op x acc rest
      end
  | _ :: rest -> find_scan1_init_flag op x acc rest

let rec find_scan_init_flag op x acc init_expr = function
  | [] -> None
  | SIf (cond, tbr, fbr) :: rest ->
      begin match cond with
      | IUn (Not, IVar init_done) ->
          let has_init = stmt_list_has_assign acc init_expr tbr
                         && stmt_list_has_assign init_done (ILitBool true) tbr in
          let has_step =
            match op with
            | OMin | OMax ->
                begin match fbr with
                | [SIf (cond2, t2, f2)] ->
                    scan1_cond op x acc cond2
                    && stmt_list_has_assign acc (IVar x) t2
                    && is_skip_list f2
                | _ -> false
                end
            | _ ->
                begin match op_to_binop op with
                | None -> false
                | Some bop ->
                    let e1 = IBin (bop, IVar acc, IVar x) in
                    let e2 = IBin (bop, IVar x, IVar acc) in
                    stmt_list_is_assign acc e1 fbr || stmt_list_is_assign acc e2 fbr
                end
          in
          if has_init && has_step then Some init_done else find_scan_init_flag op x acc init_expr rest
      | _ -> find_scan_init_flag op x acc init_expr rest
      end
  | _ :: rest -> find_scan_init_flag op x acc init_expr rest

let rec compile_hexpr ?(old=false) ?(prefer_link=false) ?(in_post=false) env (h:hexpr) : Ptree.term =
  let is_const_iexpr = function
    | ILitInt _ | ILitBool _ -> true
    | _ -> false
  in
  match find_link env h, prefer_link with
  | Some id, true ->
      let t = mk_term (term_var env id) in
      if old then term_old t else t
  | _ ->
      match find_fold env h with
      | Some name -> mk_term (Tident (qdot (qid1 env.rec_name) (rec_var_name env name)))
      | None ->
          match h with
          | HNow (IVar x) when old && List.mem x env.inputs ->
              term_of_var env (pre_input_name x)
          | HNow e ->
              let t = compile_term env e in
              if old && not (is_const_iexpr e) then term_old t else t
          | HPre (IVar x,_) when List.mem x env.inputs ->
              let t =
                if in_post
                then term_of_var env (pre_input_old_name x)
                else term_of_var env (pre_input_name x)
              in
              t
          | HPre (e,_) ->
              let t = compile_term env e in
              term_old t
          | HPreK (_e,_,_) ->
              begin match find_pre_k env h with
              | None -> failwith "pre_k not registered"
              | Some info ->
                  let name = List.nth info.names (List.length info.names - 1) in
                  term_of_var env name
              end
          | HScan1 (_,e) -> compile_term env e
          | HScan (_,_,e) -> compile_term env e
          | HWindow (_,_,e) -> compile_term env e
          | HLet (_id,_h1,h2) -> compile_hexpr env h2

let rec compile_ltl_term ?(prefer_link=false) env (f:ltl) : Ptree.term =
  match f with
  | LTrue -> mk_term Ttrue
  | LFalse -> mk_term Tfalse
  | LNot a -> mk_term (Tnot (compile_ltl_term ~prefer_link env a))
  | LAnd (a,b) -> mk_term (Tbinop (compile_ltl_term ~prefer_link env a, Dterm.DTand, compile_ltl_term ~prefer_link env b))
  | LOr (a,b) -> mk_term (Tbinop (compile_ltl_term ~prefer_link env a, Dterm.DTor, compile_ltl_term ~prefer_link env b))
  | LImp (a,b) -> mk_term (Tbinop (compile_ltl_term ~prefer_link env a, Dterm.DTimplies, compile_ltl_term ~prefer_link env b))
  | LX a -> compile_ltl_term ~prefer_link env a
  | LG a -> compile_ltl_term ~prefer_link env a
  | LAtom (ARel (h1,r,h2)) ->
      mk_term (Tinnfix (compile_hexpr ~prefer_link env h1, infix_ident (relop_id r), compile_hexpr ~prefer_link env h2))
  | LAtom (APred (id,hs)) ->
      mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~prefer_link env) hs))

let rec compile_ltl_term_shift ?(prefer_link=false) ?(in_post=false) env shift (f:ltl) : Ptree.term =
  let shift = if shift <= 0 then 0 else 1 in
  match f with
  | LTrue -> mk_term Ttrue
  | LFalse -> mk_term Tfalse
  | LNot a -> mk_term (Tnot (compile_ltl_term_shift ~prefer_link ~in_post env shift a))
  | LAnd (a,b) ->
      mk_term (Tbinop (compile_ltl_term_shift ~prefer_link ~in_post env shift a, Dterm.DTand,
                       compile_ltl_term_shift ~prefer_link ~in_post env shift b))
  | LOr (a,b) ->
      mk_term (Tbinop (compile_ltl_term_shift ~prefer_link ~in_post env shift a, Dterm.DTor,
                       compile_ltl_term_shift ~prefer_link ~in_post env shift b))
  | LImp (a,b) ->
      mk_term (Tbinop (compile_ltl_term_shift ~prefer_link ~in_post env shift a, Dterm.DTimplies,
                       compile_ltl_term_shift ~prefer_link ~in_post env shift b))
  | LX a -> compile_ltl_term_shift ~prefer_link ~in_post env 1 a
  | LG a -> compile_ltl_term_shift ~prefer_link ~in_post env shift a
  | LAtom (ARel (h1,r,h2)) ->
      let old = shift = 0 in
      mk_term (Tinnfix (compile_hexpr ~old ~prefer_link ~in_post env h1, infix_ident (relop_id r),
                        compile_hexpr ~old ~prefer_link ~in_post env h2))
  | LAtom (APred (id,hs)) ->
      let old = shift = 0 in
      mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~old ~prefer_link ~in_post env) hs))

let rec rel_hexpr env (h:hexpr) : hexpr =
  match find_fold env h with
  | Some name -> HNow (IVar name)
  | None ->
      match h with
      | HNow e -> HNow e
      | HPre (e,init) -> HPre (e, init)
      | HPreK (e,init,k) -> HPreK (e, init, k)
      | HScan1 _ | HScan _ | HWindow _ -> h
      | HLet (id, h1, h2) -> HLet (id, rel_hexpr env h1, rel_hexpr env h2)

let rec ltl_relational env (f:ltl) : ltl =
  match f with
  | LTrue | LFalse -> f
  | LNot a -> LNot (ltl_relational env a)
  | LAnd (a,b) -> LAnd (ltl_relational env a, ltl_relational env b)
  | LOr (a,b) -> LOr (ltl_relational env a, ltl_relational env b)
  | LImp (a,b) -> LImp (ltl_relational env a, ltl_relational env b)
  | LX a -> LX (ltl_relational env a)
  | LG a -> LG (ltl_relational env a)
  | LAtom (ARel (h1,r,h2)) ->
      LAtom (ARel (rel_hexpr env h1, r, rel_hexpr env h2))
  | LAtom (APred (id,hs)) ->
      LAtom (APred (id, List.map (rel_hexpr env) hs))

type spec_frag = { pre: Ptree.term list; post: Ptree.term list }

let empty_frag = { pre = []; post = [] }

let join_and a b = { pre = a.pre @ b.pre; post = a.post @ b.post }

let ltl_spec env (f:ltl) : spec_frag =
  let rec has_x = function
    | LX _ -> true
    | LTrue | LFalse | LAtom _ -> false
    | LNot a | LG a -> has_x a
    | LAnd (a,b) | LOr (a,b) | LImp (a,b) -> has_x a || has_x b
  in
  let post_term f =
    if has_x f then
      compile_ltl_term_shift ~prefer_link:true ~in_post:true env 0 f
    else
      compile_ltl_term_shift ~prefer_link:true ~in_post:true env 1 f
  in
  match f with
  | LTrue -> empty_frag
  | LFalse -> { pre = []; post = [mk_term Tfalse] }
  | LNot _ | LAnd _ | LOr _ | LImp _ | LAtom _ | LX _ ->
      let pre_t = compile_ltl_term_shift ~prefer_link:true ~in_post:false env 1 f in
      let post_t = post_term f in
      { pre = [pre_t]; post = [post_t] }
  | LG a ->
      let pre_t = compile_ltl_term_shift ~prefer_link:true ~in_post:false env 1 a in
      let post_t = post_term a in
      { pre = [pre_t]; post = [post_t] }

let rec collect_scan_expr (e:iexpr) acc =
  let acc =
    match e with
    | IScan1 (op, inner) ->
        let h = HScan1 (op, inner) in
        if List.exists ((=) h) acc then acc else h :: acc
    | IScan (op, init, inner) ->
        let h = HScan (op, init, inner) in
        if List.exists ((=) h) acc then acc else h :: acc
    | _ -> acc
  in
  match e with
  | ILitInt _ | ILitBool _ | IVar _ -> acc
  | IScan1 (_op, inner) -> collect_scan_expr inner acc
  | IScan (_op, init, inner) -> collect_scan_expr inner (collect_scan_expr init acc)
  | IBin (_, a, b) -> collect_scan_expr b (collect_scan_expr a acc)
  | IUn (_, a) -> collect_scan_expr a acc
  | IPar a -> collect_scan_expr a acc

let rec collect_hexpr (h:hexpr) acc =
  let acc = if List.exists (fun h' -> h' = h) acc then acc else h :: acc in
  match h with
  | HNow e ->
      begin match e with
      | IScan1 _ | IScan _ -> acc
      | _ -> collect_scan_expr e acc
      end
  | HPre (e,_) -> collect_hexpr (HNow e) acc
  | HPreK (e, init, _) -> collect_hexpr (HNow init) (collect_hexpr (HNow e) acc)
  | HScan1 (_,e) -> collect_hexpr (HNow e) acc
  | HScan (_,init,e) -> collect_hexpr (HNow init) (collect_hexpr (HNow e) acc)
  | HWindow (_,_,e) -> collect_hexpr (HNow e) acc
  | HLet (_,h1,h2) -> collect_hexpr h1 (collect_hexpr h2 acc)

let rec collect_ltl (f:ltl) acc =
  match f with
  | LTrue | LFalse -> acc
  | LNot a -> collect_ltl a acc
  | LAnd (a,b) | LOr (a,b) | LImp (a,b) -> collect_ltl b (collect_ltl a acc)
  | LX a | LG a -> collect_ltl a acc
  | LAtom (ARel (h1,_,h2)) -> collect_hexpr h2 (collect_hexpr h1 acc)
  | LAtom (APred (_id,hs)) -> List.fold_left (fun a h -> collect_hexpr h a) acc hs

let fold_name i = Printf.sprintf "__fold%d" i

let classify_fold h =
  match h with
  | HNow (IScan1 (op,e)) -> Some (`Scan1 (op,e))
  | HNow (IScan (op,init,e)) -> Some (`Scan (op,init,e))
  | HScan1 (op,e) -> Some (`Scan1 (op,e))
  | HScan (op,init,e) -> Some (`Scan (op,init,e))
  | _ -> None

let collect_folds_from_contracts (cs:contract list) =
  let hexprs = List.fold_left (fun acc c ->
      match c with
      | Requires f | Ensures f | Assume f | Guarantee f -> collect_ltl f acc
      | Invariant (_id,h) -> collect_hexpr h acc
      | InvariantState _ | InvariantStateRel _ -> acc
    ) [] cs |> List.filter (fun h -> match classify_fold h with Some _ -> true | None -> false) in
  let rec aux i acc = function
    | [] -> List.rev acc
    | h::t -> aux (i+1) ({ h; acc = fold_name i; init_flag = None } :: acc) t
  in
  aux 1 [] hexprs

let collect_pre_k_from_contracts (cs:contract list) =
  let rec collect_pre_k_hexpr h acc =
    let acc =
      match h with
      | HPreK _ -> if List.exists ((=) h) acc then acc else h :: acc
      | _ -> acc
    in
    match h with
    | HLet (_id, h1, h2) -> collect_pre_k_hexpr h1 (collect_pre_k_hexpr h2 acc)
    | HScan1 _ | HScan _ | HWindow _ | HNow _ | HPre _ | HPreK _ -> acc
  in
  let rec collect_pre_k_ltl f acc =
    match f with
    | LTrue | LFalse -> acc
    | LNot a | LX a | LG a -> collect_pre_k_ltl a acc
    | LAnd (a,b) | LOr (a,b) | LImp (a,b) -> collect_pre_k_ltl b (collect_pre_k_ltl a acc)
    | LAtom (ARel (h1,_,h2)) -> collect_pre_k_hexpr h2 (collect_pre_k_hexpr h1 acc)
    | LAtom (APred (_id,hs)) -> List.fold_left (fun a h -> collect_pre_k_hexpr h a) acc hs
  in
  List.fold_left
    (fun acc c ->
       match c with
       | Requires f | Ensures f | Assume f | Guarantee f -> collect_pre_k_ltl f acc
       | Invariant (_id,h) -> collect_pre_k_hexpr h acc
       | InvariantStateRel (_is_eq, _st, f) -> collect_pre_k_ltl f acc
       | InvariantState _ -> acc)
    [] cs

let build_pre_k_infos (n:node) =
  let transition_contracts =
    List.fold_left (fun acc (t:transition) -> t.contracts @ acc) [] n.trans
  in
  let pre_k_exprs = collect_pre_k_from_contracts (n.contracts @ transition_contracts) in
  let vars = n.inputs @ n.locals @ n.outputs in
  let find_vty name =
    match List.find_opt (fun v -> v.vname = name) vars with
    | Some v -> v.vty
    | None -> failwith ("pre_k unknown variable: " ^ name)
  in
  let make_names base k =
    let rec loop acc i =
      if i > k then List.rev acc
      else loop (Printf.sprintf "%s_%d" base i :: acc) (i + 1)
    in
    loop [] 1
  in
  pre_k_exprs
  |> List.mapi (fun i h ->
         match h with
         | HPreK (e, init, k) ->
             if k <= 0 then failwith "pre_k expects k >= 1";
             let vname =
               match e with
               | IVar x -> x
               | _ -> failwith "pre_k expects a variable as first argument"
             in
             let vty = find_vty vname in
             let base = Printf.sprintf "__pre_k%d_%s" (i + 1) vname in
             let names = make_names base k in
             (h, { h; expr = e; init; names; vty })
         | _ -> failwith "expected pre_k hexpr")


let pre_k_source_expr env (e:iexpr) : Ptree.expr =
  match e with
  | IVar x ->
      if List.mem x env.inputs
      then field env (pre_input_name x)
      else field env x
  | _ -> failwith "pre_k expects a variable as first argument"

let pre_k_source_term env (e:iexpr) : Ptree.term =
  match e with
  | IVar x ->
      if List.mem x env.inputs
      then term_of_var env (pre_input_name x)
      else term_of_var env x
  | _ -> failwith "pre_k expects a variable as first argument"

let rec compile_stmt env call_asserts (s:stmt) : Ptree.expr =
  match s with
  | SSkip -> mk_expr (Etuple [])
  | SAssign (x,e) ->
      let tgt =
        if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
      in
      mk_expr (Eassign [(tgt, None, compile_iexpr env e)])
  | SIf (c, tbr, fbr) ->
      mk_expr (Eif (compile_iexpr env c, compile_seq env call_asserts tbr, compile_seq env call_asserts fbr))
  | SAssert _ -> mk_expr (Etuple [])
  | SCall (inst, args, outs) ->
      let node_name =
        match List.assoc_opt inst env.inst_map with
        | Some n -> n
        | None -> failwith ("unknown instance: " ^ inst)
      in
      let module_name = module_name_of_node node_name in
      let inst_var = field env inst in
      let call_args = inst_var :: List.map (compile_iexpr env) args in
      let call_expr =
        apply_expr (mk_expr (Eident (qdot (qid1 module_name) "step"))) call_args
      in
      let call_expr =
        begin match outs with
      | [] ->
          let tmp = ident "__call" in
          mk_expr (Elet (tmp, false, Expr.RKnone, call_expr, mk_expr (Etuple [])))
      | [x] ->
          let tgt =
            if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
          in
          mk_expr (Eassign [(tgt, None, call_expr)])
      | xs ->
          let tmp_ids = List.mapi (fun i _ -> ident (Printf.sprintf "__call%d" i)) xs in
          let pat =
            { pat_desc = Ptuple (List.map (fun id -> { pat_desc = Pvar id; pat_loc = loc }) tmp_ids);
              pat_loc = loc }
          in
          let assigns =
            List.map2
              (fun x id ->
                 let tgt =
                   if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
                 in
                 mk_expr (Eassign [(tgt, None, mk_expr (Eident (Ptree.Qident id))) ]))
              xs tmp_ids
          in
          let body =
            match assigns with
            | [] -> mk_expr (Etuple [])
            | [a] -> a
            | a::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) a rest
          in
          mk_expr (Ematch (call_expr, [(pat, body)], []))
        end
      in
      let let_bindings, asserts = call_asserts (inst, args, outs) in
      let assert_exprs =
        List.map (fun t -> mk_expr (Eassert (Expr.Assume, t))) asserts
      in
      let call_with_asserts =
        match assert_exprs with
        | [] -> call_expr
        | a :: rest ->
            List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) call_expr (a :: rest)
      in
      let wrap_let (id, pre_expr) acc =
        mk_expr (Elet (id, false, Expr.RKnone, pre_expr, acc))
      in
      List.fold_right wrap_let let_bindings call_with_asserts
and compile_seq env call_asserts (lst:stmt list) : Ptree.expr =
  match lst with
  | [] -> mk_expr (Etuple [])
  | [s] -> compile_stmt env call_asserts s
  | s::rest ->
      mk_expr (Esequence (compile_stmt env call_asserts s, compile_seq env call_asserts rest))

let rec collect_calls_stmt acc s =
  match s with
  | SCall (inst, args, _outs) -> (inst, args) :: acc
  | SIf (_c, tbr, fbr) ->
      let acc = List.fold_left collect_calls_stmt acc tbr in
      List.fold_left collect_calls_stmt acc fbr
  | SAssign _ | SSkip | SAssert _ -> acc

let collect_calls_trans (ts:transition list) =
  List.fold_left
    (fun acc t -> List.fold_left collect_calls_stmt acc t.body)
    [] ts

let rec collect_calls_stmt_full acc s =
  match s with
  | SCall (inst, args, outs) -> (inst, args, outs) :: acc
  | SIf (_c, tbr, fbr) ->
      let acc = List.fold_left collect_calls_stmt_full acc tbr in
      List.fold_left collect_calls_stmt_full acc fbr
  | SAssign _ | SSkip | SAssert _ -> acc

let collect_calls_trans_full (ts:transition list) =
  List.fold_left
    (fun acc t -> List.fold_left collect_calls_stmt_full acc t.body)
    [] ts

let extract_delay_spec (cs:contract list) =
  let rec find_in_ltl = function
    | LG a -> find_in_ltl a
    | LAtom (ARel (HNow (IVar out), REq, HPre (IVar inp, _)))
    | LAtom (ARel (HPre (IVar inp, _), REq, HNow (IVar out))) ->
        Some (out, inp)
    | _ -> None
  in
  List.find_map
    (function
      | Guarantee f | Ensures f -> find_in_ltl f
      | _ -> None)
    cs

let apply_op op e1 e2 =
  match op with
  | OMin ->
      mk_expr (Eif (mk_expr (Einnfix (e1, infix_ident "<=", e2)), e1, e2))
  | OMax ->
      mk_expr (Eif (mk_expr (Einnfix (e1, infix_ident ">=", e2)), e1, e2))
  | OAdd -> mk_expr (Einnfix (e1, infix_ident "+", e2))
  | OMul -> mk_expr (Einnfix (e1, infix_ident "*", e2))
  | OAnd -> mk_expr (Einnfix (e1, infix_ident "&&", e2))
  | OOr -> mk_expr (Einnfix (e1, infix_ident "||", e2))

let compile_state_branch env call_asserts st trs : Ptree.reg_branch =
  let st_expr = field env "st" in
  let pat = { pat_desc = Papp (qid1 st, []); pat_loc = loc } in
  let rec chain = function
    | [] -> mk_expr (Etuple [])
    | t::rest ->
        let guard = match t.guard with None -> mk_expr Etrue | Some g -> compile_iexpr env g in
        let assign_dst = mk_expr (Eassign [ (st_expr, None, mk_expr (Eident (qid1 t.dst))) ]) in
        let trans_body = mk_expr (Esequence (compile_seq env call_asserts t.body, assign_dst)) in
        mk_expr (Eif (guard, trans_body, chain rest))
  in
  let body = chain trs in
  (pat, body)

let compile_transitions env call_asserts (ts:transition list) : Ptree.expr =
  let by_state =
    List.fold_left
      (fun m t ->
         let prev = Option.value ~default:[] (List.assoc_opt t.src m) in
         (t.src, prev @ [t]) :: List.remove_assoc t.src m)
      [] ts
  in
  let branches = List.map (fun (st,trs) -> compile_state_branch env call_asserts st trs) by_state in
  mk_expr (Ematch (field env "st", branches @ [({pat_desc=Pwild; pat_loc=loc}, mk_expr (Etuple []))], []))

let fold_post_terms env fi =
  let acc = term_of_var env fi.acc in
  let acc_old = term_old acc in
  let is_init_old =
    match fi.init_flag with
    | Some init_done ->
        let init_old = term_old (mk_term (term_var env init_done)) in
        mk_term (Tnot init_old)
    | None ->
        term_old (mk_term (term_var env "__first_step"))
  in
  match classify_fold fi.h with
  | Some (`Scan1 (op,e)) ->
      let t_e = compile_term env e in
      let acc_when_init = term_eq acc t_e in
      let acc_when_step = term_eq acc (term_apply_op op acc_old t_e) in
      [ term_implies is_init_old acc_when_init;
        term_implies (mk_term (Tnot is_init_old)) acc_when_step ]
  | Some (`Scan (op,init_e,e)) ->
      let t_init = compile_term env init_e in
      let t_e = compile_term env e in
      let acc_when_init = term_eq acc t_init in
      let acc_when_step = term_eq acc (term_apply_op op acc_old t_e) in
      [ term_implies is_init_old acc_when_init;
        term_implies (mk_term (Tnot is_init_old)) acc_when_step ]
  | None -> []

let compile_node (nodes:node list) (n:node) : Ptree.ident * Ptree.qualid option * Ptree.decl list * string =
  let module_name = module_name_of_node n.nname in
  let instance_imports =
    n.instances
    |> List.map (fun (_, node_name) -> module_name_of_node node_name)
    |> List.sort_uniq String.compare
    |> List.map (fun name -> Ptree.Duseimport (loc, false, [qid1 name, None]))
  in
  let imports =
    [
      Ptree.Duseimport (loc, false, [qid1 "int.Int", None]);
      Ptree.Duseimport (loc, false, [qid1 "array.Array", None]);
    ] @ instance_imports
  in

  let type_state =
    Ptree.Dtype [
      { td_loc=loc; td_ident=ident "state"; td_params=[]; td_vis=Public; td_mut=false; td_inv=[]; td_wit=None;
        td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) n.states) }
    ]
  in

  let folds : fold_info list = collect_folds_from_contracts n.contracts in
  let pre_k_map = build_pre_k_infos n in
  let pre_k_infos = List.map snd pre_k_map in
  let fold_init_links =
    List.filter_map (fun (fi:fold_info) ->
        match classify_fold fi.h with
        | Some (`Scan1 (op, IVar x)) ->
            let vars = List.map (fun v -> v.vname) (n.locals @ n.outputs) in
            let link_for acc =
              let inits = List.map (fun t -> find_scan1_init_flag op x acc t.body) n.trans in
              if List.length inits = List.length n.trans
                 && List.for_all (fun o -> o <> None) inits then
                let init_name = Option.get (List.hd inits) in
                if List.for_all (fun o -> o = Some init_name) inits
                then Some (acc, init_name) else None
              else None
            in
            begin match List.find_map link_for vars with
            | Some (acc, init_done) -> Some (fi.acc, acc, init_done)
            | None -> None
            end
        | Some (`Scan (op, init_expr, IVar x)) ->
            let vars = List.map (fun v -> v.vname) (n.locals @ n.outputs) in
            let link_for acc =
              let inits = List.map (fun t -> find_scan_init_flag op x acc init_expr t.body) n.trans in
              if List.length inits = List.length n.trans
                 && List.for_all (fun o -> o <> None) inits then
                let init_name = Option.get (List.hd inits) in
                if List.for_all (fun o -> o = Some init_name) inits
                then Some (acc, init_name) else None
              else None
            in
            begin match List.find_map link_for vars with
            | Some (acc, init_done) -> Some (fi.acc, acc, init_done)
            | None -> None
            end
        | _ -> None
      ) folds
  in
  let folds =
    List.map (fun fi ->
        match List.find_opt (fun (ghost_acc, _, _) -> ghost_acc = fi.acc) fold_init_links with
        | Some (_, _, init_done) -> { fi with init_flag = Some init_done }
        | None -> fi
      ) folds
  in
  let has_folds = folds <> [] in
  let needs_first_step = List.exists (fun fi -> fi.init_flag = None) folds in
  let inv_links =
    List.filter_map (fun c ->
        match c with
        | Invariant (id,h) -> Some (h, id)
        | _ -> None
      ) n.contracts
  in
  let ghost_links =
    List.filter_map (fun (h,id) ->
        let name =
          List.find_map (fun (fi:fold_info) -> if fi.h = h then Some fi.acc else None) folds
        in
        match name with
        | Some acc -> Some (HNow (IVar acc), id)
        | None -> None
      ) inv_links
  in
  let field_prefix = prefix_for_node n.nname in
  let input_names = List.map (fun v -> v.vname) n.inputs in
  let pre_inputs = List.map pre_input_name input_names in
  let pre_input_olds = List.map pre_input_old_name input_names in
  let base_vars =
    "st"
    :: List.map (fun v -> v.vname) (n.locals @ n.outputs)
    @ List.map fst n.instances
    @ pre_inputs
    @ pre_input_olds
    @ (if needs_first_step then ["__first_step"] else [])
    @ List.map (fun fi -> fi.acc) folds
    @ List.concat_map (fun info -> info.names) pre_k_infos
  in
  let var_map = List.map (fun name -> (name, field_prefix ^ name)) base_vars in
  let env =
    { rec_name = "vars";
      rec_vars = base_vars;
      var_map;
      ghosts = folds;
      links = inv_links @ ghost_links;
      pre_k = pre_k_map;
      inst_map = n.instances;
      inputs = input_names }
  in
  (* mutable record vars *)
  let instance_fields =
    List.map
      (fun (inst_name, node_name) ->
         let mod_name = module_name_of_node node_name in
         { f_loc=loc;
           f_ident=ident (rec_var_name env inst_name);
           f_pty=Ptree.PTtyapp(qdot (qid1 mod_name) "vars", []);
           f_mutable=true;
           f_ghost=false })
      n.instances
  in
  let fields : Ptree.field list =
    ( { f_loc=loc; f_ident=ident (rec_var_name env "st"); f_pty=Ptree.PTtyapp(qid1 "state", []); f_mutable=true; f_ghost=false } )
    :: List.map (fun v -> { f_loc=loc; f_ident=ident (rec_var_name env v.vname); f_pty=default_pty v.vty; f_mutable=true; f_ghost=false }) (n.locals @ n.outputs)
    @ instance_fields
    @ List.map
        (fun v ->
           { f_loc=loc;
             f_ident=ident (rec_var_name env (pre_input_name v.vname));
             f_pty=default_pty v.vty;
             f_mutable=true;
             f_ghost=true })
        n.inputs
    @ List.map
        (fun v ->
           { f_loc=loc;
             f_ident=ident (rec_var_name env (pre_input_old_name v.vname));
             f_pty=default_pty v.vty;
             f_mutable=true;
             f_ghost=true })
        n.inputs
    @ List.concat_map
        (fun info ->
           List.map
             (fun name ->
                { f_loc=loc;
                  f_ident=ident (rec_var_name env name);
                  f_pty=default_pty info.vty;
                  f_mutable=true;
                  f_ghost=true })
             info.names)
        pre_k_infos
    @ (if needs_first_step then
         [ { f_loc=loc; f_ident=ident (rec_var_name env "__first_step"); f_pty=Ptree.PTtyapp(qid1 "bool", []); f_mutable=true; f_ghost=true } ]
       else [])
    @ List.map (fun fi -> { f_loc=loc; f_ident=ident (rec_var_name env fi.acc); f_pty=Ptree.PTtyapp(qid1 "int", []); f_mutable=true; f_ghost=true }) folds
  in
  let type_vars =
    Ptree.Dtype [
      { td_loc=loc; td_ident=ident "vars"; td_params=[]; td_vis=Public; td_mut=true; td_inv=[]; td_wit=None;
        td_def = TDrecord fields }
    ]
  in

  let field_qid name = qid1 (rec_var_name env name) in
  let init_fields =
    (field_qid "st", mk_expr (Eident (qid1 n.init_state)))
    :: List.map (fun v -> (field_qid v.vname, match v.vty with
        | TInt -> mk_expr (Econst (Constant.int_const BigInt.zero))
        | TBool -> mk_expr Efalse
        | TReal -> mk_expr (Econst (Constant.real_const_from_string ~radix:10 ~neg:false ~int:"0" ~frac:"" ~exp:None))
        | TCustom _ -> mk_expr (Econst (Constant.int_const BigInt.zero))
      )) (n.locals @ n.outputs)
    @ List.map
        (fun (inst_name, node_name) ->
           let mod_name = module_name_of_node node_name in
           (field_qid inst_name,
            apply_expr (mk_expr (Eident (qdot (qid1 mod_name) "init_vars")))
              [mk_expr (Etuple [])]))
        n.instances
    @ List.map (fun (v:vdecl) ->
        let init =
          match v.vty with
          | TInt -> mk_expr (Econst (Constant.int_const BigInt.zero))
          | TBool -> mk_expr Efalse
          | TReal -> mk_expr (Econst (Constant.real_const_from_string ~radix:10 ~neg:false ~int:"0" ~frac:"" ~exp:None))
          | TCustom _ -> mk_expr (Econst (Constant.int_const BigInt.zero))
        in
        (field_qid (pre_input_name v.vname), init)
      ) n.inputs
    @ List.map (fun (v:vdecl) ->
        let init =
          match v.vty with
          | TInt -> mk_expr (Econst (Constant.int_const BigInt.zero))
          | TBool -> mk_expr Efalse
          | TReal -> mk_expr (Econst (Constant.real_const_from_string ~radix:10 ~neg:false ~int:"0" ~frac:"" ~exp:None))
          | TCustom _ -> mk_expr (Econst (Constant.int_const BigInt.zero))
        in
        (field_qid (pre_input_old_name v.vname), init)
      ) n.inputs
    @ List.concat_map
        (fun info ->
           let init = compile_iexpr env info.init in
           List.map (fun name -> (field_qid name, init)) info.names)
        pre_k_infos
    @ (if needs_first_step then [ (field_qid "__first_step", mk_expr Etrue) ] else [])
    @ List.map (fun fi -> (field_qid fi.acc, mk_expr (Econst (Constant.int_const BigInt.zero)))) folds
  in

  let init_decl =
    let spc = { Ptree.sp_pre=[]; sp_post=[]; sp_xpost=[]; sp_reads=[]; sp_writes=[]; sp_alias=[]; sp_variant=[]; sp_checkrw=false; sp_diverge=false; sp_partial=false } in
    let fun_body = mk_expr (Erecord init_fields) in
    let args =
      [ (loc, Some (ident "_unit"), false, Some (Ptree.PTtyapp(qid1 "unit", []))) ]
    in
    let fd : Ptree.fundef =
      (ident "init_vars", false, Expr.RKnone, args, None, {pat_desc=Pwild; pat_loc=loc}, Ity.MaskVisible, spc, fun_body)
    in
    Ptree.Drec [fd]
  in

  let vars_param =
    (loc, Some (ident "vars"), false, Some (Ptree.PTtyapp(qid1 "vars", [])))
  in
  let inputs =
    match n.inputs with
    | [] -> [vars_param]
    | _ ->
        vars_param :: List.map (fun v -> (loc, Some (ident v.vname), false, Some (default_pty v.vty))) n.inputs
  in

  let has_pre_inputs = n.inputs <> [] in
  let has_pre_k = pre_k_infos <> [] in
  let ghost_updates =
    if not has_folds && not has_pre_inputs && not has_pre_k then
      mk_expr (Etuple [])
    else
      let first_step = if needs_first_step then Some (field env "__first_step") else None in
      let fold_updates =
        List.map (fun (fi:fold_info) ->
            match classify_fold fi.h with
            | Some (`Scan1 (op,e)) ->
                let target = field env fi.acc in
                let rhs = apply_op op target (compile_iexpr env e) in
                let init_branch = mk_expr (Eassign [ (target,None, compile_iexpr env e) ]) in
                let step_branch = mk_expr (Eassign [ (target, None, rhs) ]) in
                let init_cond =
                  match fi.init_flag, first_step with
                  | Some init_done, _ -> mk_expr (Enot (field env init_done))
                  | None, Some fs -> fs
                  | None, None -> mk_expr Efalse
                in
                mk_expr (Eif (init_cond, init_branch, step_branch))
            | Some (`Scan (op,init,e)) ->
                let target = field env fi.acc in
                let rhs = apply_op op target (compile_iexpr env e) in
                let init_branch = mk_expr (Eassign [ (target,None, compile_iexpr env init) ]) in
                let step_branch = mk_expr (Eassign [ (target, None, rhs) ]) in
                let init_cond =
                  match fi.init_flag, first_step with
                  | Some init_done, _ -> mk_expr (Enot (field env init_done))
                  | None, Some fs -> fs
                  | None, None -> mk_expr Efalse
                in
                mk_expr (Eif (init_cond, init_branch, step_branch))
            | None -> mk_expr (Etuple [])
          ) folds
      in
      let pre_old_updates =
        List.map
          (fun v ->
             let target = field env (pre_input_old_name v.vname) in
             let rhs = field env (pre_input_name v.vname) in
             mk_expr (Eassign [ (target, None, rhs) ]))
          n.inputs
      in
      let pre_updates =
        List.map
          (fun v ->
             let target = field env (pre_input_name v.vname) in
             let rhs = compile_iexpr env (IVar v.vname) in
             mk_expr (Eassign [ (target, None, rhs) ]))
          n.inputs
      in
      let pre_k_updates =
        List.map
          (fun info ->
             let names = info.names in
             let rec shift acc i =
               if i <= 1 then acc
               else
                 let tgt = List.nth names (i - 1) in
                 let src = List.nth names (i - 2) in
                 let assign = mk_expr (Eassign [ (field env tgt, None, field env src) ]) in
                 shift (assign :: acc) (i - 1)
             in
             let shifts = shift [] (List.length names) in
             let first =
               mk_expr (Eassign [ (field env (List.hd names), None, pre_k_source_expr env info.expr) ])
             in
             let all = shifts @ [first] in
             match all with
             | [] -> mk_expr (Etuple [])
             | [u] -> u
             | u::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) u rest)
          pre_k_infos
      in
      let updates =
        let all = fold_updates @ pre_k_updates @ pre_old_updates @ pre_updates in
        match all with
        | [] -> mk_expr (Etuple [])
        | [u] -> u
        | u::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) u rest
      in
      match first_step with
      | Some fs -> mk_expr (Esequence (updates, mk_expr (Eassign [ (fs, None, mk_expr Efalse) ])))
      | None -> updates
  in

  let call_asserts =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    let index_of name lst =
      let rec loop i = function
        | [] -> None
        | x :: xs -> if x = name then Some i else loop (i + 1) xs
      in
      loop 0 lst
    in
    fun (inst_name, _args, outs) ->
      match List.assoc_opt inst_name n.instances with
      | None -> ([], [])
      | Some node_name ->
          match find_node node_name with
          | None -> ([], [])
          | Some inst_node ->
              match extract_delay_spec inst_node.contracts with
              | None -> ([], [])
              | Some (out_name, in_name) ->
                  let output_names = List.map (fun v -> v.vname) inst_node.outputs in
                  begin match index_of out_name output_names with
                  | None -> ([], [])
                  | Some out_idx ->
                      if out_idx >= List.length outs then ([], [])
                      else
                        let out_var = List.nth outs out_idx in
                        let pre_id =
                          ident (Printf.sprintf "__call_pre_%s_%s" inst_name in_name)
                        in
                        let pre_expr =
                          expr_of_instance_var env inst_name node_name (pre_input_name in_name)
                        in
                        let lhs = term_of_var env out_var in
                        let rhs = mk_term (Tident (qid1 pre_id.id_str)) in
                        ([ (pre_id, pre_expr) ], [term_eq lhs rhs])
                  end
  in
  let invariant_assumes =
    let terms =
      List.filter_map
        (function
          | Invariant (id,h) ->
              let lhs = term_of_var env id in
              let rhs = compile_hexpr ~prefer_link:false ~in_post:false env h in
              Some (term_eq lhs rhs)
          | InvariantState (is_eq, st_name) ->
              let st = term_of_var env "st" in
              let rhs = mk_term (Tident (qid1 st_name)) in
              Some ((if is_eq then term_eq else term_neq) st rhs)
          | InvariantStateRel (is_eq, st_name, f) ->
              let st = term_of_var env "st" in
              let rhs = mk_term (Tident (qid1 st_name)) in
              let cond = (if is_eq then term_eq else term_neq) st rhs in
              let body = compile_ltl_term ~prefer_link:true env f in
              Some (term_implies cond body)
          | _ -> None)
        n.contracts
    in
    match terms with
    | [] -> None
    | t :: rest ->
        let mk_assert t = mk_expr (Eassert (Expr.Assume, t)) in
        let seq = List.fold_left (fun acc x -> mk_expr (Esequence (acc, mk_assert x))) (mk_assert t) rest in
        Some seq
  in
  let body =
    let main = compile_transitions env call_asserts n.trans in
    match invariant_assumes with
    | None -> mk_expr (Esequence (ghost_updates, main))
    | Some assumes ->
        mk_expr (Esequence (assumes, mk_expr (Esequence (ghost_updates, main))))
  in

  let ret_expr =
    match n.outputs with
    | [] -> mk_expr (Etuple [])
    | [v] -> field env v.vname
    | vs -> mk_expr (Etuple (List.map (fun v -> field env v.vname) vs))
  in

  let pre, post =
    List.fold_left
      (fun (pre,post) c ->
         let rel = match c with
           | Requires f | Ensures f | Assume f | Guarantee f -> ltl_relational env f
      | Invariant _ | InvariantState _ | InvariantStateRel _ -> LTrue
         in
         match c with
         | Requires _ | Assume _ ->
             let frag = ltl_spec env rel in
             (frag.pre @ pre, post)
         | Ensures _ | Guarantee _ ->
             let frag = ltl_spec env rel in
             (pre, frag.post @ post)
         | Invariant _ | InvariantState _ | InvariantStateRel _ -> (pre, post))
      ([],[]) n.contracts
  in
  let state_post =
    let st = term_of_var env "st" in
    let st_old = term_old st in
    let conj_terms = function
      | [] -> mk_term Ttrue
      | [t] -> t
      | t :: rest ->
          List.fold_left (fun acc x -> mk_term (Tbinop (acc, Dterm.DTand, x))) t rest
    in
    List.fold_left
      (fun post t ->
         let cond_post = term_eq st_old (mk_term (Tident (qid1 t.src))) in
         let guard_terms =
           List.concat_map
             (function
               | Requires f | Assume f ->
                   let rel = ltl_relational env f in
                   let frag = ltl_spec env rel in
                   frag.pre
               | _ -> [])
             t.contracts
         in
         let guard = term_old (conj_terms guard_terms) in
         List.fold_left
           (fun post c ->
              match c with
              | Ensures f | Guarantee f ->
                  let rel = ltl_relational env f in
                  let frag = ltl_spec env rel in
                  let guarded = List.map (fun p -> term_implies guard p) frag.post in
                  (List.map (term_implies cond_post) guarded) @ post
              | _ -> post)
           post t.contracts)
      [] n.trans
  in
  let post = state_post @ post in
  let link_terms_pre, link_terms_post =
    List.fold_left (fun (pre, post) c ->
        match c with
        | Invariant (id,h) ->
            let lhs = term_of_var env id in
            let rhs = compile_hexpr ~prefer_link:false ~in_post:true env h in
            let t = term_eq lhs rhs in
            (pre, t :: post)
        | InvariantState (is_eq, st_name) ->
            let st = term_of_var env "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let t = (if is_eq then term_eq else term_neq) st rhs in
            (pre, t :: post)
        | InvariantStateRel (is_eq, st_name, f) ->
            let st = term_of_var env "st" in
            let rhs = mk_term (Tident (qid1 st_name)) in
            let cond = (if is_eq then term_eq else term_neq) st rhs in
            let body = compile_ltl_term ~prefer_link:true env f in
            let t = term_implies cond body in
            (pre, t :: post)
        | _ -> (pre, post)
      ) ([], []) n.contracts
  in
  let pre_input_post =
    List.map
      (fun v ->
         term_eq (term_of_var env (pre_input_name v.vname)) (term_of_var env v.vname))
      n.inputs
  in
  let pre_input_old_post =
    List.map
      (fun v ->
         term_eq
           (term_of_var env (pre_input_old_name v.vname))
           (term_old (term_of_var env (pre_input_name v.vname))))
      n.inputs
  in
  let pre_k_links =
    List.concat_map
      (fun info ->
         match info.names with
         | [] -> []
         | first :: rest ->
             let first_t =
               term_eq (term_of_var env first) (term_old (pre_k_source_term env info.expr))
             in
             let rec build acc prev = function
               | [] -> List.rev acc
               | name :: tl ->
                   let t = term_eq (term_of_var env name) (term_old (term_of_var env prev)) in
                   build (t :: acc) name tl
             in
             first_t :: build [] first rest)
      pre_k_infos
  in
  let instance_invariants =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    List.concat_map
      (fun (inst_name, node_name) ->
         match find_node node_name with
         | None -> []
         | Some inst_node ->
             List.filter_map (fun c ->
                 match c with
                 | InvariantState (is_eq, st_name) ->
                     let st = term_of_instance_var env inst_name node_name "st" in
                     let rhs = mk_term (Tident (qid1 st_name)) in
                     Some ((if is_eq then term_eq else term_neq) st rhs)
                 | InvariantStateRel (is_eq, st_name, f) ->
                     let st = term_of_instance_var env inst_name node_name "st" in
                     let rhs = mk_term (Tident (qid1 st_name)) in
                     let cond = (if is_eq then term_eq else term_neq) st rhs in
                     let inputs = List.map (fun v -> v.vname) inst_node.inputs in
                     let pre_k_map = build_pre_k_infos inst_node in
                     let body = compile_ltl_term_instance env inst_name node_name inputs pre_k_map f in
                     Some (term_implies cond body)
                 | _ -> None
               ) inst_node.contracts
      ) n.instances
  in
  let instance_input_links_pre, instance_input_links_post =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    let calls = collect_calls_trans n.trans in
    List.fold_left
      (fun (pre_acc, post_acc) (inst_name, args) ->
         match List.assoc_opt inst_name n.instances with
         | None -> (pre_acc, post_acc)
         | Some node_name ->
             match find_node node_name with
             | None -> (pre_acc, post_acc)
             | Some inst_node ->
                 let input_names = List.map (fun v -> v.vname) inst_node.inputs in
                 if List.length input_names <> List.length args then (pre_acc, post_acc)
                 else
                   let pairs = List.combine input_names args in
                  let pre_terms, post_terms =
                     List.fold_left
                       (fun (pre_acc, post_acc) (in_name, arg) ->
                          match arg with
                          | IVar v ->
                              let lhs =
                                term_of_instance_var env inst_name node_name (pre_input_name in_name)
                              in
                              let post_rhs = term_of_var env v in
                              let post_acc = term_eq lhs post_rhs :: post_acc in
                              let pre_rhs =
                                if List.exists (fun iv -> iv.vname = v) n.inputs then
                                  term_of_var env (pre_input_name v)
                                else
                                  term_of_var env v
                              in
                              (term_eq lhs pre_rhs :: pre_acc, post_acc)
                          | _ -> (pre_acc, post_acc))
                       ([], []) pairs
                   in
                   (pre_terms @ pre_acc, post_terms @ post_acc))
      ([], []) calls
  in
  let instance_delay_links_post =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    let calls = collect_calls_trans_full n.trans in
    let index_of name lst =
      let rec loop i = function
        | [] -> None
        | x :: xs -> if x = name then Some i else loop (i + 1) xs
      in
      loop 0 lst
    in
    List.filter_map
      (fun (inst_name, _args, outs) ->
         match List.assoc_opt inst_name n.instances with
         | None -> None
         | Some node_name ->
             match find_node node_name with
             | None -> None
             | Some inst_node ->
                 match extract_delay_spec inst_node.contracts with
                 | None -> None
                 | Some (out_name, in_name) ->
                     let output_names = List.map (fun v -> v.vname) inst_node.outputs in
                     let input_names = List.map (fun v -> v.vname) inst_node.inputs in
                     begin match index_of out_name output_names with
                     | None -> None
                     | Some out_idx ->
                         if out_idx >= List.length outs then None
                         else if not (List.mem in_name input_names) then None
                         else
                           let out_var = List.nth outs out_idx in
                           let lhs = term_of_var env out_var in
                           let rhs =
                             term_old
                               (term_of_instance_var env inst_name node_name (pre_input_name in_name))
                           in
                           Some (term_eq lhs rhs)
                     end)
      calls
  in
  let instance_delay_links_inv =
    let find_node name = List.find_opt (fun nd -> nd.nname = name) nodes in
    let calls = collect_calls_trans_full n.trans in
    let index_of name lst =
      let rec loop i = function
        | [] -> None
        | x :: xs -> if x = name then Some i else loop (i + 1) xs
      in
      loop 0 lst
    in
    let pre_k_first_name_for v =
      List.find_map
        (fun (_, info) ->
           match info.expr, info.names with
           | IVar x, name :: _ when x = v -> Some name
           | _ -> None)
        pre_k_map
    in
    List.filter_map
      (fun (inst_name, args, outs) ->
         match List.assoc_opt inst_name n.instances with
         | None -> None
         | Some node_name ->
             match find_node node_name with
             | None -> None
             | Some inst_node ->
                 match extract_delay_spec inst_node.contracts with
                 | None -> None
                 | Some (out_name, in_name) ->
                     let output_names = List.map (fun v -> v.vname) inst_node.outputs in
                     begin match index_of out_name output_names with
                     | None -> None
                     | Some out_idx ->
                         if out_idx >= List.length outs then None
                         else
                           let out_var = List.nth outs out_idx in
                           match List.assoc_opt in_name (List.combine (List.map (fun v -> v.vname) inst_node.inputs) args) with
                           | Some (IVar v) ->
                               begin match pre_k_first_name_for v with
                               | None -> None
                               | Some name ->
                                   Some (term_eq (term_of_var env out_var) (term_of_var env name))
                               end
                           | _ -> None
                     end)
      calls
  in
  let fold_post = List.concat (List.map (fold_post_terms env) folds) in
  let post = fold_post @ post @ pre_input_post @ pre_input_old_post in
  let output_links =
    let outputs = List.map (fun v -> v.vname) n.outputs in
    List.filter_map (fun out ->
        let assigns =
          List.filter_map (fun t ->
              match List.rev t.body with
              | SAssign (x, IVar v) :: _ when x = out -> Some v
              | _ -> None
            ) n.trans
        in
        match assigns with
        | [] -> None
        | v :: _ ->
            if List.length assigns = List.length n.trans
               && List.for_all ((=) v) assigns
            then Some (term_eq (term_of_var env out) (term_of_var env v))
            else None
      ) outputs
  in
  let fold_links =
    List.map
      (fun (ghost_acc, acc, _init_done) ->
         term_eq (term_of_var env acc) (term_of_var env ghost_acc))
      fold_init_links
  in
  let first_step_links =
    if needs_first_step then
      let first = term_of_var env "__first_step" in
      let st = term_of_var env "st" in
      let is_init = term_eq st (mk_term (Tident (qid1 n.init_state))) in
      let has_incoming = List.exists (fun t -> t.dst = n.init_state) n.trans in
      if has_incoming then
        [ term_implies first is_init ]
      else
        [ term_implies first is_init; term_implies is_init first ]
    else []
  in
  let link_invariants =
    output_links @ fold_links @ first_step_links @ instance_delay_links_inv
  in
  let pre =
    link_invariants @ instance_input_links_pre @ link_terms_pre @ pre
    |> uniq_terms
  in
  let post =
    link_invariants @ instance_input_links_post @ pre_k_links
    @ link_terms_post @ post
    |> uniq_terms
  in
  let post =
    match term_of_outputs env n.outputs with
    | None -> post
    | Some ret_term -> uniq_terms (term_eq (mk_term (Tident (qid1 "result"))) ret_term :: post)
  in

  let step_decl =
    let spc = { Ptree.sp_pre=[]; sp_post=[]; sp_xpost=[]; sp_reads=[]; sp_writes=[]; sp_alias=[]; sp_variant=[]; sp_checkrw=false; sp_diverge=false; sp_partial=false } in
    let mk_post t = (loc, [({pat_desc=Pwild; pat_loc=loc}, t)]) in
    let spc = { spc with sp_pre = List.rev pre; sp_post = List.rev_map mk_post post } in
    let fun_body = mk_expr (Esequence (body, ret_expr)) in
    let fd : Ptree.fundef =
      (ident "step", false, Expr.RKnone, inputs, None, {pat_desc=Pwild; pat_loc=loc}, Ity.MaskVisible, spc, fun_body)
    in
    Ptree.Drec [fd]
  in

  let decls =
    imports @ [type_state; type_vars; init_decl; step_decl]
  in

  let show_contract rel c =
    let to_ltl f = if rel then ltl_relational env f else f in
    match c with
    | Requires f -> "requires " ^ string_of_ltl (to_ltl f)
    | Ensures f -> "ensures " ^ string_of_ltl (to_ltl f)
    | Assume f -> "assume " ^ string_of_ltl (to_ltl f)
    | Guarantee f -> "guarantee " ^ string_of_ltl (to_ltl f)
    | Invariant (id,h) -> "invariant " ^ id ^ " = " ^ string_of_hexpr h
    | InvariantState (is_eq, st_name) ->
        let op = if is_eq then "=" else "!=" in
        "invariant state " ^ op ^ " " ^ st_name
    | InvariantStateRel (is_eq, st_name, f) ->
        let op = if is_eq then "=" else "!=" in
        "invariant state " ^ op ^ " " ^ st_name ^ " -> " ^ string_of_ltl f
  in
  let comment =
    let contracts_txt = String.concat "\n  " (List.map (show_contract false) n.contracts) in
    let pre_txt = String.concat "\n    " (List.map string_of_term pre) in
    let post_txt = String.concat "\n    " (List.map string_of_term post) in
    Printf.sprintf "Module %s\n  LTL (compact):\n  %s\n  Relational (pre/post):\n    pre:\n    %s\n    post:\n    %s\n"
      module_name contracts_txt pre_txt post_txt
  in
  (ident module_name, None, decls, comment)

let compile_program (p:program) : string =
  let modules =
    match p with
    | [] -> []
    | nodes -> List.map (compile_node nodes) nodes
  in
  let buf = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buf in
  List.iter (fun (_,_,_,comment) ->
      Format.fprintf fmt "(* %s*)@.@." comment
    ) modules;
  let mlw = Ptree.Modules (List.map (fun (a,b,c,_) -> (a,b,c)) modules) in
  Mlw_printer.pp_mlw_file fmt mlw;
  Format.pp_print_flush fmt ();
  let out = Buffer.contents buf in
  let replace_all ~sub ~by s =
    if sub = "" then s else
      let sub_len = String.length sub in
      let len = String.length s in
      let b = Buffer.create len in
      let rec loop i =
        if i >= len then ()
        else if i + sub_len <= len && String.sub s i sub_len = sub then (
          Buffer.add_string b by;
          loop (i + sub_len)
        ) else (
          Buffer.add_char b s.[i];
          loop (i + 1)
        )
      in
      loop 0;
      Buffer.contents b
  in
  replace_all ~sub:"(old " ~by:"old(" out
