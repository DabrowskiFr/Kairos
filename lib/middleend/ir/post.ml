open Ast
open Formula_origin
open Temporal_support

module Abs = Ir
module PT = Product_types

let input_names (n : Abs.node) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Abs.node) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let product_state_of_pt (st : PT.product_state) : Abs.product_state =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state;
    guarantee_state_index = st.guarantee_state;
  }

let product_step_class_of_pt = function
  | PT.Safe -> Abs.Safe
  | PT.Bad_assumption -> Abs.Bad_assumption
  | PT.Bad_guarantee -> Abs.Bad_guarantee

let is_live_product_state ~(analysis : Product_build.analysis) (st : PT.product_state) : bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let is_relevant_product_step ~(analysis : Product_build.analysis) (step : PT.product_step) : bool =
  is_live_product_state ~analysis step.src
  && (analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx)

let same_product_state (a : PT.product_state) (b : PT.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state = b.assume_state
  && a.guarantee_state = b.guarantee_state

let group_key_of_step ~(program_transition_index : int) (step : PT.product_step) : string =
  Printf.sprintf "%d|%s|%d|%d" program_transition_index step.src.prog_state step.src.assume_state
    step.src.guarantee_state

let disj_ltl (fs : ltl list) : ltl option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> LOr (acc, x)) f rest)

let product_transitions ~(analysis : Product_build.analysis) ~(node : Abs.node) :
    Abs.product_contract list =
  let transition_indices =
    node.trans
    |> List.mapi (fun idx t -> (t, idx))
    |> List.to_seq |> Hashtbl.of_seq
  in
  let relevant_steps =
    analysis.exploration.steps
    |> List.filter_map (fun (step : PT.product_step) ->
           if not (is_relevant_product_step ~analysis step) then None
           else
             Option.map (fun idx -> (step, idx)) (Hashtbl.find_opt transition_indices step.prog_transition))
  in
  let safe_group_guards = Hashtbl.create 32 in
  let safe_group_first_dst = Hashtbl.create 32 in
  List.iter
    (fun ((step : PT.product_step), program_transition_index) ->
      match step.step_class with
      | PT.Safe ->
          let key = group_key_of_step ~program_transition_index step in
          let previous = Hashtbl.find_opt safe_group_guards key |> Option.value ~default:[] in
          Hashtbl.replace safe_group_guards key (ltl_of_fo step.guarantee_guard :: previous);
          if not (Hashtbl.mem safe_group_first_dst key) then Hashtbl.add safe_group_first_dst key step.dst
      | PT.Bad_assumption | PT.Bad_guarantee -> ())
    relevant_steps;
  relevant_steps
  |> List.map (fun ((step : PT.product_step), program_transition_index) ->
         let propagates, ensures, forbidden =
           match step.step_class with
           | PT.Safe ->
               let key = group_key_of_step ~program_transition_index step in
               let grouped_ensure =
                 match Hashtbl.find_opt safe_group_guards key with
                 | Some guards -> begin
                     match disj_ltl guards with
                     | Some grouped -> begin
                         match Hashtbl.find_opt safe_group_first_dst key with
                         | Some first_dst when same_product_state first_dst step.dst ->
                             [ Abs.with_origin Internal grouped ]
                         | _ -> []
                       end
                     | None -> []
                   end
                 | None -> []
               in
               ([ Abs.with_origin GuaranteeAutomaton (ltl_of_fo step.guarantee_guard) ], grouped_ensure, [])
           | PT.Bad_guarantee ->
               ([], [], [ Abs.with_origin GuaranteeViolation (ltl_of_fo step.guarantee_guard) ])
           | PT.Bad_assumption -> ([], [], [])
         in
         {
           program_transition_index;
           step_class = product_step_class_of_pt step.step_class;
           Abs.product_src = product_state_of_pt step.src;
           product_dst = product_state_of_pt step.dst;
           assume_guard = step.assume_guard;
           guarantee_guard = step.guarantee_guard;
           requires = [];
           propagates;
           ensures;
           forbidden;
         })

type t = { product_transitions : Abs.product_contract list }

let build ~(node : Abs.node) ~(analysis : Product_build.analysis) : t =
  { product_transitions = product_transitions ~analysis ~node }

let apply ~(post_generation : t) (n : Abs.node) : Abs.node =
  { n with product_transitions = post_generation.product_transitions }

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

let apply_program ~(post_generations : (Ast.ident * t) list) (p : Abs.node list) :
    Abs.node list =
  List.map
    (fun (n : Abs.node) ->
      let post_generation =
        match List.assoc_opt n.semantics.sem_nname post_generations with
        | Some pg -> pg
        | None ->
            failwith
              (Printf.sprintf "Missing post generation for normalized node %s"
                 n.semantics.sem_nname)
      in
      apply ~post_generation n)
    p
