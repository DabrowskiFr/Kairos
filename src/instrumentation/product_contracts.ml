open Ast
open Ast_builders

module Abs = Abstract_model
module PT = Product_types

let instrumentation_state_name = "__aut_state"
let instrumentation_state_expr i = mk_var (Printf.sprintf "Aut%d" i)

let add_unique origin f lst =
  if List.exists (fun (fo : fo_o) -> fo.value = f) lst then lst
  else lst @ [ Ast_provenance.with_origin origin f ]

let mk_or = function
  | [] -> LFalse
  | f :: rest -> List.fold_left (fun acc x -> LOr (acc, x)) f rest

let compat_invariants ~(node : Abs.node) ~(analysis : Product_build.analysis) :
    invariant_state_rel list =
  let by_prog = Hashtbl.create 16 in
  List.iter
    (fun (st : PT.product_state) ->
      let prev = Hashtbl.find_opt by_prog st.prog_state |> Option.value ~default:[] in
      if List.mem st.guarantee_state prev then ()
      else Hashtbl.replace by_prog st.prog_state (st.guarantee_state :: prev))
    analysis.exploration.states;
  node.semantics.sem_states
  |> List.map (fun state ->
         let gs = Hashtbl.find_opt by_prog state |> Option.value ~default:[] |> List.sort_uniq compare in
         let formulas =
           gs
           |> List.map (fun g ->
                  LAtom (FRel (HNow (mk_var instrumentation_state_name), REq, HNow (instrumentation_state_expr g))))
         in
         let formula = mk_or formulas in
         { is_eq = true; state; formula })

let transition_matches (t1 : Abs.transition) (t2 : Abs.transition) =
  t1.src = t2.src && t1.dst = t2.dst && t1.guard = t2.guard

let add_assumption_projection_requires ?(log = None) ~(build : Automata_generation.automata_build)
    ~(analysis : Product_build.analysis) (trans : Abs.transition list) : Abs.transition list =
  match build.assume_automaton with
  | None -> trans
  | Some _ ->
      List.map
        (fun (t : Abs.transition) ->
          let by_gsrc = Hashtbl.create 8 in
          List.iter
            (fun (step : PT.product_step) ->
              if transition_matches t step.prog_transition
                 && step.step_class <> PT.Bad_assumption
                 && step.src.assume_state <> analysis.assume_bad_idx
                 && step.src.guarantee_state <> analysis.guarantee_bad_idx
              then
                let prev = Hashtbl.find_opt by_gsrc step.src.guarantee_state |> Option.value ~default:[] in
                let f = LAnd (step.assume_guard, step.guarantee_guard) in
                Hashtbl.replace by_gsrc step.src.guarantee_state (f :: prev))
            analysis.exploration.steps;
          let reqs =
            Hashtbl.fold
              (fun gsrc formulas acc ->
                let body = mk_or formulas in
                let cond =
                  LAtom (FRel (HNow (mk_var instrumentation_state_name), REq, HNow (instrumentation_state_expr gsrc)))
                in
                LImp (cond, body) :: acc)
              by_gsrc []
          in
          List.iter (fun f -> Option.iter (fun l -> l t f) log) reqs;
          { t with requires = List.fold_left (fun acc f -> add_unique AssumeAutomaton f acc) t.requires reqs })
        trans

let add_bad_guarantee_projection_ensures ?(log = None) ~(analysis : Product_build.analysis)
    (trans : Abs.transition list) : Abs.transition list =
  List.map
    (fun (t : Abs.transition) ->
      let by_gsrc = Hashtbl.create 8 in
      List.iter
        (fun (step : PT.product_step) ->
          if transition_matches t step.prog_transition
             && step.step_class = PT.Bad_guarantee
             && step.src.assume_state <> analysis.assume_bad_idx
             && step.src.guarantee_state <> analysis.guarantee_bad_idx
          then
            let prev = Hashtbl.find_opt by_gsrc step.src.guarantee_state |> Option.value ~default:[] in
            let f = LAnd (step.assume_guard, step.guarantee_guard) in
            Hashtbl.replace by_gsrc step.src.guarantee_state (f :: prev))
        analysis.exploration.steps;
      let enss =
        Hashtbl.fold
          (fun gsrc formulas acc ->
            let cond =
              LAtom (FRel (HNow (mk_var instrumentation_state_name), REq, HNow (instrumentation_state_expr gsrc)))
            in
            let bad_case = mk_or formulas in
            LImp (cond, LNot bad_case) :: acc)
          by_gsrc []
      in
      List.iter (fun f -> Option.iter (fun l -> l t f) log) enss;
      { t with ensures = List.fold_left (fun acc f -> add_unique Instrumentation f acc) t.ensures enss })
    trans
