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

let product_transitions ~(analysis : Product_build.analysis) ~(node : Abs.node) :
    Abs.product_contract list =
  let transition_indices =
    node.trans
    |> List.mapi (fun idx t -> (t, idx))
    |> List.to_seq |> Hashtbl.of_seq
  in
  analysis.exploration.steps
  |> List.filter_map (fun (step : PT.product_step) ->
         if not (is_relevant_product_step ~analysis step) then None
         else
           match Hashtbl.find_opt transition_indices step.prog_transition with
           | None -> None
           | Some program_transition_index ->
               let ensures, forbidden =
                 match step.step_class with
                 | PT.Safe ->
                     ([ Abs.with_origin GuaranteeAutomaton (ltl_of_fo step.guarantee_guard) ], [])
                 | PT.Bad_guarantee ->
                     ([], [ Abs.with_origin GuaranteeViolation (ltl_of_fo step.guarantee_guard) ])
                 | PT.Bad_assumption ->
                     ([], [])
               in
               Some
                 {
                   program_transition_index;
                   step_class = product_step_class_of_pt step.step_class;
                   Abs.product_src = product_state_of_pt step.src;
                   product_dst = product_state_of_pt step.dst;
                   assume_guard = step.assume_guard;
                   guarantee_guard = step.guarantee_guard;
                   requires = [];
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
