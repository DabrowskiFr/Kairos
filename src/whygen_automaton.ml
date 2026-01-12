open Ast
open Whygen_support
open Whygen_automaton_core

let atom_name i = Printf.sprintf "__atom_%d" (i + 1)

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
  | Requires f | Ensures f | Assume f | Guarantee f ->
      collect_atoms_ltl f []
  | InvariantStateRel (_is_eq, _st, f) ->
      collect_atoms_ltl f []
  | Invariant _ | InvariantState _ -> []

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
    let atom_map = List.mapi (fun i a -> (a, atom_name i)) atoms in
    let atom_exprs =
      List.filter_map
        (fun (a, name) ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> Some (name, e)
           | None -> None)
        atom_map
    in
    let atom_locals =
      List.map (fun (_, name) -> { vname = name; vty = TBool }) atom_map
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
      List.map (fun (name, e) -> Invariant (name, HNow e)) atom_exprs
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

let compile_program ?(k_induction=false) (p:program) : string =
  let lemma_block_for_node (n:node) =
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
    let pre_k_map = Whygen_collect.build_pre_k_infos n in
    let atom_map = List.mapi (fun i a -> (a, atom_name i)) atoms in
    let atom_exprs =
      List.filter_map
        (fun (a, name) ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e -> Some (name, e)
           | None -> None)
        atom_map
    in
    let prefix = Whygen_support.prefix_for_node n.nname in
    let atom_lemmas =
      List.map
        (fun (name, e) ->
           let expr = iexpr_to_why ~prefix ~inputs e in
           Printf.sprintf
             "  axiom %s_true: forall v:vars. v.%s%s = true <-> %s\n"
             name prefix name expr)
        atom_exprs
    in
    let inv_lemmas =
      List.filter_map
        (function
          | Invariant (id, h) ->
              begin match List.find_map (fun (h', info) -> if h' = h then Some info else None) pre_k_map with
              | None -> None
              | Some info ->
                  let name = List.nth info.names (List.length info.names - 1) in
                  Some (Printf.sprintf
                          "  axiom inv_%s_pre_k: forall v:vars. v.%s%s = v.%s%s\n"
                          id prefix id prefix name)
              end
          | _ -> None)
        n.contracts
    in
    let lemmas = atom_lemmas @ inv_lemmas in
    if lemmas = [] then None
    else Some (Whygen_support.module_name_of_node n.nname, String.concat "" lemmas)
  in
  let lemma_map =
    List.filter_map lemma_block_for_node p
  in
  let p' = List.map transform_node p in
  let out = Whygen.compile_program ~k_induction p' in
  let inject_lemmas s =
    let lines = String.split_on_char '\n' s in
    let rec loop acc current pending in_vars = function
      | [] -> List.rev acc
      | line :: rest ->
          let line_trim =
            if String.length line >= 7 then String.sub line 0 7 else line
          in
          if line_trim = "module " then
            let name =
              String.trim (String.sub line 7 (String.length line - 7))
            in
            let pending = List.assoc_opt name lemma_map in
            loop (line :: acc) (Some name) pending false rest
          else
            begin match current, pending with
            | Some _name, Some block ->
                if String.trim line = "type vars = mutable {" then
                  loop (line :: acc) current pending true rest
                else if in_vars && String.trim line = "}" then
                  loop (block :: line :: acc) current None false rest
                else
                  loop (line :: acc) current pending in_vars rest
            | _ ->
                loop (line :: acc) current pending in_vars rest
            end
    in
    String.concat "\n" (loop [] None None false lines)
  in
  inject_lemmas out

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
    let atom_map = List.mapi (fun i a -> (a, atom_name i)) atoms in
    let atom_names = List.map snd atom_map in
    let atom_lines =
      List.filter_map
        (fun (a, name) ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e ->
               let base = Printf.sprintf "%s = %s" name (Whygen_support.string_of_iexpr e) in
               let suffix = fold_origin_suffix_for_expr fold_map e in
               Some (base ^ suffix)
           | None -> None)
        atom_map
    in
    let contract_lines =
      List.filter_map
        (function
          | Requires f -> Some ("requires " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Ensures f -> Some ("ensures " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Assume f -> Some ("assume " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
          | Guarantee f -> Some ("guarantee " ^ Whygen_support.string_of_ltl (replace_atoms_ltl atom_map f))
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
            | Requires f | Ensures f | Assume f | Guarantee f ->
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
    let atom_map = List.mapi (fun i a -> (a, atom_name i)) atoms in
    let atom_lines =
      List.filter_map
        (fun (a, name) ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
           | Some e ->
               let base = Printf.sprintf "%s = %s" name (Whygen_support.string_of_iexpr e) in
               let suffix = fold_origin_suffix_for_expr fold_map e in
               Some (base ^ suffix)
           | None -> None)
        atom_map
    in
    let atom_names = List.map snd atom_map in
    let f_list =
      List.filter_map
        (function
          | Requires f | Ensures f | Assume f | Guarantee f ->
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
    let atom_map = List.mapi (fun i a -> (a, atom_name i)) atoms in
    let atom_names = List.map snd atom_map in
    let valuations = all_valuations atom_names in
    let f_list =
      List.filter_map
        (function
          | Requires f | Ensures f | Assume f | Guarantee f ->
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
