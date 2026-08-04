(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

(* Complete surface transitions with the observer updates they require. *)
open Surface.Syntax
open Core.Syntax
module S = Surface.Ast

(* Append the scheduled observer assignments to one transition. *)
let expand_observers_in_transition ~init_state schedule (t : S.transition) =
  { t with body = t.body @ Observers.observer_updates_for_transition ~init_state schedule t }

(* Recognize an unconditional transition originating in [state]. *)
let is_catch_all_transition_from state (transition : S.transition) =
  String.equal transition.src state
  &&
  match transition.guard with
  | None -> true
  | Some { sexpr = SELitBool true; _ } -> true
  | Some _ -> false

(* [complete_observer_transitions (n : S.node)] implements the internal complete observer transitions operation. It returns the operation result. *)
let complete_observer_transitions (n : S.node) =
  if n.observers = [] then n.transitions
  else
    let states_without_catch_all =
      n.state_decls.states
      |> List.filter (fun state ->
             not (List.exists (is_catch_all_transition_from state) n.transitions))
    in
    if List.mem n.state_decls.init_state states_without_catch_all then
      Shared.Error.well_formedness
        (Printf.sprintf
           "observer initialization in node '%s' requires a catch-all transition from initial state '%s'; an implicit fallback would return to the initial state"
           n.node_name n.state_decls.init_state);
    let fallbacks =
      states_without_catch_all
      |> List.map (fun state : S.transition ->
             {
               src = state;
               dst = state;
               guard = None;
               body = [];
               ensures = [];
             })
    in
    n.transitions @ fallbacks

(* [lower_contracts ~hide_init env contracts] transforms lower contracts. It returns the transformed representation. *)
