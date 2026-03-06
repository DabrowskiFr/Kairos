open Ast
open Automata_generation

type context = {
  grouped : Automaton_engine.transition list;
  states : Automaton_engine.residual_state list;
  incoming_prev_fo_shifted : fo list;
  compat_invariants : invariant_state_rel list;
  bad_state_fo_opt : fo option;
}

module Abs = Abstract_model

type hooks = {
  add_not_bad_state_requires :
    ?log:(Abs.transition -> fo -> unit) option ->
    bad_state_fo_opt:fo option ->
    Abs.transition list ->
    Abs.transition list;
  add_monitor_compatibility_requires :
    ?log:(Abs.transition -> fo -> unit) option ->
    incoming_prev_fo_shifted:fo list ->
    Abs.transition list ->
    Abs.transition list;
  add_assumption_state_aware_requires :
    ?log:(Abs.transition -> fo -> unit) option ->
    instrumentation_grouped:Automaton_engine.transition list ->
    instrumentation_states:Automaton_engine.residual_state list ->
    assume_grouped:Automaton_engine.transition list ->
    assume_states:Automaton_engine.residual_state list ->
    assume_bad_idx:int ->
    assume_atom_map_exprs:(ident * iexpr) list ->
    assume_atom_name_to_fo:(ident * fo) list ->
    Abs.transition list ->
    Abs.transition list;
  add_state_invariants_to_transitions :
    invariants_state_rel:invariant_state_rel list ->
    ?log:(Abs.transition -> fo -> unit) option ->
    ?add_to_ensures:bool ->
    Abs.transition list ->
    Abs.transition list;
}

let apply ~(build : automata_build) ~(ctx : context) ~(trans : Abs.transition list)
    ~(log_contract : reason:string -> t:Abs.transition -> fo -> unit) ~(hooks : hooks) :
    Abs.transition list =
  let trans =
    hooks.add_not_bad_state_requires
      ~log:(Some (fun t f -> log_contract ~reason:"GenHyp/no_bad_state" ~t f))
      ~bad_state_fo_opt:ctx.bad_state_fo_opt trans
  in
  let trans =
    hooks.add_monitor_compatibility_requires
      ~log:(Some (fun t f -> log_contract ~reason:"GenHyp/monitor_pre (compat)" ~t f))
      ~incoming_prev_fo_shifted:ctx.incoming_prev_fo_shifted trans
  in
  let trans =
    match (build.assume_automaton, build.assume_atoms) with
    | Some a, Some assume_atoms ->
        let assume_states = a.states in
        let assume_grouped = a.grouped in
        let assume_bad_idx =
          let rec find i = function [] -> -1 | LFalse :: _ -> i | _ :: tl -> find (i + 1) tl in
          find 0 assume_states
        in
        let assume_atom_map_exprs = assume_atoms.atom_named_exprs in
        let assume_atom_name_to_fo =
          List.map (fun (af, name) -> (name, af)) assume_atoms.atom_map
        in
        hooks.add_assumption_state_aware_requires
          ~log:(Some (fun t f -> log_contract ~reason:"GenHyp/assume_state_aware" ~t f))
          ~instrumentation_grouped:ctx.grouped ~instrumentation_states:ctx.states ~assume_grouped ~assume_states
          ~assume_bad_idx ~assume_atom_map_exprs ~assume_atom_name_to_fo trans
    | _ -> trans
  in
  hooks.add_state_invariants_to_transitions ~invariants_state_rel:ctx.compat_invariants
    ~log:(Some (fun t f -> log_contract ~reason:"GenHyp/compat_invariant" ~t f))
    ~add_to_ensures:false trans
