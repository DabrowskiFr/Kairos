[@@@ocaml.warning "-8-26-27-32-33"]
open Why3
open Ptree
open Ast

type fold_info = { h: hexpr; acc: string; init: string }
type until_info = { a: ltl; b: ltl; flag: string }
type f_event = { f: ltl; cnt: string; bound: iexpr }
type env = { rec_name: string; rec_vars: string list; ghosts: fold_info list; untils: until_info list; fevents: f_event list }

let loc = Loc.dummy_position
let ident s = { Ptree.id_str = s; id_ats = []; id_loc = loc }
let infix_ident s = { Ptree.id_str = Ident.op_infix s; id_ats = []; id_loc = loc }
let qid1 s = Ptree.Qident (ident s)
let qdot q s = Ptree.Qdot (q, ident s)

let mk_expr desc = { Ptree.expr_desc = desc; expr_loc = loc }
let mk_term desc = { Ptree.term_desc = desc; term_loc = loc }

let default_pty = function
  | TInt -> Ptree.PTtyapp(qid1 "int", [])
  | TBool -> Ptree.PTtyapp(qid1 "bool", [])
  | TReal -> Ptree.PTtyapp(qid1 "real", [])
  | TCustom s -> Ptree.PTtyapp(qid1 s, [])

let binop_id = function
  | Add -> "+" | Sub -> "-" | Mul -> "*" | Div -> "/"
  | Eq -> "=" | Neq -> "<>" | Lt -> "<" | Le -> "<=" | Gt -> ">" | Ge -> ">="
  | And -> "&&" | Or -> "||"

let field env name = mk_expr (Eident (qdot (qid1 env.rec_name) name))
let is_rec_var env x = List.exists ((=) x) env.rec_vars
let term_var env x = if is_rec_var env x then Tident (qdot (qid1 env.rec_name) x) else Tident (qid1 x)
let find_fold env h =
  List.find_map (fun fi -> if fi.h = h then Some fi.acc else None) env.ghosts
let find_until env a b =
  List.find_map (fun u -> if u.a = a && u.b = b then Some u.flag else None) env.untils
let find_f_event env f =
  List.find_map (fun fe -> if fe.f = f then Some fe.cnt else None) env.fevents

let rec string_of_qid = function
  | Ptree.Qident id -> id.id_str
  | Ptree.Qdot (q,id) -> string_of_qid q ^ "." ^ id.id_str

let string_of_const _ = "c"

