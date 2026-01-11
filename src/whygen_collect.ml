[@@@ocaml.warning "-8-26-27-32-33"]
open Ast
open Whygen_support

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
  | OMin | OMax | OFirst -> None

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
  | HFold (_,init,e) -> collect_hexpr (HNow init) (collect_hexpr (HNow e) acc)
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
  | HFold (op,init,e) -> Some (`Scan (op,init,e))
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
    | HScan1 _ | HScan _ | HFold _ | HWindow _ | HNow _ | HPre _ | HPreK _ -> acc
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
  let init_for_var =
    let table =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> ILitBool false
      | Some TInt -> ILitInt 0
      | Some TReal -> ILitInt 0
      | Some (TCustom _) | None -> ILitInt 0
  in
  let normalize_contract = function
    | Requires f -> Requires (normalize_ltl_for_k ~init_for_var f).ltl
    | Ensures f -> Ensures (normalize_ltl_for_k ~init_for_var f).ltl
    | Assume f -> Assume (normalize_ltl_for_k ~init_for_var f).ltl
    | Guarantee f -> Guarantee (normalize_ltl_for_k ~init_for_var f).ltl
    | Invariant _ as c -> c
    | InvariantState _ as c -> c
    | InvariantStateRel (is_eq, st, f) ->
        InvariantStateRel (is_eq, st, (normalize_ltl_for_k ~init_for_var f).ltl)
  in
  let normalized =
    List.map normalize_contract (n.contracts @ transition_contracts)
  in
  let pre_k_exprs = collect_pre_k_from_contracts normalized in
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
