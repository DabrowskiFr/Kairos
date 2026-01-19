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

let rec collect_hexpr (h:hexpr) acc =
  let acc = if List.exists (fun h' -> h' = h) acc then acc else h :: acc in
  match h with
  | HNow _ -> acc
  | HPre (e,_) -> collect_hexpr (HNow e) acc
  | HPreK (e, init, _) -> collect_hexpr (HNow init) (collect_hexpr (HNow e) acc)
  | HFold (_,init,e) -> collect_hexpr (HNow init) (collect_hexpr (HNow e) acc)

let rec collect_ltl (f:ltl) acc =
  match f with
  | LTrue | LFalse -> acc
  | LNot a -> collect_ltl a acc
  | LAnd (a,b) | LOr (a,b) | LImp (a,b) -> collect_ltl b (collect_ltl a acc)
  | LX a | LG a -> collect_ltl a acc
  | LAtom f -> collect_fo f acc

and collect_fo (f:fo) acc =
  match f with
  | FTrue | FFalse -> acc
  | FRel (h1,_,h2) -> collect_hexpr h2 (collect_hexpr h1 acc)
  | FPred (_id,hs) -> List.fold_left (fun a h -> collect_hexpr h a) acc hs
  | FNot a -> collect_fo a acc
  | FAnd (a,b) | FOr (a,b) | FImp (a,b) -> collect_fo b (collect_fo a acc)

let fold_name i = Printf.sprintf "__fold%d" i

let classify_fold h =
  match h with
  | HFold (op,init,e) -> Some (`Scan (op,init,e))
  | _ -> None

let collect_folds_from_contracts (cs:contract list) =
  let hexprs = List.fold_left (fun acc c ->
      match c with
      | Requires f | Ensures f | Lemma f | InvariantFormula f ->
          collect_fo f acc
      | Assume f | Guarantee f ->
          collect_ltl f acc
      | Invariant (_id,h) -> collect_hexpr h acc
      | InvariantState _ -> acc
      | InvariantStateRel (_is_eq, _st, f) -> collect_fo f acc
    ) [] cs |> List.filter (fun h -> match classify_fold h with Some _ -> true | None -> false) in
  let rec aux i acc = function
    | [] -> List.rev acc
    | h::t -> aux (i+1) ({ h; acc = fold_name i; init_flag = None } :: acc) t
  in
  aux 1 [] hexprs

let collect_pre_k_from_contracts (cs:contract list) =
  let collect_pre_k_hexpr h acc =
    let acc =
      match h with
      | HPreK _ -> if List.exists ((=) h) acc then acc else h :: acc
      | _ -> acc
    in
    match h with
    | HFold _ | HNow _ | HPre _ | HPreK _ -> acc
  in
  let rec collect_pre_k_ltl f acc =
    match f with
    | LTrue | LFalse -> acc
    | LNot a | LX a | LG a -> collect_pre_k_ltl a acc
    | LAnd (a,b) | LOr (a,b) | LImp (a,b) -> collect_pre_k_ltl b (collect_pre_k_ltl a acc)
    | LAtom f -> collect_pre_k_fo f acc
  and collect_pre_k_fo f acc =
    match f with
    | FTrue | FFalse -> acc
    | FRel (h1,_,h2) -> collect_pre_k_hexpr h2 (collect_pre_k_hexpr h1 acc)
    | FPred (_id,hs) -> List.fold_left (fun a h -> collect_pre_k_hexpr h a) acc hs
    | FNot a -> collect_pre_k_fo a acc
    | FAnd (a,b) | FOr (a,b) | FImp (a,b) -> collect_pre_k_fo b (collect_pre_k_fo a acc)
  in
  List.fold_left
    (fun acc c ->
       match c with
       | Requires f | Ensures f | Lemma f | InvariantFormula f ->
           collect_pre_k_fo f acc
       | Assume f | Guarantee f ->
           collect_pre_k_ltl f acc
       | Invariant (_id,h) -> collect_pre_k_hexpr h acc
       | InvariantStateRel (_is_eq, _st, f) -> collect_pre_k_fo f acc
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
  let normalize_fo f =
    let normalized = normalize_ltl_for_k ~init_for_var (ltl_of_fo f) in
    fo_of_ltl normalized.ltl
  in
  let normalize_contract = function
    | Requires f -> Requires (normalize_fo f)
    | Ensures f -> Ensures (normalize_fo f)
    | Assume f -> Assume (normalize_ltl_for_k ~init_for_var f).ltl
    | Guarantee f -> Guarantee (normalize_ltl_for_k ~init_for_var f).ltl
    | Lemma f -> Lemma (normalize_fo f)
    | InvariantFormula f -> InvariantFormula (normalize_fo f)
    | Invariant _ as c -> c
    | InvariantState _ as c -> c
    | InvariantStateRel (is_eq, st, f) ->
        InvariantStateRel (is_eq, st, normalize_fo f)
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
  | SMatch (_e, branches, def) ->
      let acc =
        List.fold_left
          (fun acc (_ctor, body) -> List.fold_left collect_calls_stmt acc body)
          acc
          branches
      in
      List.fold_left collect_calls_stmt acc def
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
  | SMatch (_e, branches, def) ->
      let acc =
        List.fold_left
          (fun acc (_ctor, body) -> List.fold_left collect_calls_stmt_full acc body)
          acc
          branches
      in
      List.fold_left collect_calls_stmt_full acc def
  | SAssign _ | SSkip | SAssert _ -> acc

let collect_calls_trans_full (ts:transition list) =
  List.fold_left
    (fun acc t -> List.fold_left collect_calls_stmt_full acc t.body)
    [] ts

let extract_delay_spec (cs:contract list) =
  let rec find_in_ltl = function
    | LG a -> find_in_ltl a
    | LAtom (FRel (HNow (IVar out), REq, HPre (IVar inp, _)))
    | LAtom (FRel (HPre (IVar inp, _), REq, HNow (IVar out))) ->
        Some (out, inp)
    | _ -> None
  in
  List.find_map
    (function
      | Guarantee f -> find_in_ltl f
      | Ensures f -> find_in_ltl (ltl_of_fo f)
      | _ -> None)
    cs