let rec string_of_term t =
  let open Ptree in
  let aux = string_of_term in
  match t.term_desc with
  | Tconst c -> string_of_const c
  | Ttrue -> "true"
  | Tfalse -> "false"
  | Tident q -> string_of_qid q
  | Tinnfix (a, op, b) -> "(" ^ aux a ^ " " ^ op.id_str ^ " " ^ aux b ^ ")"
  | Tbinop (a, d, b) ->
      let op = match d with
        | Dterm.DTand -> "/\\"
        | Dterm.DTor -> "\\/"
        | Dterm.DTimplies -> "->"
      in "(" ^ aux a ^ " " ^ op ^ " " ^ aux b ^ ")"
  | Tnot a -> "not " ^ aux a
  | Tidapp (q, args) ->
      string_of_qid q ^ "(" ^ String.concat ", " (List.map aux args) ^ ")"
  | Tat (t', id) -> aux t' ^ "@" ^ id.id_str
  | _ -> "?"

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

let relop_to_binop = function
  | REq -> Eq | RNeq -> Neq | RLt -> Lt | RLe -> Le | RGt -> Gt | RGe -> Ge

let hexpr_now = function HNow e -> Some e | _ -> None

let rec ltl_to_iexpr_now (f:ltl) : iexpr =
  match f with
  | LAtom (ARel (h1, r, h2)) ->
      begin match hexpr_now h1, hexpr_now h2 with
      | Some e1, Some e2 -> IBin (relop_to_binop r, e1, e2)
      | _ -> ILitBool true
      end
  | LAtom (APred (_id,hs)) ->
      if List.for_all (fun h -> hexpr_now h <> None) hs then ILitBool true else ILitBool true
  | LNot a -> IUn (Not, ltl_to_iexpr_now a)
  | LAnd (a,b) -> IBin (And, ltl_to_iexpr_now a, ltl_to_iexpr_now b)
  | LOr (a,b) -> IBin (Or, ltl_to_iexpr_now a, ltl_to_iexpr_now b)
  | LImp (a,b) -> IBin (Or, IUn (Not, ltl_to_iexpr_now a), ltl_to_iexpr_now b)
  | LX a | LG a -> ltl_to_iexpr_now a
  | LF (a,_) -> ltl_to_iexpr_now a
  | LU (_a,b) -> ltl_to_iexpr_now b
  | LTrue -> ILitBool true
  | LFalse -> ILitBool false

let rec compile_hexpr ?(old=false) env (h:hexpr) : Ptree.term =
  match find_fold env h with
  | Some name -> mk_term (Tident (qdot (qid1 env.rec_name) name))
  | None ->
      match h with
      | HNow e ->
          let t = compile_term env e in
          if old then mk_term (Tat (t, ident "old")) else t
      | HPre (e,_) ->
          let t = compile_term env e in
          mk_term (Tat (t, ident "old"))
      | HScan1 (_,e) -> compile_term env e
      | HScan (_,_,e) -> compile_term env e
      | HWindow (_,_,e) -> compile_term env e
      | HLet (_id,_h1,h2) -> compile_hexpr env h2

let relop_id = function
  | REq -> "=" | RNeq -> "<>" | RLt -> "<" | RLe -> "<=" | RGt -> ">" | RGe -> ">="

let rec compile_ltl_term env (f:ltl) : Ptree.term =
  match f with
  | LTrue -> mk_term Ttrue
  | LFalse -> mk_term Tfalse
  | LNot a -> mk_term (Tnot (compile_ltl_term env a))
  | LAnd (a,b) -> mk_term (Tbinop (compile_ltl_term env a, Dterm.DTand, compile_ltl_term env b))
  | LOr (a,b) -> mk_term (Tbinop (compile_ltl_term env a, Dterm.DTor, compile_ltl_term env b))
  | LImp (a,b) -> mk_term (Tbinop (compile_ltl_term env a, Dterm.DTimplies, compile_ltl_term env b))
  | LX a -> compile_ltl_term env a
  | LG a -> compile_ltl_term env a
  | LF (a,_) -> compile_ltl_term env a
  | LU (_a,b) -> compile_ltl_term env b
  | LAtom (ARel (h1,r,h2)) ->
      mk_term (Tinnfix (compile_hexpr env h1, infix_ident (relop_id r), compile_hexpr env h2))
  | LAtom (APred (id,hs)) ->
      mk_term (Tidapp (qid1 id, List.map (compile_hexpr env) hs))

type spec_frag = { pre: Ptree.term list; post: Ptree.term list }

let empty_frag = { pre = []; post = [] }

let join_and a b = { pre = a.pre @ b.pre; post = a.post @ b.post }

let rec ltl_spec env (f:ltl) : spec_frag =
  match f with
  | LTrue -> empty_frag
  | LFalse -> { pre = []; post = [mk_term Tfalse] }
  | LNot _ | LAnd _ | LOr _ | LImp _ | LAtom _ ->
      let t = compile_ltl_term env f in
      { pre = []; post = [t] }
  | LX a ->
      (* next: obligation on post-state *)
      let t = compile_ltl_term env a in
      { pre = []; post = [t] }
  | LG a ->
      (* globally: require invariant in pre and post *)
      let inner = ltl_spec env a in
      { pre = inner.pre @ inner.post; post = inner.pre @ inner.post }
  | LF (a,_) ->
      begin match find_f_event env a with
      | Some cnt ->
          let cnt_term = mk_term (Tident (qdot (qid1 env.rec_name) cnt)) in
          let zero = mk_term (Tconst (Constant.int_const BigInt.zero)) in
          let guard = mk_term (Tinnfix (cnt_term, infix_ident "=", zero)) in
          let t = compile_ltl_term env a in
          let obligation = mk_term (Tbinop (guard, Dterm.DTimplies, t)) in
          { pre = []; post = [obligation] }
      | None ->
          (* fallback: require now *)
          let t = compile_ltl_term env a in
          { pre = []; post = [t] }
      end
  | LU (a,b) ->
      begin match find_until env a b with
      | None ->
          (* fallback: require a unless b holds now, and require b now *)
          let tb = compile_ltl_term env b in
          let ta = compile_ltl_term env a in
          let inv = mk_term (Tbinop (mk_term (Tnot tb), Dterm.DTimplies, ta)) in
          { pre = [inv]; post = [inv; tb] }
      | Some flag ->
          let seen = mk_term (Tident (qdot (qid1 env.rec_name) flag)) in
          let tb = compile_ltl_term env b in
          let ta = compile_ltl_term env a in
          let inv = mk_term (Tbinop (mk_term (Tnot seen), Dterm.DTimplies, ta)) in
          let progress = mk_term (Tbinop (seen, Dterm.DTor, tb)) in
          { pre = [inv]; post = [inv; progress] }
      end

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
  | HNow e -> collect_scan_expr e acc
  | HPre (e,_) -> collect_hexpr (HNow e) acc
  | HScan1 (_,e) -> collect_hexpr (HNow e) acc
  | HScan (_,init,e) -> collect_hexpr (HNow init) (collect_hexpr (HNow e) acc)
  | HWindow (_,_,e) -> collect_hexpr (HNow e) acc
  | HLet (_,h1,h2) -> collect_hexpr h1 (collect_hexpr h2 acc)

let rec collect_ltl (f:ltl) acc =
  match f with
  | LTrue | LFalse -> acc
  | LNot a -> collect_ltl a acc
  | LAnd (a,b) | LOr (a,b) | LImp (a,b) | LU (a,b) -> collect_ltl b (collect_ltl a acc)
  | LX a | LG a | LF (a,_) -> collect_ltl a acc
  | LAtom (ARel (h1,_,h2)) -> collect_hexpr h2 (collect_hexpr h1 acc)
  | LAtom (APred (_id,hs)) -> List.fold_left (fun a h -> collect_hexpr h a) acc hs

let collect_untils_from_ltl f acc =
  let rec aux f acc =
    let acc =
      match f with
      | LU (a,b) ->
          if List.exists (fun (a',b') -> a' = a && b' = b) acc
          then acc else (a,b) :: acc
      | _ -> acc
    in
    match f with
    | LTrue | LFalse | LAtom _ -> acc
    | LNot a | LX a | LG a | LF (a,_) -> aux a acc
    | LAnd (a,b) | LOr (a,b) | LImp (a,b) | LU (a,b) -> aux b (aux a acc)
  in
  aux f acc

let fold_name i = Printf.sprintf "__fold%d" i
let fold_init_name i = Printf.sprintf "__fold%d_init" i

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
    ) [] cs |> List.filter (fun h -> match classify_fold h with Some _ -> true | None -> false) in
  let rec aux i acc = function
    | [] -> List.rev acc
    | h::t -> aux (i+1) ({ h; acc = fold_name i; init = fold_init_name i } :: acc) t
  in
  aux 1 [] hexprs

