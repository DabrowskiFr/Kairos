open Ast
open Fo_time
open Formula_origin
open Temporal_support

module Abs = Ir
module PT = Product_types

let dedup_fo (xs : ltl list) : ltl list = List.sort_uniq compare xs

let disj_fo (fs : ltl list) : ltl option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> LOr (acc, x)) f rest)

let guard_ltl_of_transition (t : Abs.transition) : ltl =
  match t.guard with
  | None -> LTrue
  | Some guard ->
      Fo_specs.iexpr_to_fo_with_atoms [] guard
      |> Fo_simplifier.simplify_fo
      |> ltl_of_fo

let input_names (n : Abs.node) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let same_product_state (a : Abs.product_state) (b : Abs.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let guarantee_pre_of_product_state ~(node : Abs.node) ~(analysis : Product_build.analysis) :
    Abs.product_state -> ltl option =
  let is_input = is_input_of_node node in
  let by_dst = ref [] in
  let add dst formulas =
    let rec loop acc = function
      | [] -> List.rev ((dst, formulas) :: acc)
      | (dst', prev) :: rest when same_product_state dst dst' ->
          List.rev_append acc ((dst, dedup_fo (formulas @ prev)) :: rest)
      | x :: rest -> loop (x :: acc) rest
    in
    by_dst := loop [] !by_dst
  in
  List.iter
    (fun (pc : Abs.product_contract) ->
      let ensures =
        pc.ensures
        |> List.filter (fun (f : Abs.contract_formula) ->
               f.origin = Some GuaranteeAutomaton)
        |> Abs.values
        |> List.map (shift_ltl_forward_inputs ~is_input)
      in
      if ensures <> [] then add pc.product_dst ensures)
    node.product_transitions;
  let initial_product_state =
    let st = analysis.exploration.initial_state in
    {
      Abs.prog_state = st.prog_state;
      assume_state_index = st.assume_state;
      guarantee_state_index = st.guarantee_state;
    }
  in
  fun st ->
    let from_ensures =
      List.find_map
        (fun (dst, fs) -> if same_product_state dst st then Some fs else None)
        !by_dst
      |> Option.value ~default:[]
    in
    let from_ensures =
      if same_product_state st initial_product_state then LTrue :: from_ensures else from_ensures
    in
    disj_fo from_ensures

type t = { guarantee_pre_of_product_state : Abs.product_state -> Ast.ltl option }

let build ~(node : Abs.node) ~(analysis : Product_build.analysis) : t =
  { guarantee_pre_of_product_state = guarantee_pre_of_product_state ~node ~analysis }

let add_unique_formula (origin : Formula_origin.t) (f : ltl)
    (xs : Abs.contract_formula list) : Abs.contract_formula list =
  if List.exists (fun (x : Abs.contract_formula) -> x.value = f) xs then xs
  else xs @ [ Abs.with_origin origin f ]

let apply ~(pre_generation : t) (n : Abs.node) : Abs.node =
  let transition_by_index = Array.of_list n.trans in
  let product_transitions =
    List.map
      (fun (pc : Abs.product_contract) ->
        let program_guard =
          if pc.program_transition_index >= 0
             && pc.program_transition_index < Array.length transition_by_index
          then guard_ltl_of_transition transition_by_index.(pc.program_transition_index)
          else LTrue
        in
        let requires =
          match pre_generation.guarantee_pre_of_product_state pc.product_src with
          | None -> pc.requires
          | Some inv -> add_unique_formula GuaranteePropagation inv pc.requires
        in
        let requires =
          add_unique_formula AssumeAutomaton (ltl_of_fo pc.assume_guard) requires
        in
        let requires = add_unique_formula ProgramGuard program_guard requires in
        if requires == pc.requires then pc else { pc with requires })
      n.product_transitions
  in
  { n with product_transitions }

let build_program ~(analyses : (Ast.ident * Product_build.analysis) list) (p : Abs.node list) :
    (Ast.ident * t) list =
  List.map
    (fun (n : Abs.node) ->
      let analysis =
        match List.assoc_opt n.semantics.sem_nname analyses with
        | Some analysis -> analysis
        | None ->
            failwith
              (Printf.sprintf "Missing product analysis for normalized node %s"
                 n.semantics.sem_nname)
      in
      (n.semantics.sem_nname, build ~node:n ~analysis))
    p

let apply_program ~(pre_generations : (Ast.ident * t) list) (p : Abs.node list) :
    Abs.node list =
  List.map
    (fun (n : Abs.node) ->
      let pre_generation =
        match List.assoc_opt n.semantics.sem_nname pre_generations with
        | Some pg -> pg
        | None ->
            failwith
              (Printf.sprintf "Missing pre generation for normalized node %s"
                 n.semantics.sem_nname)
      in
      apply ~pre_generation n)
    p
