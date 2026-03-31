open Ast
open Formula_origin
open Temporal_support

module Abs = Ir
module PT = Product_types

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

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

let disj_fo (fs : Fo_formula.t list) : ltl option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> Fo_formula.FOr (acc, x)) f rest |> simplify_fo |> ltl_of_fo)

let automaton_outgoing (grouped : Automaton_types.transition list) :
    (int, Automaton_types.transition list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (((src, _guard, _dst) as edge) : Automaton_types.transition) ->
      let prev = Hashtbl.find_opt tbl src |> Option.value ~default:[] in
      Hashtbl.replace tbl src (edge :: prev))
    grouped;
  tbl

let edges_from_outgoing (outgoing : (int, Automaton_types.transition list) Hashtbl.t) idx =
  Hashtbl.find_opt outgoing idx |> Option.value ~default:[]

let transition_indices (node : Abs.node) : (Abs.transition, int) Hashtbl.t =
  node.trans
  |> List.mapi (fun idx t -> (t, idx))
  |> List.to_seq |> Hashtbl.of_seq

let program_outgoing (node : Abs.node) : (ident, Abs.transition list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Abs.transition) ->
      let prev = Hashtbl.find_opt tbl t.src |> Option.value ~default:[] in
      Hashtbl.replace tbl t.src (t :: prev))
    node.trans;
  tbl

let classify_case ~(analysis : Product_build.analysis) (dst : PT.product_state) : PT.step_class =
  if analysis.assume_bad_idx >= 0 && dst.assume_state = analysis.assume_bad_idx then PT.Bad_assumption
  else if analysis.guarantee_bad_idx >= 0 && dst.guarantee_state = analysis.guarantee_bad_idx then
    PT.Bad_guarantee
  else PT.Safe

let product_transitions ~(analysis : Product_build.analysis) ~(node : Abs.node) :
    Abs.product_contract list =
  let transition_indices = transition_indices node in
  let prog_outgoing = program_outgoing node in
  let assume_outgoing = automaton_outgoing analysis.assume_grouped_edges in
  let guarantee_outgoing = automaton_outgoing analysis.guarantee_grouped_edges in
  let groups = Hashtbl.create 32 in
  let order = ref [] in
  let seen = Hashtbl.create 64 in
  let q = Queue.create () in
  let push_state st =
    if not (Hashtbl.mem seen st) then (
      Hashtbl.add seen st ();
      Queue.add st q)
  in
  push_state analysis.exploration.initial_state;
  while not (Queue.is_empty q) do
    let src = Queue.take q in
    let prog_edges = Hashtbl.find_opt prog_outgoing src.prog_state |> Option.value ~default:[] in
    let assume_edges = edges_from_outgoing assume_outgoing src.assume_state in
    let guarantee_edges = edges_from_outgoing guarantee_outgoing src.guarantee_state in
    List.iter
      (fun (prog_transition : Abs.transition) ->
        match Hashtbl.find_opt transition_indices prog_transition with
        | None -> ()
        | Some program_transition_index ->
            List.iter
              (fun (((_assume_src, assume_guard_raw, assume_dst) as assume_edge) :
                    Automaton_types.transition) ->
                List.iter
                  (fun (((_guarantee_src, guarantee_guard_raw, guarantee_dst) as guarantee_edge) :
                        Automaton_types.transition) ->
                    let dst =
                      {
                        PT.prog_state = prog_transition.dst;
                        assume_state = assume_dst;
                        guarantee_state = guarantee_dst;
                      }
                    in
                    push_state dst;
                    let step_class = classify_case ~analysis dst in
                    let step =
                      {
                        PT.src;
                        dst;
                        prog_transition;
                        prog_guard =
                          (match prog_transition.guard with
                          | None -> Fo_formula.FTrue
                          | Some g -> Fo_specs.iexpr_to_fo_with_atoms [] g |> simplify_fo);
                        assume_edge;
                        assume_guard = simplify_fo assume_guard_raw;
                        guarantee_edge;
                        guarantee_guard = simplify_fo guarantee_guard_raw;
                        step_class;
                      }
                    in
                    if is_relevant_product_step ~analysis step then (
                      let key = (program_transition_index, step.src, step.assume_edge) in
                      if not (Hashtbl.mem groups key) then order := key :: !order;
                      let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
                      Hashtbl.replace groups key ((step, program_transition_index) :: previous)))
                  guarantee_edges)
              assume_edges)
      prog_edges
  done;
  List.rev !order
  |> List.filter_map (fun key ->
         match Hashtbl.find_opt groups key with
         | None -> None
         | Some grouped ->
             let grouped = List.rev grouped in
             let ((repr_step : PT.product_step), program_transition_index) = List.hd grouped in
             let safe_guards =
               grouped
               |> List.filter_map (fun ((step : PT.product_step), _) ->
                      match step.step_class with
                      | PT.Safe -> Some step.guarantee_guard
                      | PT.Bad_assumption | PT.Bad_guarantee -> None)
             in
             let first_safe_dst =
               grouped
               |> List.find_map (fun ((step : PT.product_step), _) ->
                      match step.step_class with
                      | PT.Safe -> Some step.dst
                      | PT.Bad_assumption | PT.Bad_guarantee -> None)
             in
             let cases =
               grouped
               |> List.filter_map (fun ((step : PT.product_step), _) ->
                      match step.step_class with
                      | PT.Bad_assumption -> None
                      | PT.Safe ->
                          Some
                            {
                              Abs.step_class = product_step_class_of_pt step.step_class;
                              product_dst = product_state_of_pt step.dst;
                              guarantee_guard = step.guarantee_guard;
                              propagates =
                                [ Abs.with_origin GuaranteeAutomaton (ltl_of_fo step.guarantee_guard) ];
                              ensures = [];
                              forbidden = [];
                            }
                      | PT.Bad_guarantee ->
                          Some
                            {
                              Abs.step_class = product_step_class_of_pt step.step_class;
                              product_dst = product_state_of_pt step.dst;
                              guarantee_guard = step.guarantee_guard;
                              propagates = [];
                              ensures = [];
                              forbidden =
                                [ Abs.with_origin GuaranteeViolation (ltl_of_fo step.guarantee_guard) ];
                            })
             in
             Some
               {
                 program_transition_index;
                 Abs.product_src = product_state_of_pt repr_step.src;
                 assume_guard = repr_step.assume_guard;
                 requires = [];
                 ensures =
                   (match (disj_fo safe_guards, first_safe_dst) with
                   | Some grouped, Some _first_dst -> [ Abs.with_origin Internal grouped ]
                   | _ -> []);
                 cases;
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
