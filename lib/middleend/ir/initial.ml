open Ast
module Abs = Ir

let add_initial_invariant_goal (n : Abs.node) ~(inv_of_state : ident -> ltl option) : Abs.node =
  match inv_of_state n.semantics.sem_init_state with
  | None -> n
  | Some inv ->
      let existing_values =
        List.map (fun (f : Abs.contract_formula) -> f.logic) n.coherency_goals
      in
      if List.mem inv existing_values then n
      else
        {
          n with
          coherency_goals =
            n.coherency_goals @ [ Abs.with_origin Formula_origin.Invariant inv ];
        }

let apply (n : Abs.node) : Abs.node =
  n |> add_initial_invariant_goal ~inv_of_state:(Invariant.invariant_of_state n)

let apply_program (p : Abs.node list) : Abs.node list = List.map apply p
