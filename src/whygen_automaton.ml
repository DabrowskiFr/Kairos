open Ast
open Whygen_support
open Whygen_automaton_core

let monitor_state_type = "mon_state"
let monitor_state_name = "__mon_state"
let monitor_state_ctor i = Printf.sprintf "Mon%d" i
let monitor_state_expr i = IVar (monitor_state_ctor i)

let sanitize_ident s =
  let buf = Buffer.create (String.length s) in
  let add_underscore () =
    if Buffer.length buf = 0 || Buffer.nth buf (Buffer.length buf - 1) <> '_' then
      Buffer.add_char buf '_'
  in
  String.iter
    (fun c ->
       match c with
       | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> Buffer.add_char buf c
       | _ -> add_underscore ())
    s;
  let out = Buffer.contents buf in
  let out = String.lowercase_ascii out in
  let out =
    let len = String.length out in
    if len > 0 && out.[len - 1] = '_' then String.sub out 0 (len - 1) else out
  in
  let out = if out = "" then "atom" else out in
  let starts_with_digit =
    match out.[0] with '0' .. '9' -> true | _ -> false
  in
  if starts_with_digit then "atom_" ^ out else out

let make_atom_names atom_exprs =
  let used = Hashtbl.create 16 in
  let fresh base =
    let rec loop n =
      let name = if n = 0 then base else base ^ "_" ^ string_of_int n in
      if Hashtbl.mem used name then loop (n + 1)
      else (Hashtbl.add used name (); name)
    in
    loop 0
  in
  List.map
    (fun (_atom, expr) ->
       let base =
         "atom_" ^ sanitize_ident (Whygen_support.string_of_iexpr expr)
       in
       fresh base)
    atom_exprs

let iexpr_to_why ~prefix ~inputs =
  let rec go = function
    | ILitInt n -> string_of_int n
    | ILitBool b -> if b then "true" else "false"
    | IVar x ->
        if List.mem x inputs then "v." ^ prefix ^ Whygen_support.pre_input_name x
        else "v." ^ prefix ^ x
    | IScan1 (_,e) -> go e
    | IScan (_,_,e) -> go e
    | IPar e -> "(" ^ go e ^ ")"
    | IUn (Neg, a) -> "(-" ^ go a ^ ")"
    | IUn (Not, a) -> "(not " ^ go a ^ ")"
    | IBin (op,a,b) ->
        let op_str = Whygen_support.binop_id op in
        "(" ^ go a ^ " " ^ op_str ^ " " ^ go b ^ ")"
  in
  go

let rec collect_atoms_ltl f acc =
  match f with
  | LTrue | LFalse -> acc
  | LAtom a -> if List.exists ((=) a) acc then acc else a :: acc
  | LNot a | LX a | LG a -> collect_atoms_ltl a acc
  | LAnd (a,b) | LOr (a,b) | LImp (a,b) ->
      collect_atoms_ltl b (collect_atoms_ltl a acc)

let collect_atoms_contract = function
  | Requires f | Ensures f | Assume f | Guarantee f | Lemma f ->
      collect_atoms_ltl f []
  | Invariant _ | InvariantState _ | InvariantStateRel _ | InvariantFormula _ -> []

let relop_to_binop = function
  | REq -> Eq
  | RNeq -> Neq
  | RLt -> Lt
  | RLe -> Le
  | RGt -> Gt
  | RGe -> Ge