let collect_untils_from_contracts (cs:contract list) =
  let pairs =
    List.fold_left (fun acc c ->
        match c with
        | Requires f | Ensures f | Assume f | Guarantee f -> collect_untils_from_ltl f acc
      ) [] cs
  in
  let rec aux i acc = function
    | [] -> List.rev acc
    | (a,b)::t -> aux (i+1) ({ a; b; flag = Printf.sprintf "__until%d_seen" i } :: acc) t
  in
  aux 1 [] pairs

let collect_f_events_from_contracts (cs:contract list) =
  let rec collect_f f acc =
    match f with
    | LF (a,init) ->
        if List.exists (fun (f',_) -> f' = a) acc then acc else (a,init) :: acc
    | LNot a | LX a | LG a -> collect_f a acc
    | LAnd (a,b) | LOr (a,b) | LImp (a,b) | LU (a,b) -> collect_f b (collect_f a acc)
    | LAtom _ | LTrue | LFalse -> acc
  in
  let fs = List.fold_left (fun acc c ->
      match c with
      | Requires f | Ensures f | Assume f | Guarantee f -> collect_f f acc
    ) [] cs in
  let rec aux i acc = function
    | [] -> List.rev acc
    | (f,init)::t ->
        let bound_expr = match init with Some e -> e | None -> ILitInt 2 in
        aux (i+1) ({ f; cnt = Printf.sprintf "__f%d_cnt" i; bound = bound_expr } :: acc) t
  in
  aux 1 [] fs

let rec compile_stmt env (s:stmt) : Ptree.expr =
  match s with
  | SSkip -> mk_expr (Etuple [])
  | SAssign (x,e) ->
      let tgt =
        if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
      in
      mk_expr (Eassign [(tgt, None, compile_iexpr env e)])
  | SIf (c, tbr, fbr) ->
      mk_expr (Eif (compile_iexpr env c, compile_seq env tbr, compile_seq env fbr))
  | SAssert _ -> mk_expr (Etuple [])
and compile_seq env (lst:stmt list) : Ptree.expr =
  match lst with
  | [] -> mk_expr (Etuple [])
  | [s] -> compile_stmt env s
  | s::rest -> mk_expr (Esequence (compile_stmt env s, compile_seq env rest))

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

let compile_state_branch env st trs : Ptree.reg_branch =
  let st_expr = field env "st" in
  let pat = { pat_desc = Papp (qid1 st, []); pat_loc = loc } in
  let rec chain = function
    | [] -> mk_expr (Etuple [])
    | t::rest ->
        let guard = match t.guard with None -> mk_expr Etrue | Some g -> compile_iexpr env g in
        let assign_dst = mk_expr (Eassign [ (st_expr, None, mk_expr (Eident (qid1 t.dst))) ]) in
        let trans_body = mk_expr (Esequence (compile_seq env t.body, assign_dst)) in
        mk_expr (Eif (guard, trans_body, chain rest))
  in
  let body = chain trs in
  (pat, body)

let compile_transitions env (ts:transition list) : Ptree.expr =
  let by_state =
    List.fold_left
      (fun m t ->
         let prev = Option.value ~default:[] (List.assoc_opt t.src m) in
         (t.src, prev @ [t]) :: List.remove_assoc t.src m)
      [] ts
  in
  let branches = List.map (fun (st,trs) -> compile_state_branch env st trs) by_state in
  mk_expr (Ematch (field env "st", branches @ [({pat_desc=Pwild; pat_loc=loc}, mk_expr (Etuple []))], []))

let compile_node (n:node) : Ptree.ident * Ptree.qualid option * Ptree.decl list * string =
  let module_name = String.capitalize_ascii n.nname in
  let imports = [
    Ptree.Duseimport (loc, false, [qid1 "int.Int", None]);
    Ptree.Duseimport (loc, false, [qid1 "array.Array", None]);
  ] in

  let type_state =
    Ptree.Dtype [
      { td_loc=loc; td_ident=ident "state"; td_params=[]; td_vis=Public; td_mut=false; td_inv=[]; td_wit=None;
        td_def = TDalgebraic (List.map (fun s -> (loc, ident s, [])) n.states) }
    ]
  in

  let folds = collect_folds_from_contracts n.contracts in
  let untils = collect_untils_from_contracts n.contracts in
  let fevents = collect_f_events_from_contracts n.contracts in
  let env =
    { rec_name = "vars";
      rec_vars = "st" :: List.map (fun v -> v.vname) (n.locals @ n.outputs)
                 @ List.concat (List.map (fun fi -> [fi.acc; fi.init]) folds)
                 @ List.map (fun u -> u.flag) untils
                 @ List.map (fun f -> f.cnt) fevents;
      ghosts = folds; untils; fevents }
  in
  (* mutable record vars *)
  let fields : Ptree.field list =
    ( { f_loc=loc; f_ident=ident "st"; f_pty=Ptree.PTtyapp(qid1 "state", []); f_mutable=true; f_ghost=false } )
    :: List.map (fun v -> { f_loc=loc; f_ident=ident v.vname; f_pty=default_pty v.vty; f_mutable=true; f_ghost=false }) (n.locals @ n.outputs)
    @ List.map (fun fi -> { f_loc=loc; f_ident=ident fi.acc; f_pty=Ptree.PTtyapp(qid1 "int", []); f_mutable=true; f_ghost=true }) folds
    @ List.map (fun fi -> { f_loc=loc; f_ident=ident fi.init; f_pty=Ptree.PTtyapp(qid1 "bool", []); f_mutable=true; f_ghost=true }) folds
    @ List.map (fun u -> { f_loc=loc; f_ident=ident u.flag; f_pty=Ptree.PTtyapp(qid1 "bool", []); f_mutable=true; f_ghost=true }) untils
    @ List.map (fun f -> { f_loc=loc; f_ident=ident f.cnt; f_pty=Ptree.PTtyapp(qid1 "int", []); f_mutable=true; f_ghost=true }) fevents
  in
  let type_vars =
    Ptree.Dtype [
      { td_loc=loc; td_ident=ident "vars"; td_params=[]; td_vis=Public; td_mut=true; td_inv=[]; td_wit=None;
        td_def = TDrecord fields }
    ]
  in

  let init_fields =
    (qid1 "st", mk_expr (Eident (qid1 n.init_state)))
    :: List.map (fun v -> (qid1 v.vname, match v.vty with
        | TInt -> mk_expr (Econst (Constant.int_const BigInt.zero))
        | TBool -> mk_expr Efalse
        | TReal -> mk_expr (Econst (Constant.real_const_from_string ~radix:10 ~neg:false ~int:"0" ~frac:"" ~exp:None))
        | TCustom _ -> mk_expr (Econst (Constant.int_const BigInt.zero))
      )) (n.locals @ n.outputs)
    @ List.concat (List.map (fun fi ->
        [ (qid1 fi.acc, mk_expr (Econst (Constant.int_const BigInt.zero)));
          (qid1 fi.init, mk_expr Efalse) ]
      ) folds)
    @ List.map (fun u -> (qid1 u.flag, mk_expr Efalse)) untils
    @ List.map (fun f -> (qid1 f.cnt, mk_expr (Econst (Constant.int_const (BigInt.of_int (-1)))))) fevents
  in

  let decl_vars =
    Ptree.Dlet (ident "vars", false, Expr.RKnone, mk_expr (Erecord init_fields))
  in

  let inputs =
    List.map (fun v -> (loc, Some (ident v.vname), false, Some (default_pty v.vty))) n.inputs
  in

  let ghost_updates =
    let fold_updates =
      List.map (fun fi ->
          match classify_fold fi.h with
          | Some (`Scan1 (op,e)) ->
              let target = field env fi.acc in
              let rhs = apply_op op target (compile_iexpr env e) in
              let init_branch =
                mk_expr (Esequence (mk_expr (Eassign [ (target,None, compile_iexpr env e) ]),
                                      mk_expr (Eassign [ (field env fi.init, None, mk_expr Etrue) ])))
              in
              mk_expr (Eif (mk_expr (Enot (field env fi.init)), init_branch, mk_expr (Eassign [ (target, None, rhs) ])))
          | Some (`Scan (op,init,e)) ->
              let target = field env fi.acc in
              let rhs = apply_op op target (compile_iexpr env e) in
              let init_branch =
                mk_expr (Esequence (mk_expr (Eassign [ (target,None, compile_iexpr env init) ]),
                                      mk_expr (Eassign [ (field env fi.init, None, mk_expr Etrue) ])))
              in
              mk_expr (Eif (mk_expr (Enot (field env fi.init)), init_branch, mk_expr (Eassign [ (target, None, rhs) ])))
          | None -> mk_expr (Etuple [])
        ) folds
    in
    let until_updates =
      List.map (fun u ->
          let target = field env u.flag in
          let rhs = mk_expr (Einnfix (target, infix_ident "||", compile_iexpr env (ltl_to_iexpr_now u.b))) in
          mk_expr (Eassign [ (target, None, rhs) ])
        ) untils
    in
    let updates = fold_updates @ until_updates in
    match updates with
    | [] -> mk_expr (Etuple [])
    | [u] -> u
    | u::rest -> List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) u rest
  in

  let f_updates =
    let zero = mk_expr (Econst (Constant.int_const BigInt.zero)) in
    List.map (fun f ->
        let target = field env f.cnt in
        let minus_one = mk_expr (Eidapp (qid1 "(-)", [target; mk_expr (Econst (Constant.int_const BigInt.one))])) in
        let cond_pos = mk_expr (Einnfix (target, infix_ident ">", zero)) in
        let cond_neg = mk_expr (Einnfix (target, infix_ident "<", zero)) in
        let init_bound = compile_iexpr env f.bound in
        mk_expr (Eassign [ (target, None, mk_expr (Eif (cond_neg, init_bound, mk_expr (Eif (cond_pos, minus_one, target)))) ) ])
      ) fevents
  in

  let body =
    let main = compile_transitions env n.trans in
    let with_f =
      match f_updates with
      | [] -> main
      | u::rest ->
          let seq = List.fold_left (fun acc x -> mk_expr (Esequence (acc, x))) u rest in
          mk_expr (Esequence (main, seq))
    in
    mk_expr (Esequence (ghost_updates, with_f))
  in

  let ret_expr =
    match n.outputs with
    | [] -> mk_expr (Econst (Constant.string_const "()"))
    | [v] -> field env v.vname
    | vs -> mk_expr (Etuple (List.map (fun v -> field env v.vname) vs))
  in

  let pre, post =
    List.fold_left
      (fun (pre,post) c ->
         match c with
         | Requires f
         | Assume f ->
             let frag = ltl_spec env f in
             (frag.pre @ frag.post @ pre, post)
         | Ensures f
         | Guarantee f ->
             let frag = ltl_spec env f in
             (pre, frag.pre @ frag.post @ post))
      ([],[]) n.contracts
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
    imports @ [type_state; type_vars; decl_vars; step_decl]
  in

  let show_contract c =
    match c with
    | Requires f -> "requires " ^ Ast.show_ltl f
    | Ensures f -> "ensures " ^ Ast.show_ltl f
    | Assume f -> "assume " ^ Ast.show_ltl f
    | Guarantee f -> "guarantee " ^ Ast.show_ltl f
  in
  let comment =
    let contracts_txt = String.concat "\n  " (List.map show_contract n.contracts) in
    let pre_txt = String.concat "\n    " (List.map string_of_term pre) in
    let post_txt = String.concat "\n    " (List.map string_of_term post) in
    Printf.sprintf "Module %s\n  LTL:\n  %s\n  Relational pre:\n    %s\n  Relational post:\n    %s\n"
      module_name contracts_txt pre_txt post_txt
  in
  (ident module_name, None, decls, comment)

let compile_program (p:program) : string =
  let modules =
    match p with
    | [] -> []
    | nodes -> List.map compile_node nodes
  in
  let buf = Buffer.create 4096 in
  let fmt = Format.formatter_of_buffer buf in
  List.iter (fun (_,_,_,comment) ->
      Format.fprintf fmt "(* %s*)@.@." comment
    ) modules;
  let mlw = Ptree.Modules (List.map (fun (a,b,c,_) -> (a,b,c)) modules) in
  Mlw_printer.pp_mlw_file fmt mlw;
  Format.pp_print_flush fmt ();
  Buffer.contents buf