let fold_var_of_hexpr fold_map h =
  List.find_map (fun (h', name) -> if h = h' then Some name else None) fold_map

let hexpr_to_iexpr ~inputs ~fold_map = function
  | HNow (IScan1 _ as e) ->
      begin match fold_var_of_hexpr fold_map (HNow e) with
      | Some name -> Some (IVar name)
      | None -> None
      end
  | HNow (IScan _ as e) ->
      begin match fold_var_of_hexpr fold_map (HNow e) with
      | Some name -> Some (IVar name)
      | None -> None
      end
  | HNow e -> Some e
  | HScan1 _ as h ->
      begin match fold_var_of_hexpr fold_map h with
      | Some name -> Some (IVar name)
      | None -> None
      end
  | HScan _ as h ->
      begin match fold_var_of_hexpr fold_map h with
      | Some name -> Some (IVar name)
      | None -> None
      end
  | HFold _ as h ->
      begin match fold_var_of_hexpr fold_map h with
      | Some name -> Some (IVar name)
      | None -> None
      end
  | HPre (IVar x, _) when List.mem x inputs ->
      Some (IVar (Whygen_support.pre_input_old_name x))
  | _ -> None

let infer_iexpr_type ~var_types =
  let rec go = function
    | ILitBool _ -> Some TBool
    | ILitInt _ -> Some TInt
    | IVar x -> List.assoc_opt x var_types
    | IScan1 _ | IScan _ -> None
    | IPar e -> go e
    | IUn (Not, _) -> Some TBool
    | IUn (Neg, _) -> Some TInt
    | IBin (And, _, _) | IBin (Or, _, _) -> Some TBool
    | IBin (Eq, _, _) | IBin (Neq, _, _) -> Some TBool
    | IBin (Lt, _, _) | IBin (Le, _, _) | IBin (Gt, _, _) | IBin (Ge, _, _) -> Some TBool
    | IBin (Add, _, _) | IBin (Sub, _, _) | IBin (Mul, _, _) | IBin (Div, _, _) -> Some TInt
  in
  go

let mk_bool_eq a b =
  IBin (Or,
        IBin (And, a, b),
        IBin (And, IUn (Not, a), IUn (Not, b)))

let mk_bool_neq a b =
  IBin (Or,
        IBin (And, a, IUn (Not, b)),
        IBin (And, IUn (Not, a), b))

let atom_to_iexpr ~inputs ~var_types ~fold_map = function
  | ARel (h1, r, h2) ->
      begin match hexpr_to_iexpr ~inputs ~fold_map h1,
                  hexpr_to_iexpr ~inputs ~fold_map h2 with
      | Some e1, Some e2 ->
          let ty1 = infer_iexpr_type ~var_types e1 in
          let ty2 = infer_iexpr_type ~var_types e2 in
          begin match ty1, ty2, r with
          | Some TBool, Some TBool, REq -> Some (mk_bool_eq e1 e2)
          | Some TBool, Some TBool, RNeq -> Some (mk_bool_neq e1 e2)
          | _ -> Some (IBin (relop_to_binop r, e1, e2))
          end
      | _ -> None
      end
  | APred _ -> None

let atom_to_var_rel name =
  ARel (HNow (IVar name), REq, HNow (ILitBool true))

let rec replace_atoms_ltl atom_map f =
  match f with
  | LTrue | LFalse -> f
  | LAtom a ->
      begin match List.assoc_opt a atom_map with
      | Some name -> LAtom (atom_to_var_rel name)
      | None -> LAtom a
      end
  | LNot a -> LNot (replace_atoms_ltl atom_map a)
  | LAnd (a,b) -> LAnd (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LOr (a,b) -> LOr (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LImp (a,b) -> LImp (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LX a -> LX (replace_atoms_ltl atom_map a)
  | LG a -> LG (replace_atoms_ltl atom_map a)

let replace_atoms_contract atom_map = function
  | Requires f -> Requires (replace_atoms_ltl atom_map f)
  | Ensures f -> Ensures (replace_atoms_ltl atom_map f)
  | Assume f -> Assume (replace_atoms_ltl atom_map f)
  | Guarantee f -> Guarantee (replace_atoms_ltl atom_map f)
  | Lemma f -> Lemma (replace_atoms_ltl atom_map f)
  | InvariantFormula f -> InvariantFormula (replace_atoms_ltl atom_map f)
  | InvariantStateRel (is_eq, st, f) ->
      InvariantStateRel (is_eq, st, replace_atoms_ltl atom_map f)
  | Invariant _ as c -> c
  | InvariantState _ as c -> c

let fold_map_for_contracts (cs:contract list) =
  let folds : Whygen_support.fold_info list =
    Whygen_collect.collect_folds_from_contracts cs
  in
  List.map (fun (fi:Whygen_support.fold_info) -> (fi.h, fi.acc)) folds

let fold_origin_suffix fold_map name =
  match List.find_opt (fun (_h, acc) -> acc = name) fold_map with
  | None -> ""
  | Some (h, _) ->
      " (" ^ Whygen_support.string_of_hexpr h ^ ")"

let rec fold_vars_in_iexpr acc = function
  | IVar v -> if List.mem v acc then acc else v :: acc
  | ILitInt _ | ILitBool _ -> acc
  | IScan1 (_, e) | IScan (_, _, e) | IPar e -> fold_vars_in_iexpr acc e
  | IUn (_, e) -> fold_vars_in_iexpr acc e
  | IBin (_, a, b) -> fold_vars_in_iexpr (fold_vars_in_iexpr acc a) b

let fold_origin_suffix_for_expr fold_map e =
  let vars = fold_vars_in_iexpr [] e in
  let origins =
    List.filter_map
      (fun v ->
         match List.find_opt (fun (_h, acc) -> acc = v) fold_map with
         | None -> None
         | Some (h, _) -> Some (v, h))
      vars
  in
  match origins with
  | [] -> ""
  | _ ->
      let parts =
        List.map
          (fun (v, h) -> v ^ " = " ^ Whygen_support.string_of_hexpr h)
          origins
      in
      " (" ^ String.concat ", " parts ^ ")"

let transform_node (n:node) : node =
  let fold_map = fold_map_for_contracts n.contracts in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let atoms =
    List.fold_left
      (fun acc c -> collect_atoms_contract c @ acc)
      []
      n.contracts
    |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
    |> List.sort_uniq compare
  in
  if atoms = [] then n
  else
    let atom_exprs =
      List.filter_map
        (fun a ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> Some (a, e)
           | None -> None)
        atoms
    in
    let atom_names = make_atom_names atom_exprs in
    let atom_map =
      List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
    in
    let atom_named_exprs =
      List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
    in
    let atom_locals =
      List.map (fun name -> { vname = name; vty = TBool }) atom_names
    in
    let atom_assigns =
      List.map
        (fun (a, name) ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> SAssign (name, e)
           | None -> SSkip
        )
        atom_map
    in
    let atom_invariants =
      List.map (fun (name, e) -> Invariant (name, HNow e)) atom_named_exprs
    in
    let trans =
      List.map
        (fun (t:transition) ->
           let contracts = List.map (replace_atoms_contract atom_map) t.contracts in
           let body = t.body @ atom_assigns in
           { t with contracts; body })
        n.trans
    in
    let contracts = List.map (replace_atoms_contract atom_map) n.contracts in
    { n with locals = n.locals @ atom_locals; contracts = contracts @ atom_invariants; trans }


let combine_contracts_for_monitor contracts =
  let rec mk_and = function
    | [] -> LTrue
    | [x] -> x
    | x :: xs -> LAnd (x, mk_and xs)
  in
  let assumes, guarantees =
    List.fold_left
      (fun (a, g) c ->
         match c with
         | Requires f | Assume f -> (f :: a, g)
         | Ensures f | Guarantee f -> (a, f :: g)
         | Lemma _ | InvariantFormula _ -> (a, g)
         | _ -> (a, g))
      ([], [])
      contracts
  in
  let a = mk_and (List.rev assumes) in
  let g = mk_and (List.rev guarantees) in
  match assumes, guarantees with
  | [], [] -> LTrue
  | [], _ -> g
  | _ , [] -> LImp (a, LTrue)
  | _ -> LImp (a, g)

let monitor_update_stmts atom_names states transitions =
  let mon = monitor_state_name in
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (i, vals, j) ->
       let per_src =
         match Hashtbl.find_opt by_src i with
         | Some m -> m
         | None ->
             let m = Hashtbl.create 16 in
             Hashtbl.add by_src i m;
             m
       in
       let prev = Hashtbl.find_opt per_src j |> Option.value ~default:[] in
       Hashtbl.replace per_src j (vals :: prev))
    transitions;
  let is_true = function ILitBool true -> true | _ -> false in
  let is_false = function ILitBool false -> true | _ -> false in
  let rec chain = function
    | [] -> SSkip
    | (dst, cond) :: rest ->
        if is_true cond then
          SAssign (mon, monitor_state_expr dst)
        else if is_false cond then
          chain rest
        else
          SIf (cond, [SAssign (mon, monitor_state_expr dst)], [chain rest])
  in
  let per_state =
    List.init (List.length states) (fun i -> i)
    |> List.map (fun i ->
      match Hashtbl.find_opt by_src i with
      | None -> (i, SSkip)
      | Some per_src ->
          let dests =
            Hashtbl.fold
              (fun dst vals_list acc ->
                 let cond = valuations_to_iexpr atom_names vals_list in
                 (dst, cond) :: acc)
              per_src
              []
          in
          let dests = List.sort_uniq compare dests in
          (i, chain dests))
  in
  let branches =
    List.map
      (fun (i, body) -> (monitor_state_ctor i, [body]))
      per_state
  in
  match branches with
  | [] -> []
  | _ -> [SMatch (IVar mon, branches, [])]

let monitor_assert bad_idx =
  if bad_idx < 0 then []
  else
    [SAssert (LAtom (ARel (HNow (IVar monitor_state_name),
                          RNeq,
                          HNow (monitor_state_expr bad_idx))))]

let transform_node_monitor (n:node) : node =
  let fold_map = fold_map_for_contracts n.contracts in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let atoms =
    List.fold_left
      (fun acc c -> collect_atoms_contract c @ acc)
      []
      n.contracts
    |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
    |> List.sort_uniq compare
  in
  let atom_exprs =
    List.filter_map
      (fun a ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map a with
         | Some e -> Some (a, e)
         | None -> None)
      atoms
  in
  let atom_names = make_atom_names atom_exprs in
  let atom_map =
    List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
  in
  let atom_named_exprs =
    List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
  in
  let atom_locals =
    List.map (fun name -> { vname = name; vty = TBool }) atom_names
  in
  let atom_assigns =
    List.map
      (fun (a, name) ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map a with
         | Some e -> SAssign (name, e)
         | None -> SSkip
      )
      atom_map
  in
  let atom_invariants =
    List.map (fun (name, e) -> Invariant (name, HNow e)) atom_named_exprs
  in
  let monitor_local = { vname = monitor_state_name; vty = TCustom monitor_state_type } in
  let contracts =
    List.map (replace_atoms_contract atom_map) n.contracts
  in
  let spec =
    combine_contracts_for_monitor contracts
    |> replace_atoms_ltl atom_map
    |> simplify_ltl
  in
  let valuations = all_valuations atom_names in
  let states, transitions = build_residual_graph atom_map valuations spec in
  let states, transitions =
    minimize_residual_graph valuations states transitions
  in
  let compat_invariants =
    let n_states = List.length n.states in
    let n_mon = List.length states in
    if n_states = 0 || n_mon = 0 then []
    else
      let state_index = Hashtbl.create n_states in
      List.iteri (fun i s -> Hashtbl.add state_index s i) n.states;
      let prog_out = Array.make n_states [] in
      List.iter
        (fun (t:transition) ->
           match Hashtbl.find_opt state_index t.src,
                 Hashtbl.find_opt state_index t.dst with
           | Some i, Some j ->
               if not (List.mem j prog_out.(i)) then
                 prog_out.(i) <- j :: prog_out.(i)
           | _ -> ())
        n.trans;
      let mon_out = Array.make n_mon [] in
      List.iter
        (fun (i, _vals, j) ->
           if not (List.mem j mon_out.(i)) then
             mon_out.(i) <- j :: mon_out.(i))
        transitions;
      let visited = Array.make_matrix n_states n_mon false in
      let q = Queue.create () in
      begin match Hashtbl.find_opt state_index n.init_state with
      | Some i0 ->
          visited.(i0).(0) <- true;
          Queue.add (i0, 0) q
      | None -> ()
      end;
      while not (Queue.is_empty q) do
        let (i, j) = Queue.take q in
        List.iter
          (fun i' ->
             List.iter
               (fun j' ->
                  if not visited.(i').(j') then (
                    visited.(i').(j') <- true;
                    Queue.add (i', j') q
                  ))
               mon_out.(j))
          prog_out.(i)
      done;
      let mk_or acc f =
        match acc with
        | None -> Some f
        | Some a -> Some (LOr (a, f))
      in
      let mon_eq i =
        LAtom (ARel (HNow (IVar monitor_state_name),
                    REq,
                    HNow (monitor_state_expr i)))
      in
      List.mapi
        (fun si st_name ->
           let disj =
             let acc = ref None in
             for mi = 0 to n_mon - 1 do
               if visited.(si).(mi) then
                 acc := mk_or !acc (mon_eq mi)
             done;
             match !acc with
             | Some f -> simplify_ltl f
             | None -> LFalse
           in
           InvariantStateRel (true, st_name, disj))
        n.states
  in
  let bad_idx =
    let rec find i = function
      | [] -> -1
      | LFalse :: _ -> i
      | _ :: tl -> find (i + 1) tl
    in
    find 0 states
  in
  let monitor_invariants =
    let mon = monitor_state_name in
    let mk_state_formula i f =
      let cond =
        LAtom (ARel (HNow (IVar mon), REq, HNow (monitor_state_expr i)))
      in
      let f = simplify_ltl f in
      let inv = LG (LImp (cond, f)) in
      [Requires inv; Ensures inv]
    in
    let state_invs = List.concat (List.mapi mk_state_formula states) in
    let rec ltl_of_iexpr_now = function
      | ILitBool true -> LTrue
      | ILitBool false -> LFalse
      | IVar name ->
          let h = HNow (IVar name) in
          LAtom (ARel (h, REq, HNow (ILitBool true)))
      | IUn (Not, IVar name) ->
          let h = HNow (IVar name) in
          LAtom (ARel (h, REq, HNow (ILitBool false)))
      | IUn (Not, e) -> LNot (ltl_of_iexpr_now e)
      | IBin (And, a, b) -> LAnd (ltl_of_iexpr_now a, ltl_of_iexpr_now b)
      | IBin (Or, a, b) -> LOr (ltl_of_iexpr_now a, ltl_of_iexpr_now b)
      | _ -> LTrue
    in
    let incoming_prev =
      let by_dst = Hashtbl.create 16 in
      List.iter
        (fun (_i, vals, j) ->
           let prev = Hashtbl.find_opt by_dst j |> Option.value ~default:[] in
           Hashtbl.replace by_dst j (vals :: prev))
        transitions;
      Hashtbl.fold
        (fun j vals_list acc ->
           let cond =
             LAtom (ARel (HNow (IVar mon), REq, HNow (monitor_state_expr j)))
           in
           let guard_expr = valuations_to_iexpr atom_names vals_list in
           let guard = ltl_of_iexpr_now guard_expr in
           let inv = simplify_ltl (LG (LImp (cond, guard))) in
           InvariantFormula inv :: acc)
        by_dst
        []
    in
    state_invs @ incoming_prev
  in
  let monitor_updates = monitor_update_stmts atom_names states transitions in
  let monitor_asserts = monitor_assert bad_idx in
  let trans =
    List.map
      (fun (t:transition) ->
         let contracts = List.map (replace_atoms_contract atom_map) t.contracts in
         let body = t.body @ atom_assigns @ monitor_updates @ monitor_asserts in
         { t with contracts; body })
      n.trans
  in
  { n with locals = n.locals @ atom_locals @ [monitor_local];
           contracts = contracts @ atom_invariants @ monitor_invariants @ compat_invariants;
           trans }

let compile_program_with_transform ?(k_induction=false) ?(prefix_fields=true) transform (p:program) : string =
  let p' = List.map transform p in
  Whygen.compile_program ~k_induction ~prefix_fields p'

let compile_program ?(k_induction=false) ?(prefix_fields=true) (p:program) : string =
  compile_program_with_transform ~k_induction ~prefix_fields transform_node p

let compile_program_monitor ?(k_induction=false) ?(prefix_fields=true) (p:program) : string =
  compile_program_with_transform ~k_induction ~prefix_fields transform_node_monitor p

let dot_program (p:program) : string =
  let buf = Buffer.create 2048 in
  Buffer.add_string buf "digraph LTLAutomata {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let add_node_block n =
    let fold_map = fold_map_for_contracts n.contracts in
    let inputs = List.map (fun v -> v.vname) n.inputs in
    let var_types =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    let atoms =
      List.fold_left
        (fun acc c -> collect_atoms_contract c @ acc)
        []
        n.contracts
      |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
      |> List.sort_uniq compare
    in
    let atom_exprs =
      List.filter_map
        (fun a ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> Some (a, e)
           | None -> None)
        atoms
    in
    let atom_names = make_atom_names atom_exprs in
    let atom_map =
      List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
    in
    let atom_lines =
      List.map2
        (fun (_, e) name ->
           let base = Printf.sprintf "%s = %s" name (Whygen_support.string_of_iexpr e) in
           let suffix = fold_origin_suffix_for_expr fold_map e in
           base ^ suffix)
        atom_exprs atom_names
    in
    let contract_lines =
      List.filter_map
        (function
          | Requires f -> Some ("requires " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Ensures f -> Some ("ensures " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Assume f -> Some ("assume " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Guarantee f -> Some ("guarantee " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Lemma f -> Some ("lemma " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | InvariantFormula f ->
              Some ("invariant " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Invariant (id,h) -> Some ("invariant " ^ id ^ " = " ^ Whygen_support.string_of_hexpr h)
          | InvariantState (is_eq, st) ->
              let op = if is_eq then "=" else "!=" in
              Some ("invariant state " ^ op ^ " " ^ st)
          | InvariantStateRel (is_eq, st, f) ->
              let op = if is_eq then "=" else "!=" in
              Some ("invariant state " ^ op ^ " " ^ st ^ " -> " ^ Whygen_support.string_of_ltl f))
        n.contracts
    in
    let label_lines =
      let atoms_txt =
        if atom_lines = [] then "atoms: (none)" else "atoms:\\n" ^ String.concat "\\n" atom_lines
      in
      let contracts_txt =
        if contract_lines = [] then "contracts: (none)"
        else "contracts:\\n" ^ String.concat "\\n" contract_lines
      in
      escape_dot_label (atoms_txt ^ "\\n\\n" ^ contracts_txt)
    in
    let cluster = Whygen_support.module_name_of_node n.nname in
    let cluster_label =
      if atom_lines = [] then cluster
      else
        cluster ^ "\\n\\n" ^ "atoms:\\n" ^ String.concat "\\n" atom_lines
    in
    Buffer.add_string buf (Printf.sprintf "  subgraph cluster_%s {\n" cluster);
    Buffer.add_string buf (Printf.sprintf "    label=\"%s\";\n" (escape_dot_label cluster_label));
    Buffer.add_string buf "    labelloc=\"b\";\n";
    Buffer.add_string buf "    labeljust=\"l\";\n";
    if atom_names = [] then (
      Buffer.add_string buf (Printf.sprintf "    %s_q0 [shape=circle,label=\"q0\"];\n" cluster);
      Buffer.add_string buf (Printf.sprintf "    %s_info [shape=box,label=\"%s\"];\n" cluster label_lines);
      Buffer.add_string buf (Printf.sprintf "    %s_q0 -> %s_q0 [label=\"step\"];\n" cluster cluster)
    ) else (
      let valuations = all_valuations atom_names in
      List.iteri (fun i vals ->
          let vlabel = escape_dot (valuation_label vals) in
          Buffer.add_string buf (Printf.sprintf "    %s_v%d [shape=circle,label=\"%s\"];\n" cluster i vlabel)
        ) valuations;
      let f_list =
        List.filter_map
          (function
            | Requires f | Ensures f | Assume f | Guarantee f | Lemma f ->
                Some (replace_atoms_ltl atom_map f)
            | _ -> None)
          n.contracts
      in
      let ok vals =
        List.for_all (fun f -> eval_ltl atom_map vals f) f_list
      in
      let len = List.length valuations in
      let edge_map = Hashtbl.create 16 in
      for i = 0 to len - 1 do
        for j = 0 to len - 1 do
          let v = List.nth valuations i in
          let v' = List.nth valuations j in
          if ok v && ok v' then
            let key = (i, j) in
            let prev = Hashtbl.find_opt edge_map key |> Option.value ~default:[] in
            Hashtbl.replace edge_map key (v :: prev)
        done
      done;
      Hashtbl.iter
        (fun (i, j) vals_list ->
           let lbl = valuations_to_formula atom_names vals_list |> escape_dot in
           Buffer.add_string buf (Printf.sprintf "    %s_v%d -> %s_v%d [label=\"%s\"];\n" cluster i cluster j lbl))
        edge_map
    );
    Buffer.add_string buf "  }\n";
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let dot_residual_program (p:program) : string =
  let buf = Buffer.create 4096 in
  Buffer.add_string buf "digraph LTLResidual {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let add_node_block n =
    let fold_map = fold_map_for_contracts n.contracts in
    let inputs = List.map (fun v -> v.vname) n.inputs in
    let var_types =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    let atoms =
      List.fold_left
        (fun acc c -> collect_atoms_contract c @ acc)
        []
        n.contracts
      |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
      |> List.sort_uniq compare
    in
    let atom_exprs =
      List.filter_map
        (fun a ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> Some (a, e)
           | None -> None)
        atoms
    in
    let atom_names = make_atom_names atom_exprs in
    let atom_map =
      List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
    in
    let atom_lines =
      List.map2
        (fun (_, e) name ->
           let base = Printf.sprintf "%s = %s" name (Whygen_support.string_of_iexpr e) in
           let suffix = fold_origin_suffix_for_expr fold_map e in
           base ^ suffix)
        atom_exprs atom_names
    in
    let f_list =
      List.filter_map
        (function
          | Requires f | Ensures f | Assume f | Guarantee f | Lemma f ->
              Some (replace_atoms_ltl atom_map f)
          | _ -> None)
        n.contracts
    in
    let f0 =
      List.fold_left (fun acc f -> simplify_ltl (LAnd (acc, f))) LTrue f_list
    in
    let valuations = all_valuations atom_names in
    let cluster = Whygen_support.module_name_of_node n.nname in
    let cluster_label =
      if atom_lines = [] then cluster
      else
        cluster ^ "\\n\\n" ^ "atoms:\\n" ^ String.concat "\\n" atom_lines
    in
    Buffer.add_string buf (Printf.sprintf "  subgraph cluster_%s {\n" cluster);
    Buffer.add_string buf (Printf.sprintf "    label=\"%s\";\n" (escape_dot_label cluster_label));
    Buffer.add_string buf "    labelloc=\"b\";\n";
    Buffer.add_string buf "    labeljust=\"l\";\n";
    let (states, transitions) = build_residual_graph atom_map valuations f0 in
    let (states, transitions) =
      minimize_residual_graph valuations states transitions
    in
    List.iteri
      (fun i f ->
         let lbl = escape_dot_label (Whygen_support.string_of_ltl f) in
         Buffer.add_string buf (Printf.sprintf "    %s_r%d [shape=box,label=\"%s\"];\n" cluster i lbl))
      states;
    let edge_map = Hashtbl.create 16 in
    List.iter
      (fun (i, vals, j) ->
         let key = (i, j) in
         let prev = Hashtbl.find_opt edge_map key |> Option.value ~default:[] in
         Hashtbl.replace edge_map key (vals :: prev))
      transitions;
    Hashtbl.iter
      (fun (i, j) vals_list ->
         let lbl = valuations_to_formula atom_names vals_list |> escape_dot_label in
         Buffer.add_string buf (Printf.sprintf "    %s_r%d -> %s_r%d [label=\"%s\"];\n" cluster i cluster j lbl))
      edge_map;
    Buffer.add_string buf "  }\n";
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  Buffer.contents buf

let dot_monitor_program (p:program) : string =
  dot_residual_program p

let dot_product_program (p:program) : string =
  let buf = Buffer.create 4096 in
  Buffer.add_string buf "digraph LTLProduct {\n";
  Buffer.add_string buf "  rankdir=LR;\n";
  let add_node_block n =
    let fold_map = fold_map_for_contracts n.contracts in
    let inputs = List.map (fun v -> v.vname) n.inputs in
    let var_types =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    let atoms =
      List.fold_left
        (fun acc c -> collect_atoms_contract c @ acc)
        []
        n.contracts
      |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
      |> List.sort_uniq compare
    in
    let atom_exprs =
      List.filter_map
        (fun a ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> Some (a, e)
           | None -> None)
        atoms
    in
    let atom_names = make_atom_names atom_exprs in
    let atom_map =
      List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
    in
    let valuations = all_valuations atom_names in
    let f_list =
      List.filter_map
        (function
          | Requires f | Ensures f | Assume f | Guarantee f | Lemma f ->
              Some (replace_atoms_ltl atom_map f)
          | _ -> None)
        n.contracts
    in
    let f0 =
      List.fold_left (fun acc f -> simplify_ltl (LAnd (acc, f))) LTrue f_list
    in
    let cluster = Whygen_support.module_name_of_node n.nname in
    Buffer.add_string buf (Printf.sprintf "  subgraph cluster_%s {\n" cluster);
    Buffer.add_string buf (Printf.sprintf "    label=\"%s\";\n" cluster);
    let (states, transitions) = build_residual_graph atom_map valuations f0 in
    let (states, transitions) =
      minimize_residual_graph valuations states transitions
    in
    List.iteri
      (fun si st ->
         List.iteri
           (fun ri rf ->
              let lbl =
                escape_dot (st ^ " | " ^ Whygen_support.string_of_ltl rf)
              in
              Buffer.add_string buf (Printf.sprintf "    %s_s%d_r%d [shape=box,label=\"%s\"];\n" cluster si ri lbl))
           states)
      n.states;
    List.iter
      (fun t ->
         let src_idx = List.find_opt (fun (_i,s) -> s = t.src) (List.mapi (fun i s -> (i,s)) n.states) in
         let dst_idx = List.find_opt (fun (_i,s) -> s = t.dst) (List.mapi (fun i s -> (i,s)) n.states) in
         match src_idx, dst_idx with
         | Some (si,_), Some (di,_) ->
             let edge_map = Hashtbl.create 16 in
             List.iter
               (fun (ri, vals, rj) ->
                  let key = (ri, rj) in
                  let prev = Hashtbl.find_opt edge_map key |> Option.value ~default:[] in
                  Hashtbl.replace edge_map key (vals :: prev))
               transitions;
             Hashtbl.iter
               (fun (ri, rj) vals_list ->
                  let lbl = valuations_to_formula atom_names vals_list |> escape_dot in
                  Buffer.add_string buf (Printf.sprintf "    %s_s%d_r%d -> %s_s%d_r%d [label=\"%s\"];\n" cluster si ri cluster di rj lbl))
               edge_map
         | _ -> ())
      n.trans;
    Buffer.add_string buf "  }\n";
  in
  List.iter add_node_block p;
  Buffer.add_string buf "}\n";
  Buffer.contents buf
